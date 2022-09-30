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
all_regions = ["ap-northeast-1","ap-northeast-2","ap-northeast-3","ap-south-1","ap-southeast-1","ap-southeast-2","ca-central-1","eu-central-1","eu-north-1","eu-west-1","eu-west-2","eu-west-3","sa-east-1","us-east-1","us-east-2","us-west-1","us-west-2"]

def exit_handler(signum, frame):
    print("Exiting...")
    sys.exit(1)


signal.signal(signal.SIGINT, exit_handler)

def main(argv):
    
    verbosity = logging.ERROR
    start_time = time.time()
  
    sseclog_profile = None
    sseclog_id = None

    tseclog_profile = None
    tseclog_id = None
    tseclog_SecLog_sns_arn = None
    tseclog_KMSCloudtrailKey_arn = None
    tseclog_SecLogOU = None

    account_profile = None
    account_id = None
    account_email = None
    stored_SecLog_sns_arn = None
    stored_KMSCloudtrailKey_arn = None
    stored_SecLogOU = None

    organisation_profile = None
    organisation_id = None
    

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

    # linked account
    
    print(f"Account to be moved : {account_profile}")
    account_session=boto3.Session(profile_name=account_profile, region_name ='eu-west-1')
    
    account_id = get_account_id(account_session)

    print(f"Account ID : {account_id}")
    
    # get stored seclog_id from ssm parameter
    ssm = account_session.client('ssm')
    try:
        response = ssm.get_parameter(Name='/org/member/SecLogMasterAccountId')
        stored_sseclog_id = response['Parameter']['Value']
    except ClientError as err:
        print(f"LZ not configured on this account. [{Status.FAIL.value}]")
        print("Exiting...")
        sys.exit(1)

    try:
        response = ssm.get_parameter(Name='/org/member/SecLog_sns_arn')
        stored_SecLog_sns_arn = response['Parameter']['Value']
    except ClientError as err:
        print(f"SecLog_sns_arn not configured on this account. [{Status.FAIL.value}]")
        print("Exiting...")
        sys.exit(1)

    try:
        response = ssm.get_parameter(Name='/org/member/KMSCloudtrailKey_arn')
        stored_KMSCloudtrailKey_arn = response['Parameter']['Value']
    except ClientError as err:
        print(f"KMSCloudtrailKey_arn not configured on this account. [{Status.FAIL.value}]")
        print("Exiting...")
        sys.exit(1)

    try:
        response = ssm.get_parameter(Name='/org/member/SecLogOU')
        stored_SecLogOU = response['Parameter']['Value']
    except ClientError as err:
        print(f"SecLogOU not configured on this account. [{Status.FAIL.value}]")
        print("Exiting...")
        sys.exit(1)

    print(f"Linked account identified. [{Status.OK.value}]")
    print("")

    # organisation account

    print(f"Organisation account : {organisation_profile}")
    
    org_session=boto3.Session(profile_name=organisation_profile, region_name ='eu-west-1')

    organisation_id = get_account_id(org_session)
    organizations = org_session.client('organizations')
    response = organizations.describe_account(AccountId=account_id)
    account_email = response['Account']['Email']

    print(f"Account ID : {organisation_id}")
    print(f"Organisation account identified. [{Status.OK.value}]")
    print("")

    # original seclog account
    print(f"Original SECLOG account : {sseclog_profile}")
   
    sseclog_session=boto3.Session(profile_name=sseclog_profile, region_name ='eu-west-1')

    sseclog_id = get_account_id(sseclog_session)
    print(f"Account ID : {sseclog_id}")
    if (is_seclog(sseclog_session) == False):
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
    
    tseclog_session=boto3.Session(profile_name=tseclog_profile, region_name ='eu-west-1')

    tseclog_id = get_account_id(tseclog_session)
    print(f"Account ID : {tseclog_id}")
    if (is_seclog(tseclog_session) == False):
        print(f"Not a SECLOG account. [{Status.FAIL.value}]")
        print("Exiting...")
        sys.exit(1)
    else:
        print(f"Target SECLOG account identified. [{Status.OK.value}]")
        
        ssm = tseclog_session.client('ssm')
        try:
            response = ssm.get_parameter(Name='/org/member/SecLog_sns_arn')
            tseclog_SecLog_sns_arn = response['Parameter']['Value']
        except ClientError as err:
            print(f"SecLog_sns_arn not configured on this account. [{Status.FAIL.value}]")
            print("Exiting...")
            sys.exit(1)

        try:
            response = ssm.get_parameter(Name='/org/member/KMSCloudtrailKey_arn')
            tseclog_KMSCloudtrailKey_arn = response['Parameter']['Value']
        except ClientError as err:
            print(f"KMSCloudtrailKey_arn not configured on this account. [{Status.FAIL.value}]")
            print("Exiting...")
            sys.exit(1)

        try:
            response = ssm.get_parameter(Name='/org/member/SecLogOU')
            tseclog_SecLogOU = response['Parameter']['Value']
        except ClientError as err:
            print(f"SecLogOU not configured on this account. [{Status.FAIL.value}]")
            print("Exiting...")
            sys.exit(1)

            
    print("")

    input(f"####### All seems in good shape. Press any key to continue (Ctrl+C to cancel)")

    print("")

    # Cleaning up linked account
    print("#######")
    print(f"####### Migrating linked account {account_profile} from SECLOG {sseclog_profile} to SECLOG {tseclog_profile}")
    print("#######")
    print("")

    # deactivate guardduty from source SECLOG
    #deactivate_guardduty(sseclog_id,account_session)

    # deactivate securityhub from source SECLOG
    #deactivate_securityhub(sseclog_id,account_session)

    # deactivate config from source SECLOG
    #deactivate_config(account_id,sseclog_id,account_session,sseclog_session)
    
    # Update SSM parameter
   
    ssm = account_session.client('ssm')
    if stored_sseclog_id == tseclog_id:
        print(f"Update SecLogMasterAccountId SSM parameter [{Status.NO_ACTION.value}]")
    else:
        try:
            ssm.put_parameter(
                Name='/org/member/SecLogMasterAccountId',
                Value=tseclog_id,
                Type='String',
                Overwrite=True)
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
            ssm.put_parameter(
                Name='/org/member/SecLog_sns_arn',
                Value=tseclog_SecLog_sns_arn,
                Type='String',
                Overwrite=True)
            print(f"Update SecLog_sns_arn SSM parameter [{Status.OK.value}]")
        except botocore.exceptions.ClientError as error:
            print(f"Update SecLog_sns_arn SSM parameter [{Status.FAIL.value}]")
            print(error.response['Error']['Message'])
            print("Exiting...")
            sys.exit(1)

    if stored_KMSCloudtrailKey_arn == tseclog_KMSCloudtrailKey_arn:
        print(f"Update KMSCloudtrailKey_arn SSM parameter [{Status.NO_ACTION.value}]")
    else:
        try:
            ssm.put_parameter(
                Name='/org/member/KMSCloudtrailKey_arn',
                Value=tseclog_KMSCloudtrailKey_arn,
                Type='String',
                Overwrite=True)
            print(f"Update KMSCloudtrailKey_arn SSM parameter [{Status.OK.value}]")
        except botocore.exceptions.ClientError as error:
            print(f"Update KMSCloudtrailKey_arn SSM parameter [{Status.FAIL.value}]")
            print(error.response['Error']['Message'])
            print("Exiting...")
            sys.exit(1)
    
    if stored_SecLogOU == tseclog_SecLogOU:
        print(f"Update SecLogOU SSM parameter [{Status.NO_ACTION.value}]")
    else:
        try:
            ssm.put_parameter(
                Name='/org/member/SecLogOU',
                Value=tseclog_SecLogOU,
                Type='String',
                Overwrite=True)
            print(f"Update SecLogOU SSM parameter [{Status.OK.value}]")
        except botocore.exceptions.ClientError as error:
            print(f"Update SecLogOU SSM parameter [{Status.FAIL.value}]")
            print(error.response['Error']['Message'])
            print("Exiting...")
            sys.exit(1)



    # Delete instances from original seclog account
   
    #remove_stacks_from_stackset('SECLZ-Enable-Config-SecurityHub-Globally', account_id,sseclog_session)
    #remove_stacks_from_stackset('SECLZ-Enable-Guardduty-Globally', account_id,sseclog_session)

    # Re-apply CFN
  
    #update_stack('SECLZ-StackSetExecutionRole',account_session)
    #update_stack('SECLZ-Guardduty-detector',account_session)
    ##update_stack('SECLZ-Notifications-Cloudtrail',account_session) ##new parameter values not being used 
    #update_stack('SECLZ-config-cloudtrail-SNS',account_session)
    #update_stack('SECLZ-local-SNS-topic',account_session)

       # Re-apply CFN
   
    # Re-apply Stackset from Target SECLOG
    #add_stacks_from_stackset('SECLZ-Enable-Config-SecurityHub-Globally', account_id,tseclog_session)
    #add_stacks_from_stackset('SECLZ-Enable-Guardduty-Globally', account_id,tseclog_session)
    
    # associate config with target SECLOG
    activate_config(account_id,account_session,tseclog_id,tseclog_session)
    # associate guardduty with target SECLOG
    #activate_guardduty(account_id, account_email,account_session,tseclog_id,tseclog_session)
    # associate securityhub with target SECLOG
    #activate_securityhub(account_id, account_email,account_session,tseclog_id,tseclog_session)
    
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

def add_stacks_from_stackset(stackset,account_id,session):
    
    global regions

    print(f"Add stacks from StackSet {stackset} in progress ", end="")

    cfn = session.client('cloudformation')
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



def update_stack(stack,session):
    """
    Function that updates a stack defined in the parameters
        :stack:         The stack name
        :template_data: dict holding CFT details
        :params:        parameters to be passed to the stack
        :return:        True or False
    """
    client = session.client('cloudformation')
    
    capabilities = []
    tags = []
    parameters = []
    template_body = None
    
    print(f"Update {stack} stack ", end="")

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
        print(f"\033[2K\033[1GUpdate Stack {stack} failed. Reason : {err.response['Error']['Message']} [{Status.FAIL.value}]")
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
                        print(f"\033[2K\033[1GUpdate stack {stack} [{Status.OK.value}]")
                        updated=True
                        break
                    elif 'FAILED' in response['Stacks'][0]['StackStatus'] or 'ROLLBACK' in response['Stacks'][0]['StackStatus'] :
                        print(f"\033[2K\033[1GUpdate stack  {stack} failed. Reason {response['Stacks'][0]['StackStatusReason']} [{Status.FAIL.value}]")
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
                print(f"\033[2K\033[1GUpdate stack {stack} [{Status.NO_ACTION.value}]")
            else:
                print(f"\033[2K\033[1GUpdate stack  {stack} failed. Reason : {err.response['Error']['Message']} [{Status.FAIL.value}]")


def deactivate_config(account_id,sseclog_id,account_session,sseclog_session):
    
    global all_regions
    print("Disassociate AWSConfig from source SECLOG account ", end="")
    with Spinner():
        try:
            for region in all_regions:
                try:
                    configservice = account_session.client('config', region_name=region)
                    configservice.delete_aggregation_authorization(
                        AuthorizedAccountId=sseclog_id,
                        AuthorizedAwsRegion='eu-west-1'
                    )
                except ClientError as error:
                    if  error.response['Error']['Code'] != 'AccessDeniedException':
                        raise error
                    

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

            client.put_configuration_aggregator(
                ConfigurationAggregatorName='SecLogAggregator',
                AccountAggregationSources=[
                    {
                    'AccountIds': accountsIds,
                        'AllAwsRegions': True
                    },
            ]
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


def activate_config(account_id,account_session,tseclog_id,tseclog_session):
    
    global all_regions
    
    print("Asassociate AWSConfig from source SECLOG account ", end="")
    with Spinner():
        try:

       
            client = tseclog_session.client('config')

            response = client.describe_configuration_aggregators(
                ConfigurationAggregatorNames=[
                    'SecLogAggregator',
                ]
            )
        
            for aggregationSources in response['ConfigurationAggregators'][0]['AccountAggregationSources']:
                accountsIds = aggregationSources['AccountIds']
            
                if account_id not in aggregationSources['AccountIds']:
                    accountsIds.append(account_id)

            client.put_configuration_aggregator(
                ConfigurationAggregatorName='SecLogAggregator',
                AccountAggregationSources=[
                    {
                    'AccountIds': accountsIds,
                        'AllAwsRegions': True
                    },
            ]
            )

        
            client = account_session.client('config')

            response = client.describe_pending_aggregation_requests()
            
            for pendingAggregationRequests in response['PendingAggregationRequests']:
                print(pendingAggregationRequests)
                if tseclog_id in pendingAggregationRequests['RequesterAccountId']:
                    for region in all_regions:
                        client = account_session.client('config', region_name=region)
                        client.put_aggregation_authorization(
                            AuthorizedAccountId=tseclog_id,
                            AuthorizedAwsRegion='eu-west-1'
                        )


            print(f"\033[2K\033[1GAsassociate AWSConfig linked account to target SECLOG account [{Status.OK.value}]")
        except botocore.exceptions.ClientError as error:
                if error.response['Error']['Code'] == 'BadRequestException':
                    if 'is not associated' in error.response['Error']['Message']:
                        print(f"\033[2K\033[1GAssociate AWSConfig linked account to target SECLOG account [{Status.NO_ACTION.value}]")
                    else:
                        print(f"\033[2K\033[1GAssociate AWSConfig linked account to target SECLOG account [{Status.FAIL.value}]")
                        print(error.response['Error']['Message'])
                        print("Exiting...")
                        sys.exit(1)
                else:
                    print(f"\033[2K\033[1GAsssociate AWSConfig linked account to target SECLOG account [{Status.FAIL.value}]")
                    print(error.response['Error']['Message'])
                    print("Exiting...")
                    sys.exit(1)



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
    
def activate_guardduty(account_id, account_email,account_session,tseclog_id,tseclog_session):


    guardduty = tseclog_session.client('guardduty')
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
            print(f"Issue invitation for GuardDuty from target SECLOG account [{Status.OK.value}]")
        except botocore.exceptions.ClientError as error:
            if error.response['Error']['Code'] == 'BadRequestException':
                if 'is not associated' in error.response['Error']['Message']:
                    print(f"Issue invitation for GuardDuty from target SECLOG account [{Status.NO_ACTION.value}]")
                else:
                    print(f"Issue invitation for GuardDuty from target SECLOG account [{Status.FAIL.value}]")
                    print(error.response['Error']['Message'])
                    print("Exiting...")
                    sys.exit(1)
            else:
                print(f"Issue invitation for GuardDuty from target SECLOG account [{Status.FAIL.value}]")
                print(error.response['Error']['Message'])
                print("Exiting...")
                sys.exit(1)

    # accept invitation
 

    guardduty = account_session.client('guardduty')
    detector_response = guardduty.list_detectors()
    for detector in detector_response['DetectorIds']:
        try:
            response = guardduty.list_invitations()
            response = guardduty.accept_invitation(
                DetectorId=detector,
                MasterId=tseclog_id,
                InvitationId=response['Invitations'][0]['InvitationId']
            )
            
            print(f"Aassociate GuardDuty from linked account to target SECLOG  account [{Status.OK.value}]")
        except botocore.exceptions.ClientError as error:
            if error.response['Error']['Code'] == 'BadRequestException':
                if 'is not associated' in error.response['Error']['Message']:
                    print(f"Aassociate GuardDuty from linked account to target SECLOG account [{Status.NO_ACTION.value}]")
                else:
                    print(f"Aassociate GuardDuty from linked account to target SECLOG account [{Status.FAIL.value}]")
                    print(error.response['Error']['Message'])
                    print("Exiting...")
                    sys.exit(1)
            else:
                print(f"Aassociate GuardDuty from linked account to target SECLOG account [{Status.FAIL.value}]")
                print(error.response['Error']['Message'])
                print("Exiting...")
                sys.exit(1)

   

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
            if 'is not associated' in error.response['Error']['Message']:
                print(f"Disassociate SecurityHub from source SECLOG account [{Status.NO_ACTION.value}]")
            else:
                print(f"Disassociate SecurityHub from source SECLOG account [{Status.FAIL.value}]")
                print(error.response['Error']['Message'])
                print("Exiting...")
                sys.exit(1)
        else:
            print(f"Disassociate SecurityHub from source SECLOG account [{Status.FAIL.value}]")
            print(error.response['Error']['Message'])
            print("Exiting...")
            sys.exit(1)

def activate_securityhub(account_id, account_email,account_session,tseclog_id,tseclog_session):

    securityhub = tseclog_session.client('securityhub')
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
        print(f"Issue invitation for SecurityHub from target SECLOG account: [{Status.OK.value}]")
    except botocore.exceptions.ClientError as error:
        if error.response['Error']['Code'] == 'BadRequestException':
            if 'is not associated' in error.response['Error']['Message']:
                print(f"Issue invitation for SecurityHub from target SECLOG account [{Status.NO_ACTION.value}]")
            else:
                print(f"Issue invitation for SecurityHub from target SECLOG account [{Status.FAIL.value}]")
                print(error.response['Error']['Message'])
                print("Exiting...")
                sys.exit(1)
        else:
            print(f"Issue invitation for SecurityHub from target SECLOG account [{Status.FAIL.value}]")
            print(error.response['Error']['Message'])
            print("Exiting...")
            sys.exit(1)
   
    # accept invitation
   
    securityhub = account_session.client('securityhub')
    try:
        response = securityhub.list_invitations()
        response = securityhub.accept_invitation(
            MasterId=tseclog_id,
            InvitationId=response['Invitations'][0]['InvitationId']
        )
        
        print(f"Aassociate SecurityHub linked account to SECLOG account [{Status.OK.value}]")
    except botocore.exceptions.ClientError as error:
        if error.response['Error']['Code'] == 'BadRequestException':
            if 'is not associated' in error.response['Error']['Message']:
                print(f"Aassociate SecurityHub from linked account to target SECLOG account [{Status.NO_ACTION.value}]")
            else:
                print(f"Aassociate SecurityHub from linked account to target SECLOG account [{Status.FAIL.value}]")
                print(error.response['Error']['Message'])
                print("Exiting...")
                sys.exit(1)
        else:
            print(f"Aassociate SecurityHub from linked account to target SECLOG account [{Status.FAIL.value}]")
            print(error.response['Error']['Message'])
            print("Exiting...")
            sys.exit(1)


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


