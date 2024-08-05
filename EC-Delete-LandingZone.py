#!/usr/bin/python -u
import signal
import sys, getopt
import subprocess, pkg_resources
import os
import subprocess
import shlex
import logging
import time
import boto3
import boto3.session
import botocore
import json
import threading
import cursor
import yaml

from datetime import datetime
from enum import Enum
from colorama import Fore, Back, Style
from botocore.exceptions import BotoCoreError, ClientError, ProfileNotFound
from botocore.config import Config

regions = ["ap-northeast-1","ap-northeast-2","ap-northeast-3","ap-south-1","ap-southeast-1","ap-southeast-2","ca-central-1","eu-central-1","eu-north-1","eu-west-2","eu-west-3","sa-east-1","us-east-1","us-east-2","us-west-1","us-west-2"]

def main(argv):
    
    verbosity = logging.ERROR
    start_time = time.time()
  
    seclog_profile = None
    seclog_id = None

    account_profile = None
    account_id = None
    stored_seclog_id = None

    try:
        opts, args = getopt.getopt(argv,"hva:s:",["account", "seclog", "verbose"])
    except getopt.GetoptError:
        usage()
        sys.exit(2)
    
    print("#######")
    print("####### AWS Landing Zone delete script")
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
        
        if opt in ("-s", "--seclog"):
            if not arg:
                print(f"Source SECLOG profile has not been provided. [{Status.FAIL.value}]")
                usage()
                sys.exit(1)
            else:
                seclog_profile = arg
        
    
    logging.basicConfig(level=verbosity)

    # linked account
    
    print(f"Account to be processed : {account_profile}")
    account_session=boto3.Session(profile_name=account_profile, region_name ='eu-west-1')
    
    account_id = get_account_id(account_session)

    print(f"Account ID : {account_id}")
    
    # get stored seclog_id from ssm parameter
    ssm = account_session.client('ssm')
    try:
        response = ssm.get_parameter(Name='/org/member/SecLogMasterAccountId')
        stored_seclog_id = response['Parameter']['Value']
        if is_seclog(account_session) == True:
            print(f"This is a SECLOG account. Deletion script only works on linked accounts. [{Status.FAIL.value}]")
            print("Exiting...")
            sys.exit(1)
    except ClientError as err:
        print(f"LZ not configured on this account. [{Status.FAIL.value}]")
        print("Exiting...")
        sys.exit(1)

    # seclog account
    print(f"Associated SECLOG account : {seclog_profile}")
    seclog_session=boto3.Session(profile_name=seclog_profile, region_name ='eu-west-1')

    seclog_id = get_account_id(seclog_session)
    print(f"Account ID : {seclog_id}")
    if (is_seclog(seclog_session) == False):
        print(f"Pofile {seclog_profile} is not a SECLOG account. [{Status.FAIL.value}]")
        print("Exiting...")
        sys.exit(1)
    elif (seclog_id != stored_seclog_id):
        print(f"Not the SECLOG for account {account_profile} ({account_id}). [{Status.FAIL.value}]")
        print("Exiting...")
        sys.exit(1)
    else:
        print(f"SECLOG account identified. [{Status.OK.value}]")
    print("")

    input(f"####### All seems in good shape. Press any key to continue (Ctrl+C to cancel)")

    print("")

    # Cleaning up linked account
    print("#######")
    print(f"####### Deleting Landing Zone from account {account_profile}")
    print("#######")
    print("")

    # deactivate guardduty from source SECLOG
    deactivate_guardduty(seclog_id,account_session)

    # deactivate securityhub from source SECLOG
    deactivate_securityhub(seclog_id,account_session)

    # deactivate config from source SECLOG
    deactivate_config(account_id,seclog_id,account_session,seclog_session)

    # remove stacks from stackset from source SECLOG
    remove_stacks_from_stackset('SECLZ-Enable-Config-SecurityHub-Globally', account_id,seclog_session)
    remove_stacks_from_stackset('SECLZ-Enable-Guardduty-Globally', account_id,seclog_session)

    # delete stacks from linked account
    delete_stack('SECLZ-Notifications-Cloudtrail',account_session)
    delete_stack('SECLZ-Iam-Password-Policy',account_session)
    delete_stack('SECLZ-SecurityHub',account_session)
    delete_stack('SECLZ-Guardduty-detector',account_session)
    delete_stack('SECLZ-local-SNS-topic',account_session)
    delete_stack('SECLZ-config-cloudtrail-SNS',account_session)
    delete_stack('SECLZ-StackSetExecutionRole',account_session)

    # delete ssm parameters
    delete_ssm_parameter('/org/member/SecLog_notification-mail', account_session)
    delete_ssm_parameter('/org/member/SecLogMasterAccountId', account_session)
    delete_ssm_parameter('/org/member/SecLogOU', account_session)
    delete_ssm_parameter('/org/member/KMSCloudtrailKey_arn', account_session)
    delete_ssm_parameter('/org/member/SLZVersion', account_session)
    delete_ssm_parameter('/org/member/SecLog_cloudtrail-groupname', account_session)
    delete_ssm_parameter('/org/member/SecLog_cloudtrail-group-subscription-filter-name', account_session)
    delete_ssm_parameter('/org/member/SecLog_insight-groupname', account_session)
    delete_ssm_parameter('/org/member/SecLog_insight-group-subscription-filter-name', account_session)
    delete_ssm_parameter('/org/member/SecLog_securityhub-groupname', account_session)
    delete_ssm_parameter('/org/member/SecLog_securityhub-group-subscription-filter-name', account_session)
    delete_ssm_parameter('/org/member/SecLog_config-groupname', account_session)
    delete_ssm_parameter('/org/member/SecLog_config-group-subscription-filter-name', account_session)
    delete_ssm_parameter('/org/member/SecLog_alarms-groupname', account_session)
    delete_ssm_parameter('/org/member/SecLog_config-group-subscription-filter-name', account_session)
    delete_ssm_parameter('/org/member/SecLog_insight-group-subscription-filter-name', account_session)
    for region in regions:
        delete_ssm_parameter('/org/member/SecLog_guardduty-groupname', account_session, region=region)
        delete_ssm_parameter('/org/member/SecLog_guardduty-group-subscription-filter-name', account_session, region=region)

    print("")
    print(f"####### AWS Landing Zone deletion script finished. Executed in {time.time() - start_time} seconds")
    print("#######")
    print("")

################################################################################
# FUNCTIONS
################################################################################

def usage():
    """
    This function prints the script usage
    """
    print('Usage:')
    print('')
    print('python EC-Delete-LandingZone.py -a <account profile> [-s <seclog profile>] [-v]')
    print('')
    print('   Provide ')
    print('   -a --account         : The AWS profile of the linked account to be switched')
    print('   -s --seclog          : The AWS profile of the source SECLOG account')
    print('   -v --verbose         : Debug mode - optional')

def exit_handler(signum, frame):
    print("Exiting...")
    sys.exit(1)

def get_account_id(session):
    """
    This function gets te id of the account defined in the profile
        :param force: flag to force the retrieval of the account ID 
        :return: a string with the account id 
    """

    try:
        sts = session.client('sts')
        response = sts.get_caller_identity()
        return response['Account']
    except ClientError as error:
        if error.response['Error']['Code'] == 'AccessDenied':
            print(f"Access denied getting account id [{Status.FAIL.value}]")
            print("Exiting...") 
            sys.exit(1)
        else:
            raise error

def is_seclog(session):
    """
    Function that checks if the account is a seclog account
        :return: true or false
    """
    client = session.client('ssm')
    seclog_account_id = get_account_id(session)
    response = client.get_parameter(Name='/org/member/SecLogMasterAccountId')
    if not 'Value' not in response or seclog_account_id != response['Parameter']['Value']:
        return False
    return True

def deactivate_guardduty(sseclog_id, session):
    guardduty = session.client('guardduty')
    
    detector_response = guardduty.list_detectors()
    for detector in detector_response['DetectorIds']:
        try:
            response = guardduty.disassociate_from_master_account(
                DetectorId=detector
            )
            response = guardduty.delete_invitations(AccountIds=[
                sseclog_id,
            ])
            print(f"Disassociate GuardDuty from source SECLOG account [{Status.OK.value}]")
            return
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
    print(f"Disassociate GuardDuty from source SECLOG account [{Status.NO_ACTION.value}]")

def deactivate_securityhub(sseclog_id,session):
    securityhub = session.client('securityhub')

    try:
        response = securityhub.disassociate_from_master_account()
        response = securityhub.delete_invitations(AccountIds=[
            sseclog_id,
        ])
        print(f"Disassociate SecurityHub from source SECLOG account [{Status.OK.value}]")
    except botocore.exceptions.ClientError as error:
        if error.response['Error']['Code'] == 'BadRequestException':
            if 'is not associated' in error.response['Error']['Message'] or 'no such resource found' in error.response['Error']['Message']:
                print(f"Disassociate SecurityHub from source SECLOG account [{Status.NO_ACTION.value}]")
            else:
                print(f"Disassociate SecurityHub from source SECLOG account [{Status.FAIL.value}]")
                print(error.response['Error']['Message'])
                print("Exiting...")
                sys.exit(1)
        else:
            print(f"Disassociate SecurityHub from source SECLOG account, error: error.response['Error']['Message'] [{Status.FAIL.value}]")
            print("Exiting...")
            sys.exit(1)

def deactivate_config(account_id,sseclog_id,account_session,sseclog_session):
    
    global regions
    print("Disassociate AWSConfig from source SECLOG account ", end="")
    with Spinner():
        try:
            for region in regions:
                try:
                    configservice = account_session.client('config', region_name=region)
                    configservice.delete_aggregation_authorization(
                        AuthorizedAccountId=sseclog_id,
                        AuthorizedAwsRegion='eu-west-1'
                    )
                except ClientError as error:
                    if  error.response['Error']['Code'] != 'AccessDeniedException':
                        raise error
                    else:
                        print(f"{error}{region}")
            

            client = sseclog_session.client('config')

            response = client.describe_configuration_aggregators(
                ConfigurationAggregatorNames=[
                    'SecLogAggregator',
                ]
            )
        
            for aggregationSources in response['ConfigurationAggregators'][0]['AccountAggregationSources']:
                accountsIds = aggregationSources['AccountIds']
            
                if account_id in aggregationSources['AccountIds']:
                    accountsIds.remove(account_id)
            if len(accountsIds) > 0:
                client.put_configuration_aggregator(
                    ConfigurationAggregatorName='SecLogAggregator',
                    AccountAggregationSources=[
                        {
                        'AccountIds': accountsIds,
                            'AllAwsRegions': True
                        },
                    ]
                )
            else: 
                 client.delete_configuration_aggregator(
                    ConfigurationAggregatorName='SecLogAggregator',
                   
                )

            print(f"\033[2K\033[1GDisassociate AWSConfig from source SECLOG account [{Status.OK.value}]")

        except botocore.exceptions.ClientError as error:
                if error.response['Error']['Code'] == 'BadRequestException':
                    if 'is not associated' in error.response['Error']['Message']:
                        print(f"\033[2K\033[1GDisassociate AWSConfig from source SECLOG account [{Status.NO_ACTION.value}]")
                    else:
                        print(f"\033[2K\033[1GDisassociate AWSConfig from source SECLOG account. Error: {error} [{Status.FAIL.value}]")
                        print(error.response['Error']['Message'])
                        print("Exiting...")
                        sys.exit(1)
                else:
                    print(f"\033[2K\033[1GDisassociate AWSConfig from source SECLOG account. Error: {error} [{Status.FAIL.value}]")
                    print(error.response['Error']['Message'])
                    print("Exiting...")
                    sys.exit(1)

def remove_stacks_from_stackset(stackset,account_id, session):
    
    global regions

    print(f"Remove stacks from StackSet {stackset} in progress ", end="")

    cfn = session.client('cloudformation')
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

def delete_stack(stack,session):
    """
    Function that updates a stack defined in the parameters
        :stack:         The stack name
        :session:       session of the account to be processed
        :return:        True or False
    """
    client = session.client('cloudformation')
    
    print(f"Delete {stack} stack ", end="")

    try:
        describe = client.describe_stacks(StackName=stack)
        
        if describe['Stacks'][0]['StackStatus'] not in ('CREATE_COMPLETE', 'UPDATE_COMPLETE', 'ROLLBACK_COMPLETE','UPDATE_ROLLBACK_COMPLETE'):
            print(f"Cannot delete stack {stack}. Current status is : {describe['Stacks'][0]['StackStatus']} [{Status.FAIL.value}]")
            print("Exiting...")
            sys.exit(1)

        client.update_termination_protection(EnableTerminationProtection=False, StackName=stack)

    except ClientError as err:
        if err.response['Error']['Code'] == 'AmazonCloudFormationException':
            print(f"\033[2K\033[1GDelete stack {stack} [{Status.NO_ACTION.value}]")
            return
        elif err.response['Error']['Code'] == 'ValidationError':
            print(f"\033[2K\033[1GDelete stack {stack} [{Status.NO_ACTION.value}]")
            return
        else:
            print(f"\033[2K\033[1GDelete stack {stack} failed. Reason : {err.response['Error']['Message']} [{Status.FAIL.value}]")
            print("Exiting...")
            sys.exit(1)

    print("in progress ", end="")
    
    with Spinner():
        try:
            
            client.delete_stack(StackName=stack)
            updated=False
            while updated == False: 
                try:
                    time.sleep(1)
                    response = client.describe_stacks(StackName=stack)
                    if 'FAILED' in response['Stacks'][0]['StackStatus'] or 'ROLLBACK' in response['Stacks'][0]['StackStatus'] :
                        print(f"\033[2K\033[1GDelete stack  {stack} failed. Reason {response['Stacks'][0]['StackStatusReason']} [{Status.FAIL.value}]")
                        print("Exiting...")
                        sys.exit(1)
                except ClientError as err:
                    if err.response['Error']['Code'] == 'ThrottlingException':
                        continue
                    else:
                        raise err

        except ClientError as err:
            if err.response['Error']['Code'] == 'ValidationError':
                print(f"\033[2K\033[1GDelete stack {stack} [{Status.OK.value}]")
            else:
                print(f"\033[2K\033[1GDelete stack  {stack} failed. Reason : {err.response['Error']['Message']} [{Status.FAIL.value}]")

def delete_ssm_parameter(parameter, session, region=None):
    """
    Function used to update an SSM parameter if the value is different
        :paremter:      parameter name
        :session:       session of the account to be processed
        :region:        region of command execution
    """

    client = session.client('ssm')

    exists = True
    if region:
        print(f"Delete SSM parameter {parameter} [{region}] ", end="")
    else:
        print(f"Delete SSM parameter {parameter} ", end="")

    try:
        response = client.get_parameter(Name=parameter)
    except Exception as err:
        exists=False
    
    try:
        if exists and 'Value' in response['Parameter']:
            response = client.delete_parameter(Name=parameter)
            print(f"[{Status.OK.value}]")
        else:
            print(f"[{Status.NO_ACTION.value}]")
    except Exception as err:
        print(f"failed. Reason {err.response['Error']['Message']} [{Status.FAIL.value}]")
        print("Exiting...")
        sys.exit(1)



################################################################################
# CLASSES
################################################################################

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


signal.signal(signal.SIGINT, exit_handler)

if __name__ == "__main__":
    main(sys.argv[1:])

