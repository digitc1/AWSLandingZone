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

stacks = { 'SECLZ-Cloudtrail-KMS' : { 'Template' : 'CFN/EC-lz-Cloudtrail-kms-key.yml' } ,
     'SECLZ-LogShipper-Lambdas-Bucket' : { 'Template' : 'CFN/EC-lz-s3-bucket-lambda-code.yml' } ,
     'SECLZ-LogShipper-Lambdas' : { 'Template' : 'CFN/EC-lz-logshipper-lambdas.yml' } ,
     'SECLZ-Central-Buckets' : { 'Template' : 'CFN/EC-lz-s3-buckets.yml' , "Params" : 'CFN/EC-lz-TAGS-params.json'} ,
     'SECLZ-Iam-Password-Policy' : { 'Template' : 'CFN/EC-lz-iam-setting_password_policy.yml', 'Linked':True } ,
     'SECLZ-config-cloudtrail-SNS' : { 'Template' : 'CFN/EC-lz-config-cloudtrail-logging.yml', 'Linked':True } ,
     'SECLZ-Guardduty-detector' : { 'Template' : 'CFN/EC-lz-guardDuty-detector.yml', 'Linked':True } ,
     'SECLZ-SecurityHub' : { 'Template' : 'CFN/EC-lz-securityHub.yml', 'Linked':True } ,
     'SECLZ-Notifications-Cloudtrail' : { 'Template' : 'CFN/EC-lz-notifications.yml', 'Linked':True } ,
     'SECLZ-CloudwatchLogs-SecurityHub' : { 'Template' : 'CFN/EC-lz-config-securityhub-logging.yml' } ,
     'SECLZ-local-SNS-topic' : { 'Template' : 'CFN/EC-lz-local-config-SNS.yml', 'Linked':True} }


stacksets = { 'SECLZ-Enable-Config-SecurityHub-Globally' :  { 'Template' : 'CFN/EC-lz-Config-SecurityHub-all-regions.yml' } ,
     'SECLZ-Enable-Guardduty-Globally' :  { 'Template' : 'CFN/EC-lz-Config-Guardduty-all-regions.yml' } }


def main(argv):
    start_time = time.time()
    manifest = ''
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


    # Parsing script parameters
    for opt, arg in opts:
        if opt == '-h':
            usage()
            sys.exit()
        elif opt in ("-m", "--manifest"):
            if (arg == ''):
                print("Manifest has not been provided. [\033[0;31;40mFAIL\033[0;37;40m]")
                print("Exiting...")
                sys.exit(1)
            else:
                try:
                    with open(arg) as f:
                        manifest = json.load(f)
                except FileNotFoundError as err:
                    print("Manifest file not found : {} [\033[0;31;40mFAIL\033[0;37;40m]".format(err.strerror))
                    print("Exiting...")
                    sys.exit(1)
                except AttributeError:
                    print("Manifest file {} is not a valid json file [\033[0;31;40mFAIL\033[0;37;40m]".format(arg))
                    print("Exiting...")
                    sys.exit(1)
        elif opt in ("-o", "--org"):
            orgprofile = arg
        elif opt in ("-s", "--seclog"):
            print("Using AWS profile : {}".format(arg))

            boto3.setup_default_session(profile_name=arg)
        elif opt in ("-v", "--verbose"):
            verbosity = logging.DEBUG
    
    logging.basicConfig(level=verbosity)


    if (is_seclog() == False):
        print("Not a SECLOG account. [\033[0;31;40mFAIL\033[0;37;40m]")
        print("Exiting...")
        sys.exit(1)
    
    print("SECLOG account identified. [\033[0;32;40mOK\033[0;37;40m]")
    print("Updating account...")
    print("")

    #update seclog stacks
    stack_actions = manifest['stacks']

    if 'SECLZ-Cloudtrail-KMS' in stack_actions and stack_actions['SECLZ-Cloudtrail-KMS']['update'] == True:
        if update_stack('SECLZ-Cloudtrail-KMS', stacks) == False:
            print("Exiting...")
            sys.exit(1)
        else:
            print("SSM parameter /org/member/KMSCloudtrailKey_arn update in progress...", end="")
            client = boto3.client('ssm')
            response = client.get_parameter(Name='/org/member/KMSCloudtrailKey_arn')
            response = client.put_parameter(Name='/org/member/KMSCloudtrailKey_arn', Value=response['Parameter']['Value'], Type=response['Parameter']['Type'], Overwrite=True)
            print("\rSSM parameter /org/member/KMSCloudtrailKey_arn updated with version [\033[0;32;40mOK\033[0;37;40m]".format(response['Version']))

    if 'SECLZ-LogShipper-Lambdas-Bucket' in stack_actions and stack_actions['SECLZ-LogShipper-Lambdas-Bucket']['update'] == True:
        if update_stack('SECLZ-LogShipper-Lambdas-Bucket', stacks) == False:
            print("Exiting...")
            sys.exit(1)

    if 'SECLZ-LogShipper-Lambdas' in stack_actions and stack_actions['SECLZ-LogShipper-Lambdas']['update'] == True:
        #TODO
        print("")
    
    if 'SECLZ-Central-Buckets' in stack_actions and stack_actions['SECLZ-Central-Buckets']['update'] == True:
        if update_stack('SECLZ-Central-Buckets', stacks) == False:
            print("Exiting...")
            sys.exit(1)
    
    if 'SECLZ-Iam-Password-Policy' in stack_actions and stack_actions['SECLZ-Iam-Password-Policy']['update'] == True:
        if update_stack('SECLZ-Iam-Password-Policy', stacks) == False:
            print("Exiting...")
            sys.exit(1)

    if 'SECLZ-config-cloudtrail-SNS' in stack_actions and stack_actions['SECLZ-config-cloudtrail-SNS']['update'] == True:
        if update_stack('SECLZ-config-cloudtrail-SNS', stacks) == False:
            print("Exiting...")
            sys.exit(1)
    
    if 'SECLZ-Guardduty-detector' in stack_actions and stack_actions['SECLZ-Guardduty-detector']['update'] == True:
        if update_stack('SECLZ-Guardduty-detector', stacks) == False:
            print("Exiting...")
            sys.exit(1)
    
    if 'SECLZ-SecurityHub' in stack_actions and stack_actions['SECLZ-SecurityHub']['update'] == True:
        if update_stack('SECLZ-SecurityHub', stacks) == False:
            print("Exiting...")
            sys.exit(1)
    
    if 'SECLZ-Notifications-Cloudtrail' in stack_actions and stack_actions['SECLZ-Notifications-Cloudtrail']['update'] == True:
        if update_stack('SECLZ-Notifications-Cloudtrail', stacks) == False:
            print("Exiting...")
            sys.exit(1)
    
    if 'SECLZ-CloudwatchLogs-SecurityHub' in stack_actions and stack_actions['SECLZ-CloudwatchLogs-SecurityHub']['update'] == True:
        if update_stack('SECLZ-CloudwatchLogs-SecurityHub', stacks) == False:
            print("Exiting...")
            sys.exit(1)
    
    print("")
    print("SECLOG account updated [\033[0;32;40mOK\033[0;37;40m]")

    print("")
    print("Identifying linked accounts...")
    linked_accounts = get_linked_accounts()
    print("{}".format(linked_accounts))
    
    print("")
    print("####### AWS Landing Zone update script is done. Executed in {} seconds".format(time.time() - start_time))
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
    response = client.list_detectors()
    
    if response['DetectorIds'][0] != '':
        data = client.list_members(DetectorId=response['DetectorIds'][0])
        
        for member in data['Members']:
            if member['relationshipStatus'] == 'ENABLED':
                linked_accounts.append(member['accountId'])
                
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

def update_stack(stack, templates, params=[]):
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
        client = boto3.client('cloudformation')

        response = client.describe_stacks(StackName=stack)

        if 'Params' in templates[stack]:
            with open(templates[stack]['Params']) as f:
                params = json.load(f)
        else: 
            if 'Parameters' in response['Stacks'][0]:
                params = response['Stacks'][0]['Parameters']
        
        
        if 'Capabilities' in response['Stacks'][0]:
            capabilities = response['Stacks'][0]['Capabilities']
        


        if response['Stacks'][0]['StackStatus'] not in ('CREATE_COMPLETE', 'UPDATE_COMPLETE'):
            print("Cannot update stack {}. Current status is : {} [\033[0;31;40mFAIL\033[0;37;40m]".format(stack,response['Stacks'][0]['StackStatus']))
            return False
        
        print("in progress ...".format(stack), end="")
        client.update_stack(StackName=stack, TemplateBody=template_body, Parameters=params, Capabilities=capabilities)
        updated=False
        
        while updated == False:
            response = client.describe_stacks(StackName=stack)
            if 'COMPLETE' in response['Stacks'][0]['StackStatus'] :
                print("\rUpdating stack {} complete [\033[0;32;40mOK\033[0;37;40m]".format(stack))
                updated=True
                break
            elif 'FAILED' in response['Stacks'][0]['StackStatus'] :
                print("\rUpdating stack {} failed. Reason {} [\033[0;31;40mFAIL\033[0;37;40m]".format(stack, response['Stacks'][0]['StackStatusReason']))
                return False
            time.sleep(1)

        
        return True
        
    except FileNotFoundError as err:
        print("Template not found : {} [\033[0;31;40mFAIL\033[0;37;40m]".format(err.strerror))
    except ClientError as err:
        if err.response['Error']['Code'] == 'AmazonCloudFormationException':
            print("\rStack {} not found : {} [\033[0;31;40mFAIL\033[0;37;40m]".format(err.response['Error']['Message']))
        elif err.response['Error']['Code'] == 'ValidationError' and err.response['Error']['Message'] == 'No updates are to be performed.':
            print("\rStack {} update not required [\033[0;33;40mNO ACTION\033[0;37;40m]".format(stack))
            return True
        else:
            print("\rStack {} update failed. Reason : {} [\033[0;31;40mFAIL\033[0;37;40m]".format(err.response['Error']['Message']))
    
    return False
    

if __name__ == "__main__":
    main(sys.argv[1:])