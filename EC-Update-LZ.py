#!/usr/bin/python

import sys, getopt
import subprocess, pkg_resources
import os
import logging
import time
import boto3
import json

from enum import Enum
from colorama import Fore, Back, Style
from botocore.exceptions import BotoCoreError, ClientError, ProfileNotFound



account_id = ''

stacks = { 'SECLZ-Cloudtrail-KMS' : { 'Template' : 'CFN/EC-lz-Cloudtrail-kms-key.yml' } ,
     'SECLZ-LogShipper-Lambdas-Bucket' : { 'Template' : 'CFN/EC-lz-s3-bucket-lambda-code.yml' } ,
     'SECLZ-LogShipper-Lambdas' : { 'Template' : 'CFN/EC-lz-logshipper-lambdas.yml' } ,
     'SECLZ-Central-Buckets' : { 'Template' : 'CFN/EC-lz-s3-buckets.yml' , "Params" : 'CFN/EC-lz-TAGS-params.json'} ,
     'SECLZ-Iam-Password-Policy' : { 'Template' : 'CFN/EC-lz-iam-setting_password_policy.yml', 'Linked':True } ,
     'SECLZ-config-cloudtrail-SNS' : { 'Template' : 'CFN/EC-lz-config-cloudtrail-logging.yml', 'Linked':True } ,
     'SECLZ-Guardduty-detector' : { 'Template' : 'CFN/EC-lz-guardDuty-detector.yml', 'Linked':True } ,
     'SECLZ-SecurityHub' : { 'Template' : 'CFN/EC-lz-securityHub.yml', "Params" : 'CFN/EC-lz-TAGS-params.json', 'Linked':True } ,
     'SECLZ-Notifications-Cloudtrail' : { 'Template' : 'CFN/EC-lz-notifications.yml', 'Linked':True } ,
     'SECLZ-CloudwatchLogs-SecurityHub' : { 'Template' : 'CFN/EC-lz-config-securityhub-logging.yml' } ,
     'SECLZ-local-SNS-topic' : { 'Template' : 'CFN/EC-lz-local-config-SNS.yml', 'Linked':True} }


stacksets = { 'SECLZ-Enable-Config-SecurityHub-Globally' :  { 'Template' : 'CFN/EC-lz-Config-SecurityHub-all-regions.yml' } ,
     'SECLZ-Enable-Guardduty-Globally' :  { 'Template' : 'CFN/EC-lz-Config-Guardduty-all-regions.yml' } }


def main(argv):
    
    start_time = time.time()
    manifest = ''
    profile = ''
    org_account='246933597933'
    has_profile = False
    verbosity = logging.ERROR
    linked_accounts_doctored = []

    try:
        opts, args = getopt.getopt(argv,"hvm:s:o:",["manifest", "seclog", "org", "verbose"])
    except getopt.GetoptError:
        usage()
        sys.exit(2)
    
    print("#######")
    print("####### AWS Landing Zone update script")
    print("")


    # Parsing script parameters
    for opt, arg in opts:
        if opt == '-h':
            usage()
            sys.exit()
        elif opt in ("-m", "--manifest"):
            if (arg == ''):
                print("Manifest has not been provided. [{}]".format(Status.FAIL.value))
                print("Exiting...")
                sys.exit(1)
            else:
                try:
                    with open(arg) as f:
                        manifest = json.load(f)
                except FileNotFoundError as err:
                    print("Manifest file not found : {} [{}]".format(err.strerror,Status.FAIL.value))
                    print("Exiting...")
                    sys.exit(1)
                except AttributeError:
                    print("Manifest file {} is not a valid json [{}]".format(arg,Status.FAIL.value))
                    print("Exiting...")
                    sys.exit(1)
        elif opt in ("-o", "--org"):
            print("Using Organization account : {}".format(arg))
            org_account = arg
        elif opt in ("-s", "--seclog"):
            profiles = arg.split(',')
            has_profile = True
            if len(profiles) > 1:
                print("Multiple AWS profiles delected  : {}".format(profiles))
        elif opt in ("-v", "--verbose"):
            verbosity = logging.DEBUG
    
    logging.basicConfig(level=verbosity)
    p = 0
    loop = True
    while loop:
        if has_profile:
            if p  < len(profiles):
                profile = profiles[p]
                p=p+1
                try:
                    print("Using AWS profile : {}".format(profile))
                    boto3.setup_default_session(profile_name=profile)
                    get_account_id(True)
                except ProfileNotFound as err:
                    print("{} [{}]".format(err,Status.FAIL.value))
                    print("Exiting...")
                    sys.exit(1)
            else:
                break
        else:
            loop = False 

        if (is_seclog() == False):
            print("Not a SECLOG account. [{}]".format(Status.FAIL.value))
            print("Exiting...")
            sys.exit(1)
        
        print("SECLOG account identified. [{}]".format(Status.OK.value))
        print("")

        linked_accounts = get_linked_accounts()
        
        #update seclog stacks
        
        print("Updating SECLOG account {}".format(account_id))
        print("")
        stack_actions = manifest['stacks']
        cfn = boto3.client('cloudformation')
        seclog_status = Execution.NO_ACTION
        if 'SECLZ-Cloudtrail-KMS' in stack_actions and stack_actions['SECLZ-Cloudtrail-KMS']['update'] == True:            
            result = update_stack(cfn, 'SECLZ-Cloudtrail-KMS', stacks)
            if result != Execution.NO_ACTION:
                seclog_status = result
            elif result == Execution.OK :
                print("SSM parameter /org/member/KMSCloudtrailKey_arn update in progress...", end="")
                client = boto3.client('ssm')
                response = client.get_parameter(Name='/org/member/KMSCloudtrailKey_arn')
                response = client.put_parameter(Name='/org/member/KMSCloudtrailKey_arn', Value=response['Parameter']['Value'], Type=response['Parameter']['Type'], Overwrite=True)
                print("\rSSM parameter /org/member/KMSCloudtrailKey_arn updated with version [{Status.OK}]".format(response['Version']))

        if seclog_status != Execution.FAIL and 'SECLZ-LogShipper-Lambdas-Bucket' in stack_actions and stack_actions['SECLZ-LogShipper-Lambdas-Bucket']['update'] == True:
            result = update_stack(cfn, 'SECLZ-LogShipper-Lambdas-Bucket', stacks)
            if result != Execution.NO_ACTION:
                seclog_status = result

        if seclog_status != Execution.FAIL and 'SECLZ-LogShipper-Lambdas' in stack_actions and stack_actions['SECLZ-LogShipper-Lambdas']['update'] == True:
            #TODO
            print("")
        
        if seclog_status != Execution.FAIL and 'SECLZ-Central-Buckets' in stack_actions and stack_actions['SECLZ-Central-Buckets']['update'] == True:
            result = update_stack(cfn, 'SECLZ-Central-Buckets', stacks)
            if result != Execution.NO_ACTION:
                seclog_status = result
        
        if seclog_status != Execution.FAIL and 'SECLZ-Iam-Password-Policy' in stack_actions and stack_actions['SECLZ-Iam-Password-Policy']['update'] == True:
            result = update_stack(cfn, 'SECLZ-Iam-Password-Policy', stacks)
            if result != Execution.NO_ACTION:
                seclog_status = result

        if seclog_status != Execution.FAIL and 'SECLZ-config-cloudtrail-SNS' in stack_actions and stack_actions['SECLZ-config-cloudtrail-SNS']['update'] == True:
            result = update_stack(cfn, 'SECLZ-config-cloudtrail-SNS', stacks)
            if result != Execution.NO_ACTION:
                seclog_status = result
        
        if seclog_status != Execution.FAIL and 'SECLZ-Guardduty-detector' in stack_actions and stack_actions['SECLZ-Guardduty-detector']['update'] == True:
            result = update_stack(cfn, 'SECLZ-Guardduty-detector', stacks)
            if result != Execution.NO_ACTION:
                seclog_status = result
        
        if seclog_status != Execution.FAIL and 'SECLZ-SecurityHub' in stack_actions and stack_actions['SECLZ-SecurityHub']['update'] == True:
            result = update_stack(cfn, 'SECLZ-SecurityHub', stacks)
            if result != Execution.NO_ACTION:
                seclog_status = result
        
        if seclog_status != Execution.FAIL and 'SECLZ-Notifications-Cloudtrail' in stack_actions and stack_actions['SECLZ-Notifications-Cloudtrail']['update'] == True:
            result = update_stack(cfn, 'SECLZ-Notifications-Cloudtrail', stacks)
            if result != Execution.NO_ACTION:
                seclog_status = result
        
        if seclog_status != Execution.FAIL and 'SECLZ-CloudwatchLogs-SecurityHub' in stack_actions and stack_actions['SECLZ-CloudwatchLogs-SecurityHub']['update'] == True:
            result = update_stack(cfn, 'SECLZ-CloudwatchLogs-SecurityHub', stacks)
            if result != Execution.NO_ACTION:
                seclog_status = result
        
        print("")
        print("SECLOG account {} update ".format(account_id), end="")
        if seclog_status == Execution.FAIL:
            print("[{}]".format(Status.FAIL.value))
            print("Exiting...")
            sys.exit(1)
        elif seclog_status == Execution.OK:
            print("[{}]".format(Status.OK.value))
        else:
            print("[{}]".format(Status.NO_ACTION.value))

        #update linked account stacks

        for linked in linked_accounts:
            credentials = ''
            accessKey = ''
            secretAccessKey = ''
            sessionToken = ''

            
            sts = boto3.client('sts')
            assumedRole = sts.assume_role(
                RoleArn="arn:aws:iam::{}:role/AWSCloudFormationStackSetExecutionRole".format(linked),
                RoleSessionName='CloudFormationSession'
            )
            credentials = assumedRole['Credentials']
            accessKey = credentials['AccessKeyId']
            secretAccessKey = credentials['SecretAccessKey']
            sessionToken = credentials['SessionToken']

            cfn = boto3.client('cloudformation',  
                aws_access_key_id=accessKey,
                aws_secret_access_key=secretAccessKey, 
                aws_session_token=sessionToken)
            
            print("")
            print("Updating linked account {}".format(linked))
            print("")
            linked_status = Execution.NO_ACTION
            if 'SECLZ-Iam-Password-Policy' in stack_actions and stack_actions['SECLZ-Iam-Password-Policy']['update'] == True:
                result = update_stack(cfn, 'SECLZ-Iam-Password-Policy', stacks)
                if result != Execution.NO_ACTION:
                    linked_status = result
                    

            if linked_status != Execution.FAIL and 'SECLZ-config-cloudtrail-SNS' in stack_actions and stack_actions['SECLZ-config-cloudtrail-SNS']['update'] == True:
                result = update_stack(cfn, 'SECLZ-config-cloudtrail-SNS', stacks)
                if result != Execution.NO_ACTION:
                    linked_status = result
                    
            
            if linked_status != Execution.FAIL and 'SECLZ-SecurityHub' in stack_actions and stack_actions['SECLZ-SecurityHub']['update'] == True:
                result = update_stack(cfn, 'SECLZ-SecurityHub', stacks)
                if result != Execution.NO_ACTION:
                    linked_status = result
                    
        
            if linked_status != Execution.FAIL and 'SECLZ-Notifications-Cloudtrail' in stack_actions and stack_actions['SECLZ-Notifications-Cloudtrail']['update'] == True:
                result = update_stack(cfn, 'SECLZ-Notifications-Cloudtrail', stacks)
                if result != Execution.NO_ACTION:
                    linked_status = result
                
            
            if linked_status != Execution.FAIL and 'SECLZ-local-SNS-topic' in stack_actions and stack_actions['SECLZ-local-SNS-topic']['update'] == True:
                result = update_stack(cfn, 'SECLZ-local-SNS-topic', stacks)
                if result != Execution.NO_ACTION:
                    linked_status = result
                

            print("")
            print("Linked account {} update ".format(linked), end="")
            if linked_status == Execution.FAIL:
                print("[{}]".format(Status.FAIL.value))
                print("Exiting...")
                sys.exit(1)
            elif linked_status == Execution.OK:
                print("[{}]".format(Status.OK.value))
            else:
                print("[{}]".format(Status.NO_ACTION.value))
            print("")
    
    print("")
    print("####### AWS Landing Zone update script finished. Executed in {} seconds".format(time.time() - start_time))
    print("#######")
    print("")

def usage():
    """
    This function prints the script usage
    """
    print('Usage:')
    print('')
    print('python EC-Update-LZ.py -m <manifest> [-s <seclogprofile>] [-o <orgprofile>] [-v]')
    print('')
    print('   Provide ')
    print('   -m --manifext         : The manifest for the LZ update')
    print('   -s --seclog           : The AWS profile of the SECLOG account - optional')
    print('   -o --org              : The AWS ID of the Organisation account - optional')
    print('   -v --verbose          : Debug mode - optional')

def get_account_id(Force = False):
    """
    This function gets te id of the account defined in the profile
        :param force: flag to force the retrieval of the account ID 
        :return: a string with the account id 
    """
    global account_id

    if account_id == '' or Force == True:
        sts = boto3.client('sts')
        try:
            response = sts.get_caller_identity()
            account_id = response['Account']
        except ClientError as error:
            if error.response['Error']['Code'] == 'AccessDenied':
                print("Access denied getting account id [{}]".format(Status.FAIL.value))
                print("Exiting...") 
                sys.exit(1)
            else:
                raise error
        
    return account_id

def get_linked_accounts():
    """
    Function to retrieve the Linked accounts from a SECLOG account
        :return: list with linked account details
    """
    linked_accounts = []
    accountId = get_account_id()
    client = boto3.client('guardduty')
    response = client.list_detectors()
    
    if response['DetectorIds'][0] != '':
        data = client.list_members(DetectorId=response['DetectorIds'][0])
        
        for member in data['Members']:
            if member['RelationshipStatus'] == 'Enabled':
                linked_accounts.append(member['AccountId'])
                
    return linked_accounts

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

def update_stack(client, stack, templates, params=[]):
    """
    Function that updates a stack defined in the parameters
        :stack:         The stack name
        :template_data: dict holding CFT details
        :params:        parameters to be passed to the stack
        :return:        True or False
    """
    template = templates[stack]['Template']
    capabilities=[]

    try:

        f=open(template, "r")
        template_body=f.read()
        print("Updating stack : {}. ".format(stack), end="")
        

        response = client.describe_stacks(StackName=stack)

        if not params: 
            if 'Params' in templates[stack]:
                with open(templates[stack]['Params']) as f:
                    params = json.load(f)
            else: 
                if 'Parameters' in response['Stacks'][0]:
                    params = response['Stacks'][0]['Parameters']
        
        
        if 'Capabilities' in response['Stacks'][0]:
            capabilities = response['Stacks'][0]['Capabilities']
        


        if response['Stacks'][0]['StackStatus'] not in ('CREATE_COMPLETE', 'UPDATE_COMPLETE'):
            print("Cannot update stack {}. Current status is : {} [{}]".format(stack,response['Stacks'][0]['StackStatus'],Status.FAIL.value ))
            return Execution.FAIL
        
        print("in progress ... ".format(stack), end="")
        client.update_stack(StackName=stack, TemplateBody=template_body, Parameters=params, Capabilities=capabilities)
        updated=False
        
        while updated == False:
            response = client.describe_stacks(StackName=stack)
            if 'COMPLETE' in response['Stacks'][0]['StackStatus'] :
                print("\033[2K\033[1GStack {} update [{}]".format(stack,Status.OK.value))
                updated=True
                break
            elif 'FAILED' in response['Stacks'][0]['StackStatus'] :
                print("\033[2K\033[1GStack {} update failed. Reason {} [{}]".format(stack, response['Stacks'][0]['StackStatusReason'],Status.FAIL.value))
                return Execution.FAIL
            time.sleep(1)

        
        return Execution.OK
        
    except FileNotFoundError as err:
        print("\033[2K\033[1GTemplate not found : {} [{}]".format(err.strerror,Status.FAIL.value))
    except ClientError as err:
        if err.response['Error']['Code'] == 'AmazonCloudFormationException':
            print("\033[2K\033[1GStack {} not found : {} [{}]".format(stack,err.response['Error']['Message'],Status.FAIL.value))
        elif err.response['Error']['Code'] == 'ValidationError' and err.response['Error']['Message'] == 'No updates are to be performed.':
            print("\033[2K\033[1GStack {} update [{}]".format(stack,Status.NO_ACTION.value))
            return Execution.NO_ACTION
        else:
            print("\033[2K\033[1GStack {} update failed. Reason : {} [{}]".format(stack,err.response['Error']['Message'],Status.FAIL.value))
    
    return Execution.FAIL
    

class Execution(Enum):
    FAIL = -1
    OK = 0
    NO_ACTION = 2

class Status(Enum):
    FAIL = Fore.RED + "FAIL" + Style.RESET_ALL
    OK = Fore.GREEN + "OK" + Style.RESET_ALL
    NO_ACTION = Fore.YELLOW + "NO ACTION" + Style.RESET_ALL

if __name__ == "__main__":
    main(sys.argv[1:])


