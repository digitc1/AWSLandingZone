#!/usr/bin/python -u

import sys, getopt
import subprocess, pkg_resources
import os
import subprocess
import shlex
import logging
import time
import boto3
import botocore
import json
import threading
import cursor
import yaml
from cfn_tools import load_yaml, dump_yaml

from datetime import datetime
from enum import Enum
from colorama import Fore, Back, Style
from botocore.exceptions import BotoCoreError, ClientError, ProfileNotFound
from botocore.config import Config

regions = ["ap-northeast-1","ap-northeast-2","ap-northeast-3","ap-south-1","ap-southeast-1","ap-southeast-2","ca-central-1","eu-central-1","eu-north-1","eu-west-2","eu-west-3","sa-east-1","us-east-1","us-east-2","us-west-1","us-west-2"]
    

def main(argv):
    
    verbosity = logging.ERROR
    start_time = time.time()
  
    sseclog_profile = None
    sseclog_id = None

    tseclog_profile = None
    tseclog_id = None
    tseclog_SecLog_sns_arn = None

    account_profile = None
    account_id = None
    account_email = None
    stored_SecLog_sns_arn = None

    organisation_profile = None
    organisation_id = None
    


    
    boto3_config = Config(
        retries = dict(
            max_attempts = 10
        )
    )

    try:
        opts, args = getopt.getopt(argv,"hva:s:t:o:",["account", "sseclog", "tseclog", "org", "verbose"])
    except getopt.GetoptError:
        usage()
        sys.exit(2)
    
    print("#######")
    print("####### AWS Landing Zone switch SECLOG script")
    print("")


    # Parsing script parameters
    for opt, arg in opts:
        if opt == '-h':
            usage()
            sys.exit()
        if opt in ("-v", "--verbose"):
            verbosity = logging.DEBUG
        if opt in ("-a", "--account"):
            if not arg:
                print(f"Account profile has not been provided. [{Status.FAIL.value}]")
                usage()
                sys.exit(1)
            else:
                account_profile = arg
        
        if opt in ("-s", "--sseclog"):
            if not arg:
                print(f"Source SECLOG profile has not been provided. [{Status.FAIL.value}]")
                usage()
                sys.exit(1)
            else:
                sseclog_profile = arg
        if opt in ("-t", "--tseclog"):
            if not arg:
                print(f"Target SECLOG profile has not been provided. [{Status.FAIL.value}]")
                usage()
                sys.exit(1)
            else:
                tseclog_profile = arg
        if opt in ("-o", "--org"):
            if not arg:
                print(f"Organisation profile has not been provided. [{Status.FAIL.value}]")
                usage()
                sys.exit(1)
            else:
                organisation_profile = arg
        
    
    logging.basicConfig(level=verbosity)

    # Identify accounts

    

    # linked account
    print(f"Account to be moved : {account_profile}")
    boto3.setup_default_session(
        profile_name=account_profile,
        region_name='eu-west-1',
    )
    account_id = get_account_id()

    print(f"Account ID : {account_id}")
    
    # get stored seclog_id from ssm parameter
    ssm = boto3.client('ssm')
    response = ssm.get_parameter(Name='/org/member/SecLogMasterAccountId')
    if 'Value' in response['Parameter']:
        stored_sseclog_id = response['Parameter']['Value']
    else:
        print(f"LZ not configured on this account. [{Status.FAIL.value}]")
        print("Exiting...")
        sys.exit(1)
        
    response = ssm.get_parameter(Name='/org/member/SecLog_sns_arn')
    if 'Value' in response['Parameter']:
        stored_SecLog_sns_arn = response['Parameter']['Value']
    else:
        print(f"SecLog_sns_arn not configured on this account. [{Status.FAIL.value}]")
        print("Exiting...")
        sys.exit(1)
    print(f"Linked account identified. [{Status.OK.value}]")
    print("")

    # organisation account
    print(f"Organisation account : {organisation_profile}")
    boto3.setup_default_session(
        profile_name=organisation_profile,
        region_name='eu-west-1',
    )
    organisation_id = get_account_id()
    organizations = boto3.client('organizations')
    response = organizations.describe_account(AccountId=account_id)
    account_email = response['Account']['Email']

    print(f"Account ID : {organisation_id}")
    print(f"Organisation account identified. [{Status.OK.value}]")
    print("")

    # original seclog account
    print(f"Original SECLOG account : {sseclog_profile}")
    boto3.setup_default_session(
        profile_name=sseclog_profile,
        region_name='eu-west-1',
    )
    sseclog_id = get_account_id()
    print(f"Account ID : {sseclog_id}")
    if (is_seclog() == False):
        print(f"Not a SECLOG account. [{Status.FAIL.value}]")
        print("Exiting...")
        sys.exit(1)
    elif (sseclog_id != stored_sseclog_id):
        print(f"Not the original SECLOG for account {account_profile} ({account_id}). [{Status.FAIL.value}]")
        print("Exiting...")
        sys.exit(1)
    else:
        print(f"Source SECLOG account identified. [{Status.OK.value}]")
    print("")

    # target seclog account
    print(f"Target SECLOG account : {tseclog_profile}")
    boto3.setup_default_session(
        profile_name=tseclog_profile,
        region_name='eu-west-1',
    )
    tseclog_id = get_account_id()
    print(f"Account ID : {tseclog_id}")
    if (is_seclog() == False):
        print(f"Not a SECLOG account. [{Status.FAIL.value}]")
        print("Exiting...")
        sys.exit(1)
    else:
        print(f"Target SECLOG account identified. [{Status.OK.value}]")
        ssm = boto3.client('ssm')
        response = ssm.get_parameter(Name='/org/member/SecLog_sns_arn')
        if 'Value' in response['Parameter']:
            tseclog_SecLog_sns_arn = response['Parameter']['Value']
        else:
            print(f"SecLog_sns_arn not configured on this account. [{Status.FAIL.value}]")
            print("Exiting...")
            sys.exit(1)
    print("")


    # Cleaning up linked account

    print(f"Migrating linked account {account_profile} from SECLOG {sseclog_profile} to SECLOG {tseclog_profile}")
    print("")
    boto3.setup_default_session(
        profile_name=account_profile,
        region_name='eu-west-1',
    )

    # guardduty
    guardduty = boto3.client('guardduty')
    detector_response = guardduty.list_detectors()
    for detector in detector_response['DetectorIds']:
        try:
            response = guardduty.disassociate_from_master_account(
                DetectorId=detector
            )
            response = guardduty.delete_invitations(AccountIds=[
                sseclog_id,
            ])
            print(f"Disassociate GuardDuty from master account: [{Status.OK.value}]")
        except botocore.exceptions.ClientError as error:
            if error.response['Error']['Code'] == 'BadRequestException':
                if 'is not associated' in error.response['Error']['Message']:
                    print(f"Disassociate GuardDuty from master account [{Status.NO_ACTION.value}]")
                else:
                    print(f"Disassociate GuardDuty from master account [{Status.FAIL.value}]")
                    print(error.response['Error']['Message'])
                    print("Exiting...")
                    sys.exit(1)
            else:
                print(f"Disassociate GuardDuty from master account [{Status.FAIL.value}]")
                print(error.response['Error']['Message'])
                print("Exiting...")
                sys.exit(1)

    # security hub
    securityhub = boto3.client('securityhub')
    try:
        response = securityhub.disassociate_from_master_account()
        response = securityhub.delete_invitations(AccountIds=[
            sseclog_id,
        ])
        print(f"Disassociate SecurityHub from master account: [{Status.OK.value}]")
    except botocore.exceptions.ClientError as error:
        if error.response['Error']['Code'] == 'BadRequestException':
            if 'is not associated' in error.response['Error']['Message']:
                print(f"Disassociate SecurityHub from administrator account [{Status.NO_ACTION.value}]")
            else:
                print(f"Disassociate SecurityHub from administrator account [{Status.FAIL.value}]")
                print(error.response['Error']['Message'])
                print("Exiting...")
                sys.exit(1)
        else:
            print(f"Disassociate SecurityHub from administrator account [{Status.FAIL.value}]")
            print(error.response['Error']['Message'])
            print("Exiting...")
            sys.exit(1)

    # SSM parameter
    ssm = boto3.client('ssm')
    if stored_sseclog_id == tseclog_id:
        print(f"Update SecLogMasterAccountId SSM parameter [{Status.NO_ACTION.value}]")
    else:
        try:
            client.put_parameter(
                Name='/org/member/SecLogMasterAccountId',
                Value=tseclog_id,
                Type='String',
                Overwrite=True|False)
            print(f"Update SecLogMasterAccountId SSM parameter [{Status.OK.value}]")
        except botocore.exceptions.ClientError as error:
            print(f"Update SecLogMasterAccountId SSM parameter [{Status.FAIL.value}]")
            print(error.response['Error']['Message'])
            print("Exiting...")
            sys.exit(1)

    if stored_SecLog_sns_arn == tseclog_SecLog_sns_arn:
        print(f"Update SecLog_sns_arn SSM parameter [{Status.NO_ACTION.value}]")
    else:
        try:
            client.put_parameter(
                Name='/org/member/SecLog_sns_arn',
                Value=tseclog_SecLog_sns_arn,
                Type='String',
                Overwrite=True|False)
            print(f"Update SecLog_sns_arn SSM parameter [{Status.OK.value}]")
        except botocore.exceptions.ClientError as error:
            print(f"Update SecLog_sns_arn SSM parameter [{Status.FAIL.value}]")
            print(error.response['Error']['Message'])
            print("Exiting...")
            sys.exit(1)

    # Delete instances from original seclog account

    boto3.setup_default_session(
        profile_name=sseclog_profile,
        region_name='eu-west-1',
    )

    #remove_stacks_from_stackset('SECLZ-Enable-Config-SecurityHub-Globally', account_id)
    #remove_stacks_from_stackset('SECLZ-Enable-Guardduty-Globally', account_id)

    # Re-apply CFN
    boto3.setup_default_session(
        profile_name=account_profile,
        region_name='eu-west-1',
    )

    #update_stack('SECLZ-StackSetExecutionRole')
    #update_stack('SECLZ-config-cloudtrail-SNS')
    #update_stack('SECLZ-Guardduty-detector')
    #update_stack('SECLZ-SecurityHub')
    #update_stack('SECLZ-Notifications-Cloudtrail')
    
    # Re-apply Stackset from Target SECLOG
    boto3.setup_default_session(
        profile_name=tseclog_profile,
        region_name='eu-west-1',
    )

    #add_stacks_from_stackset('SECLZ-Enable-Config-SecurityHub-Globally', account_id)
    #add_stacks_from_stackset('SECLZ-Enable-Guardduty-Globally', account_id)
    
    # associate guardduty with new SECLOG
    # issue invitation
    guardduty = boto3.client('guardduty')
    detector_response = guardduty.list_detectors()
    for detector in detector_response['DetectorIds']:
        try:
           
            response = guardduty.create_members(
                DetectorId=detector,
                AccountDetails=[
                    {
                        'AccountId': account_id,
                        'Email': account_email
                    },
                ]
            )
            response = guardduty.invite_members(
                DetectorId=detector,
                AccountIds=[
                    account_id,
                ],
                DisableEmailNotification=True
            )
            print(f"Issue invitation for GuardDuty from SECLOG {tseclog_profile} account [{Status.OK.value}]")
        except botocore.exceptions.ClientError as error:
            if error.response['Error']['Code'] == 'BadRequestException':
                if 'is not associated' in error.response['Error']['Message']:
                    print(f"Issue invitation for GuardDuty from SECLOG {tseclog_profile} account [{Status.NO_ACTION.value}]")
                else:
                    print(f"Issue invitation for GuardDuty from SECLOG {tseclog_profile} account [{Status.FAIL.value}]")
                    print(error.response['Error']['Message'])
                    print("Exiting...")
                    sys.exit(1)
            else:
                print(f"Issue invitation for GuardDuty from SECLOG {tseclog_profile} account [{Status.FAIL.value}]")
                print(error.response['Error']['Message'])
                print("Exiting...")
                sys.exit(1)

    # accept invitation
    boto3.setup_default_session(
        profile_name=account_profile,
        region_name='eu-west-1',
    )

    guardduty = boto3.client('guardduty')
    detector_response = guardduty.list_detectors()
    for detector in detector_response['DetectorIds']:
        try:
            response = guardduty.list_invitations()
            response = guardduty.accept_invitation(
                DetectorId=detector,
                MasterId=tseclog_id,
                InvitationId=response['Invitations'][0]['InvitationId']
            )
            
            print(f"Aassociate GuardDuty detector linked account to SECLOG {tseclog_profile} account [{Status.OK.value}]")
        except botocore.exceptions.ClientError as error:
            if error.response['Error']['Code'] == 'BadRequestException':
                if 'is not associated' in error.response['Error']['Message']:
                    print(f"Aassociate GuardDuty from linked account to SECLOG {tseclog_profile} account [{Status.NO_ACTION.value}]")
                else:
                    print(f"Aassociate GuardDuty from linked account to SECLOG {tseclog_profile} account [{Status.FAIL.value}]")
                    print(error.response['Error']['Message'])
                    print("Exiting...")
                    sys.exit(1)
            else:
                print(f"Aassociate GuardDuty from linked account to SECLOG {tseclog_profile} account [{Status.FAIL.value}]")
                print(error.response['Error']['Message'])
                print("Exiting...")
                sys.exit(1)

    # associate securityhub with new SECLOG
    # issue invitation
    boto3.setup_default_session(
        profile_name=tseclog_profile,
        region_name='eu-west-1',
    )

    securityhub = boto3.client('securityhub')
    try:
        response = securityhub.create_members(
            AccountDetails=[
                {
                    'AccountId': account_id,
                    'Email': account_email
                },
            ]
        )
        response = securityhub.invite_members(
            AccountIds=[
                account_id,
            ]
        )
        print(f"Issue invitation for SecurityHub from SECLOG {tseclog_profile} account: [{Status.OK.value}]")
    except botocore.exceptions.ClientError as error:
        if error.response['Error']['Code'] == 'BadRequestException':
            if 'is not associated' in error.response['Error']['Message']:
                print(f"Issue invitation for SecurityHub from SECLOG {tseclog_profile} account [{Status.NO_ACTION.value}]")
            else:
                print(f"Issue invitation for SecurityHub from SECLOG {tseclog_profile} account [{Status.FAIL.value}]")
                print(error.response['Error']['Message'])
                print("Exiting...")
                sys.exit(1)
        else:
            print(f"Issue invitation for SecurityHub from SECLOG {tseclog_profile} account [{Status.FAIL.value}]")
            print(error.response['Error']['Message'])
            print("Exiting...")
            sys.exit(1)
   
    # accept invitation
    boto3.setup_default_session(
        profile_name=account_profile,
        region_name='eu-west-1',
    )

    securityhub = boto3.client('securityhub')
    try:
        response = securityhub.list_invitations()
        response = securityhub.accept_invitation(
            MasterId=tseclog_id,
            InvitationId=response['Invitations'][0]['InvitationId']
        )
        
        print(f"Aassociate SecurityHub detector linked account to SECLOG {tseclog_profile} account [{Status.OK.value}]")
    except botocore.exceptions.ClientError as error:
        if error.response['Error']['Code'] == 'BadRequestException':
            if 'is not associated' in error.response['Error']['Message']:
                print(f"Aassociate SecurityHub from linked account to SECLOG {tseclog_profile} account [{Status.NO_ACTION.value}]")
            else:
                print(f"Aassociate SecurityHub from linked account to SECLOG {tseclog_profile} account [{Status.FAIL.value}]")
                print(error.response['Error']['Message'])
                print("Exiting...")
                sys.exit(1)
        else:
            print(f"Aassociate SecurityHub from linked account to SECLOG {tseclog_profile} account [{Status.FAIL.value}]")
            print(error.response['Error']['Message'])
            print("Exiting...")
            sys.exit(1)

    print("")
    print(f"####### AWS Landing Zone switch SECLOG script finished. Executed in {time.time() - start_time} seconds")
    print("#######")
    print("")

def usage():
    """
    This function prints the script usage
    """
    print('Usage:')
    print('')
    print('python EC-Switch-Seclog.py -a <account profile> [-s <seclog profile>] [-v]')
    print('')
    print('   Provide ')
    print('   -a --account         : The AWS profile of the linked account to be switched')
    print('   -s --sseclog         : The AWS profile of the source SECLOG account')
    print('   -t --tseclog         : The AWS profile of the target SECLOG account')
    print('   -o --org             : The AWS profile of the Organisation account')
    print('   -v --verbose         : Debug mode - optional')


def get_account_id():
    """
    This function gets te id of the account defined in the profile
        :param force: flag to force the retrieval of the account ID 
        :return: a string with the account id 
    """

    sts = boto3.client('sts')
    try:
        response = sts.get_caller_identity()
        return response['Account']
    except ClientError as error:
        if error.response['Error']['Code'] == 'AccessDenied':
            print(f"Access denied getting account id [{Status.FAIL.value}]")
            print("Exiting...") 
            sys.exit(1)
        else:
            raise error

def is_seclog():
    """
    Function that checks if the account is a seclog account
        :return: true or false
    """
    client = boto3.client('ssm')
    seclog_account_id = get_account_id()
    response = client.get_parameter(Name='/org/member/SecLogMasterAccountId')
    if not 'Value' not in response or seclog_account_id != response['Parameter']['Value']:
        return False
    return True

def remove_stacks_from_stackset(stackset,account_id):
    
    global regions

    print(f"Remove stacks from StackSet {stackset} in progress ", end="")

    cfn = boto3.client('cloudformation')
    response = cfn.describe_stack_set(StackSetName=stackset)
   
    if response['StackSet']['Status'] not in ('ACTIVE'):
        print(f"Cannot remove stacks from stackset {stackset}. Current stackset status is: {response['StackSet']['Status']} [{Status.FAIL.value}]")
        print("Exiting...")
        sys.exit(1)
   
    with Spinner():
        filter=[{
            'Name': 'DETAILED_STATUS',
            'Values': 'PENDING'
        }]
        response = cfn.list_stack_instances(StackSetName=stackset,Filters=filter)

        while(len(response['Summaries']) > 0):
            time.sleep(1)
            response = cfn.list_stack_instances(StackSetName=stackset,Filters=filter)

        try:
            operationPreferences={
                'RegionConcurrencyType': 'PARALLEL',
                'FailureToleranceCount': 9,
                'MaxConcurrentCount': 10
            }
            cfn.delete_stack_instances(
                StackSetName=stackset, 
                Regions=regions, 
                Accounts=[account_id],
                OperationPreferences=operationPreferences,
                RetainStacks=False
                )

            time.sleep(5)
            response = cfn.list_stack_set_operations(StackSetName=stackset)
            while(any(x['Status'] == "RUNNING" for x in response['Summaries'])):
                time.sleep(10)
                response = cfn.list_stack_set_operations(StackSetName=stackset)
            
        
            print(f"\033[2K\033[1GRemove stacks from StackSet {stackset} [{Status.OK.value}]")
            
        
        except ClientError as error:
            print(f"\033[2K\033[1GRemove stacks from StackSet {stackset} failed. Reason: {error.response['Error']['Message']} [{Status.FAIL.value}]")
            print("Exiting...")
            sys.exit(1)

def add_stacks_from_stackset(stackset,account_id):
    
    global regions

    print(f"Add stacks from StackSet {stackset} in progress ", end="")

    cfn = boto3.client('cloudformation')
    response = cfn.describe_stack_set(StackSetName=stackset)
   
    if response['StackSet']['Status'] not in ('ACTIVE'):
        print(f"Cannot add stacks from stackset {stackset}. Current stackset status is: {response['StackSet']['Status']} [{Status.FAIL.value}]")
        print("Exiting...")
        sys.exit(1)
   
    with Spinner():
        filter=[{
            'Name': 'DETAILED_STATUS',
            'Values': 'PENDING'
        }]
        response = cfn.list_stack_instances(StackSetName=stackset,Filters=filter)

        while(len(response['Summaries']) > 0):
            time.sleep(1)
            response = cfn.list_stack_instances(StackSetName=stackset,Filters=filter)

        try:
            operationPreferences={
                'RegionConcurrencyType': 'PARALLEL',
                'FailureToleranceCount': 9,
                'MaxConcurrentCount': 10
            }
            cfn.create_stack_instances(
                StackSetName=stackset, 
                Regions=regions, 
                Accounts=[account_id],
                OperationPreferences=operationPreferences
                )

            time.sleep(5)
            response = cfn.list_stack_set_operations(StackSetName=stackset)
            while(any(x['Status'] == "RUNNING" for x in response['Summaries'])):
                time.sleep(10)
                response = cfn.list_stack_set_operations(StackSetName=stackset)
            
        
            print(f"\033[2K\033[1GAdd stacks from StackSet {stackset} [{Status.OK.value}]")
            
        
        except ClientError as error:
            print(f"\033[2K\033[1GAdd stacks from StackSet {stackset} failed. Reason: {error.response['Error']['Message']} [{Status.FAIL.value}]")
            print("Exiting...")
            sys.exit(1)



def update_stack(stack):
    """
    Function that updates a stack defined in the parameters
        :stack:         The stack name
        :template_data: dict holding CFT details
        :params:        parameters to be passed to the stack
        :return:        True or False
    """
    client = boto3.client('cloudformation')
    
    capabilities = None
    tags = None
    parameters = None
    template_body = None
    
    print(f"Stack {stack} update ", end="")

    try:
        describe = client.describe_stacks(StackName=stack)
        
        if describe['Stacks'][0]['StackStatus'] not in ('CREATE_COMPLETE', 'UPDATE_COMPLETE','UPDATE_ROLLBACK_COMPLETE'):
            print(f"Cannot update stack {stack}. Current status is : {describe['Stacks'][0]['StackStatus']} [{Status.FAIL.value}]")
            print("Exiting...")
            sys.exit(1)

        if 'Capabilities' in describe['Stacks'][0]:
            capabilities = describe['Stacks'][0]['Capabilities']

        if 'Parameters' in describe['Stacks'][0]:
            parameters = describe['Stacks'][0]['Parameters']

        if 'Tags' in describe['Stacks'][0]:
            tags =  describe['Stacks'][0]['Tags']


        response = client.get_template(StackName=stack)
        template_body = response['TemplateBody']

    except ClientError as err:
        print(f"\033[2K\033[1GStack {stack} update failed. Reason : {err.response['Error']['Message']} [{Status.FAIL.value}]")
        print("Exiting...")
        sys.exit(1)
    

   

        
    print("in progress ", end="")
    
    with Spinner():
        try:
            
            client.update_stack(
                StackName=stack, 
                TemplateBody=template_body, 
                Parameters=parameters, 
                Capabilities=capabilities, 
                Tags=tags)
            updated=False
            while updated == False: 
                try:
                    time.sleep(1)
                    response = client.describe_stacks(StackName=stack)
                    if 'COMPLETE' in response['Stacks'][0]['StackStatus'] :
                        print(f"\033[2K\033[1GStack {stack} update [{Status.OK.value}]")
                        updated=True
                        break
                    elif 'FAILED' in response['Stacks'][0]['StackStatus'] or 'ROLLBACK' in response['Stacks'][0]['StackStatus'] :
                        print(f"\033[2K\033[1GStack {stack} update failed. Reason {response['Stacks'][0]['StackStatusReason']} [{Status.FAIL.value}]")
                        print("Exiting...")
                        sys.exit(1)
                except ClientError as err:
                    if err.response['Error']['Code'] == 'ThrottlingException':
                        continue
                    else:
                        raise err
            
        
        except ClientError as err:
            if err.response['Error']['Code'] == 'AmazonCloudFormationException':
                print(f"\033[2K\033[1GStack {stack} not found : {err.response['Error']['Message']} [{Status.FAIL.value}]")
            elif err.response['Error']['Code'] == 'ValidationError' and err.response['Error']['Message'] == 'No updates are to be performed.':
                print(f"\033[2K\033[1GStack {stack} update [{Status.NO_ACTION.value}]")
            else:
                print(f"\033[2K\033[1GStack {stack} update failed. Reason : {err.response['Error']['Message']} [{Status.FAIL.value}]")


class Status(Enum):
    FAIL = Fore.RED + "FAIL" + Style.RESET_ALL
    OK = Fore.GREEN + "OK" + Style.RESET_ALL
    NO_ACTION = Fore.YELLOW + "NO ACTION" + Style.RESET_ALL

class Spinner:
    busy = False
    delay = 0.1

    @staticmethod
    def spinning_cursor():
        while 1: 
            for cursor in '⠄⠆⠇⠋⠙⠸⠰⠠⠰⠸⠙⠋⠇⠆': yield cursor

    def __init__(self, delay=None):
        cursor.hide()
        self.spinner_generator = self.spinning_cursor()
        if delay and float(delay): self.delay = delay

    def spinner_task(self):
        
        while self.busy:
            sys.stdout.write(next(self.spinner_generator))
            sys.stdout.flush()
            time.sleep(self.delay)
            sys.stdout.write('\b')
            sys.stdout.flush()

    def __enter__(self):
        self.busy = True
        threading.Thread(target=self.spinner_task).start()

    def __exit__(self, exception, value, tb):
        self.busy = False
        time.sleep(self.delay)
        cursor.show()
        if exception is not None:
            return False

if __name__ == "__main__":
    main(sys.argv[1:])


