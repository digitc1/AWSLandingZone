#!/usr/bin/python

import sys, getopt
import subprocess, pkg_resources
import os
import logging
import time
import boto3
import json

from botocore.exceptions import BotoCoreError, ClientError


account_id = ''

stacks = [
    { 'SECLZ-Cloudtrail-KMS' : { 'Template' : 'CFN/EC-lz-Cloudtrail-kms-key.yml' } },
    { 'SECLZ-LogShipper-Lambdas-Bucket' : { 'Template' : 'CFN/EC-lz-s3-bucket-lambda-code.yml' } },
    { 'SECLZ-LogShipper-Lambdas' : { 'Template' : 'CFN/EC-lz-logshipper-lambdas.yml' } },
    { 'SECLZ-Central-Buckets' : { 'Template' : 'CFN/EC-lz-s3-buckets.yml' , "Params" : 'CFN/EC-lz-TAGS-params.json'} },
    { 'SECLZ-Iam-Password-Policy' : { 'Template' : 'CFN/EC-lz-iam-setting_password_policy.yml', 'Client':True } },
    { 'SECLZ-config-cloudtrail-SNS' : { 'Template' : 'CFN/EC-lz-config-cloudtrail-logging.yml', 'Client':True } },
    { 'SECLZ-Guardduty-detector' : { 'Template' : 'CFN/EC-lz-guardDuty-detector.yml', 'Client':True } },
    { 'SECLZ-SecurityHub' : { 'Template' : 'CFN/EC-lz-securityHub.yml', 'Client':True } },
    { 'SECLZ-Notifications-Cloudtrail' : { 'Template' : 'CFN/EC-lz-notifications.yml', 'Client':True } },
    { 'SECLZ-CloudwatchLogs-SecurityHub' : { 'Template' : 'CFN/EC-lz-config-securityhub-logging.yml' } },
    { 'SECLZ-local-SNS-topic' : { 'Template' : 'CFN/EC-lz-local-config-SNS.yml', 'Client':True} }
]

stacksets = [
    { 'SECLZ-Enable-Config-SecurityHub-Globally' :  { 'Template' : 'CFN/EC-lz-Config-SecurityHub-all-regions.yml' } },
    { 'SECLZ-Enable-Guardduty-Globally' :  { 'Template' : 'CFN/EC-lz-Config-Guardduty-all-regions.yml' } }
]

def main(argv):

    manifest = ''
    manifest_data = ''
    orgprofile = ''
    seclogprofile = ''
    verbosity = logging.ERROR

    try:
        opts, args = getopt.getopt(argv,"hvm:s:o:",["manifest", "seclog", "org", "verbose"])
    except getopt.GetoptError:
        usage()
        sys.exit(2)
    
    print("#######")
    print("####### AWS Landing Zone update script")
    print("")
    print("#######")

    # Parsing script parameters
    for opt, arg in opts:
        if opt == '-h':
            usage()
            sys.exit()
        elif opt in ("-m", "--manifest"):
            if (arg == ''):
                print("####### Manifest has not been provided. [\033[0;31;4mFAIL\033[0;37;4m]")
                print("Exiting...")
                sys.exit(1)
            else:
                try:
                    f=open(arg, "r")
                    manifest=f.read()
                    manifest_data = json.load(manifest)
                except FileNotFoundError as err:
                    print("####### Manifest file not found : {} [\033[0;31;4mFAIL\033[0;37;4m]".format(err.strerror))
                    print("Exiting...")
                    sys.exit(1)
                except AttributeError:
                    print("####### Manifest file {} is not a valid json file [\033[0;31;4mFAIL\033[0;37;4m]".format(arg))
                    print("Exiting...")
                    sys.exit(1)
        elif opt in ("-o", "--org"):
            orgprofile = arg
        elif opt in ("-s", "--seclog"):
            print("####### Using AWS profile : {}".format(arg))
            boto3.setup_default_session(profile_name=arg)
        elif opt in ("-v", "--verbose"):
            verbosity = logging.DEBUG
    
    logging.basicConfig(level=verbosity)

    
    
    

    print("#######")
    print("####### Checking account...")
    if (is_seclog() == False):
        print("####### Not a SECLOG account. [\033[0;31;4mFAIL\033[0;37;4m]")
        print("Exiting...")
        sys.exit(1)
    
    print("####### SECLOG account identified. [\033[0;32;4mOK\033[0;37;4m]")

    print("")
    print("#######")
    print("####### Updating SECLOG Account")
    print("#######")

    #update seclog stacks
    for key, val in manifest_data['stacks'].items():
        if val['update'] == True:
            if update_stack(key, stacks[key]) == False:
                print("Exiting...")
                sys.exit(1)
    

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
    print('   -o --org              : The AWS profile of the Organisation account - optional')
    print('   -v --verbose          : Debug mode - optional')

def get_account_id(Force = False):
    """
    This function gets te id of the account defined in the profile
        :param force: flag to force the retrieval of the account ID 
        :eturn: a string with the account id 
    """
    global account_id

    if account_id == '' or Force == True:
        client = boto3.client('sts')
        response = client.get_caller_identity()
        account_id = response['Account']
    return account_id

def get_linked_accounts():
    """
    Function to retrieve the Linked accounts from a SECLOG account
        :return: list with linked account details
    """
    linked_accounts = []
    accountId = get_account_id()
    client = boto3.client('guardduty')
    data0 = client.list_detectors()
    if data0['DetectorIds'][0] != '':
        data1 = client.list_members(DetectorId=data0['DetectorIds'][0])
        
        for member in data1['Members']:
            if member['RelationshipStatus'] == 'ENABLED':
                linked_accounts.append(member['AccoundId'])
                
    logging.debug("Linked accounts : {}".format(linked_accounts))
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

def update_stack(stack, template_data, params=[]):
    """
    Function that updates a stack defined in the parameters
        :stack:         The stack name
        :template_data: dict holding CFT details
        :params:        parameters to be passed to the stack
        :return:        True or False
    """
   
    template = template_data['Template']
    

    try:
        if  'Params' in template_data:
            f=open(template_data['Params'], "r")
            params = f.read()
    
        f=open(template, "r")
        template_body=f.read()
        print("### Updating stack : {}".format(stack))
        client = boto3.client('cloudformation')

        response = client.describe_stacks(StackName=stack)
        if response['Stacks'][0]['StackStatus'] not in ('CREATE_COMPLETE', 'UPDATE_COMPLETE'):
            print("#### Cannot update stack {}. Current status is : {} [\033[0;31;4mFAIL\033[0;37;4m]".format(stack,response['Stacks'][0]['StackStatus']))
            return False
        
        print("### Updating stack {} in progress ...".format(stack), end="")
        client.update_stack(StackName=stack, TemplateBody=template_body, Parameters=params)
        updated=False
        
        while updated == False:
            response = client.describe_stacks(StackName=stack)
            if 'COMPLETE' in response['Stacks'][0]['StackStatus'] :
                print("### Updating stack {} complete [\033[0;32;4mOK\033[0;37;4m]".format(stack))
                updated=True
                break
            elif 'FAILED' in response['Stacks'][0]['StackStatus'] :
                print("### Updating stack {} failed. Reason {} [\033[0;31;4mFAIL\033[0;37;4m]".format(stack, response['Stacks'][0]['StackStatusReason']))
                return False
            time.sleep(1)

        
        return True
        
    except FileNotFoundError as err:
        print("### Template not found : {} [\033[0;31;4mFAIL\033[0;37;4m]".format(err.strerror))
    except ClientError as err:
        if err.response['Error']['Code'] == 'AmazonCloudFormationException':
            print("### Stack {} not found : {} [\033[0;31;4mFAIL\033[0;37;4m]".format(err.response['Error']['Message']))
        elif err.response['Error']['Code'] == 'ValidationError' and err.response['Error']['Message'] == 'No updates are to be performed.':
            print("### Update not required for stack : {} [\033[0;33;4mNO ACTION\033[0;37;4m]".format(stack))
            return True
        else:
            print("### Updating stack {} failed. Reason : {} [\033[0;31;4mFAIL\033[0;37;4m]".format(err.response['Error']['Message']))
    
    return False
    

if __name__ == "__main__":
    main(sys.argv[1:])