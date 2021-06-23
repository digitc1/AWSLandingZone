#!/usr/bin/python

import sys, getopt
import subprocess, pkg_resources
import os
import subprocess
import shlex
import logging
import time
import boto3
import json
import zipfile
import threading
import cursor

from zipfile import ZipFile
from datetime import datetime
from enum import Enum
from colorama import Fore, Back, Style
from botocore.exceptions import BotoCoreError, ClientError, ProfileNotFound

 
 

account_id = ''

stacks = { 'SECLZ-Cloudtrail-KMS' : { 'Template' : 'CFN/EC-lz-Cloudtrail-kms-key.yml' , "Params" : 'CFN/EC-lz-TAGS-params.json' } ,
     'SECLZ-LogShipper-Lambdas-Bucket' : { 'Template' : 'CFN/EC-lz-s3-bucket-lambda-code.yml' , "Params" : 'CFN/EC-lz-TAGS-params.json' } ,
     'SECLZ-LogShipper-Lambdas' : { 'Template' : 'CFN/EC-lz-logshipper-lambdas.yml' , "Params" : 'CFN/EC-lz-TAGS-params.json' } ,
     'SECLZ-Central-Buckets' : { 'Template' : 'CFN/EC-lz-s3-buckets.yml' , "Params" : 'CFN/EC-lz-TAGS-params.json'} ,
     'SECLZ-Iam-Password-Policy' : { 'Template' : 'CFN/EC-lz-iam-setting_password_policy.yml' , "Params" : 'CFN/EC-lz-TAGS-params.json', 'Linked':True } ,
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
    ssm_actions = []
    stack_actions = []
    stacksets_actions = []

    
    sys.stdout = Unbuffered(sys.stdout)

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
 
        if not null_empty(manifest, 'stacks'): 
            stack_actions = manifest['stacks']
        if not null_empty(manifest, 'stacksets'):
            stacksets_actions = manifest['stacksets']
        if null_empty(manifest, 'ssm'):
            ssm_actions = manifest['ssm']

        seclog_status = Execution.NO_ACTION
        
        if ssm_actions:
            #update SSM parameters
            if account_id:
                result=update_ssm_parameter('/org/member/SecLogMasterAccountId', account_id)
                if result != Execution.NO_ACTION:
                    seclog_status = result  
            if will_update(ssm_actions, 'seclog-ou') and seclog_status != Execution.FAIL:
                result=update_ssm_parameter('/org/member/SecLogOU', ssm_actions['seclog-ou']['value'])
                if result != Execution.NO_ACTION:
                    seclog_status = result     
            if will_update(ssm_actions, 'notification-mail') and seclog_status != Execution.FAIL:
                result=update_ssm_parameter('/org/member/SecLog_notification-mail', ssm_actions['notification-mail']['value'])
                if result != Execution.NO_ACTION:
                    seclog_status = result     
            if will_update(manifest, 'version') and seclog_status != Execution.FAIL:
                result=update_ssm_parameter('/org/member/SLZVersion', manifest['version'])
                if result != Execution.NO_ACTION:
                    seclog_status = result  
            if will_update(ssm_actions, 'cloudtrail-groupname') and seclog_status != Execution.FAIL:
                result=update_ssm_parameter('/org/member/SecLog_cloudtrail-groupname', ssm_actions['cloudtrail-groupname']['value'])
                if result != Execution.NO_ACTION:
                    seclog_status = result  
            if  will_update(ssm_actions, 'insight-groupname') and seclog_status != Execution.FAIL:
                result=update_ssm_parameter('/org/member/SecLog_insight-groupname', ssm_actions['insight-groupname']['value'])
                if result != Execution.NO_ACTION:
                    seclog_status = result  
            if  will_update(ssm_actions, 'guardduty-groupname') and seclog_status != Execution.FAIL:
                result=update_ssm_parameter('/org/member/SecLog_guardduty-groupname', ssm_actions['guardduty-groupname']['value'])
                if result != Execution.NO_ACTION:
                    seclog_status = result  
            if  will_update(ssm_actions, 'securityhub-groupname') and seclog_status != Execution.FAIL:
                result=update_ssm_parameter('/org/member/SecLog_securityhub-groupname', ssm_actions['securityhub-groupname']['value'])
                if result != Execution.NO_ACTION:
                    seclog_status = result  
            if  will_update(ssm_actions, 'config-groupname') and seclog_status != Execution.FAIL:
                result=update_ssm_parameter('/org/member/SecLog_config-groupname', ssm_actions['config-groupname']['value'])
                if result != Execution.NO_ACTION:
                    seclog_status = result
            if  will_update(ssm_actions, 'alarms-groupname') and seclog_status != Execution.FAIL:
                result=update_ssm_parameter('/org/member/SecLog_alarms-groupname', ssm_actions['alarms-groupname']['value'])
                if result != Execution.NO_ACTION:
                    seclog_status = result

        cfn = boto3.client('cloudformation')
        

        #KMS template
        if will_update(stack_actions, 'SECLZ-Cloudtrail-KMS') and seclog_status != Execution.FAIL:            
            result = update_stack(cfn, 'SECLZ-Cloudtrail-KMS', stacks)
            if result != Execution.NO_ACTION:
                seclog_status = result
            elif result == Execution.OK :
                print("SSM parameter /org/member/KMSCloudtrailKey_arn update", end="")
                response = update_ssm_parameter('/org/member/KMSCloudtrailKey_arn', response['Parameter']['Value'])
                print(" [{}]".format(Status.OK.value))

        #logshipper lambdas S3 bucket
        if will_update(stack_actions, 'SECLZ-LogShipper-Lambdas-Bucket') and seclog_status != Execution.FAIL:
            result = update_stack(cfn, 'SECLZ-LogShipper-Lambdas-Bucket', stacks)
            if result != Execution.NO_ACTION:
                seclog_status = result
        
        #logshipper lambdas
        if will_update(stack_actions, 'SECLZ-LogShipper-Lambdas') and seclog_status != Execution.FAIL:
            
            #packaging lambdas
            now = datetime.now().strftime('%d%m%Y')
            cloudtrail_lambda=f'CloudtrailLogShipper-{now}.zip'
            with ZipFile(cloudtrail_lambda,'w') as zip:
                zip.write('LAMBDAS/CloudtrailLogShipper.py','CloudtrailLogShipper.py')

            config_lambda=f'ConfigLogShipper-{now}.zip'
            with ZipFile(config_lambda,'w') as zip:
                zip.write('LAMBDAS/ConfigLogShipper.py','CloudtrailLogShipper.py')

            #update CFT file
            if seclog_status != Execution.FAIL:
                template = stacks['SECLZ-LogShipper-Lambdas']['Template']
                print("Template SECLZ-LogShipper-Lambdas update ", end="")

                try:
                    template = stacks['SECLZ-LogShipper-Lambdas']['Template']
                    
                    with open(template, "r") as f:
                        template_body=f.read()
                
                    template_body.replace('##cloudtrailCodeURI##',cloudtrail_lambda).replace('##configCodeURI##',config_lambda)

                    template = f'EC-lz-logshipper-lambdas-{now}.yml'
                    with open(template, "w") as f:
                        f.write(template_body)
                

                    print(" [{}]".format(Status.OK.value))
                except FileNotFoundError as err:
                    print(" [{}]".format(Status.FAIL.value))
                    seclog_status = Execution.FAIL
            
            #package stack
            print("Template SECLZ-LogShipper-Lambdas package ", end="")
            bucket=f'lambda-artefacts-{account_id}'
            if seclog_status != Execution.FAIL:
                if has_profile:
                    prf = f'--profile {profile}'
                with Spinner():
                    cmd = f"aws cloudformation package --template-file {template} {prf} --s3-bucket {bucket} --output-template-file EC-lz-logshipper-lambdas-{now}.packaged.yml"
                    cmdarg = shlex.split(cmd)
                    proc = subprocess.Popen(cmdarg,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
                    output, errors = proc.communicate()
                
                if len(errors) > 0:
                    print(" failed. Readon {} [{}]".format(errors, Status.FAIL.value))
                    seclog_status = Execution.FAIL
                else:
                    print(" [{}]".format(Status.OK.value))

                os.remove(template)
                os.remove(cloudtrail_lambda)
                os.remove(config_lambda)
                
                #updating stack
                if seclog_status != Execution.FAIL:
                    stacks['SECLZ-LogShipper-Lambdas']['Template'] = f'EC-lz-logshipper-lambdas-{now}.packaged.yml'
                    result = update_stack(cfn, 'SECLZ-LogShipper-Lambdas', stacks)
                    if result != Execution.NO_ACTION:
                        seclog_status = result
                    os.remove(f'EC-lz-logshipper-lambdas-{now}.packaged.yml')

        #central buckets
        if will_update(stack_actions, 'SECLZ-Central-Buckets') and seclog_status != Execution.FAIL:
            result = update_stack(cfn, 'SECLZ-Central-Buckets', stacks)
            if result != Execution.NO_ACTION:
                seclog_status = result
        
        #password policy
        if will_update(stack_actions, 'SECLZ-Iam-Password-Policy') and seclog_status != Execution.FAIL:
            result = update_stack(cfn, 'SECLZ-Iam-Password-Policy', stacks)
            if result != Execution.NO_ACTION:
                seclog_status = result

        #cloudtrail SNS
        if will_update(stack_actions, 'SECLZ-config-cloudtrail-SNS') and seclog_status != Execution.FAIL:
            result = update_stack(cfn, 'SECLZ-config-cloudtrail-SNS', stacks)
            if result != Execution.NO_ACTION:
                seclog_status = result
        
        #guardduty detector
        if will_update(stack_actions, 'SECLZ-Guardduty-detector') and seclog_status != Execution.FAIL:
            result = update_stack(cfn, 'SECLZ-Guardduty-detector', stacks)
            if result != Execution.NO_ACTION:
                seclog_status = result
        
        #securityhub
        if will_update(stack_actions, 'SECLZ-SecurityHub') and seclog_status != Execution.FAIL:
            result = update_stack(cfn, 'SECLZ-SecurityHub', stacks)
            if result != Execution.NO_ACTION:
                seclog_status = result
        
        #cloudtrail notifications
        if will_update(stack_actions, 'SECLZ-Notifications-Cloudtrail') and seclog_status != Execution.FAIL:
            result = update_stack(cfn, 'SECLZ-Notifications-Cloudtrail', stacks)
            if result != Execution.NO_ACTION:
                seclog_status = result
        
        #cloudwatch logs
        if will_update(stack_actions, 'SECLZ-CloudwatchLogs-SecurityHub') and seclog_status != Execution.FAIL:
            result = update_stack(cfn, 'SECLZ-CloudwatchLogs-SecurityHub', stacks)
            if result != Execution.NO_ACTION:
                seclog_status = result
        
        #stackset Enable-Config-SecurityHub
        if will_update(stacksets_actions, 'SECLZ-Enable-Config-SecurityHub-Globally') and seclog_status != Execution.FAIL:            
            result = update_stackset(cfn, 'SECLZ-Enable-Config-SecurityHub-Globally', stacksets)
            if result != Execution.NO_ACTION:
                seclog_status = result
        
        #stackset Enable-Guardduty-Globally
        if will_update(stacksets_actions, 'SECLZ-Enable-Guardduty-Globally') and seclog_status != Execution.FAIL:            
            result = update_stackset(cfn, 'SECLZ-Enable-Guardduty-Globally', stacksets)
            if result != Execution.NO_ACTION:
                seclog_status = result

        print("")
        print("SECLOG account {} update ".format(account_id), end="")
        if seclog_status == Execution.FAIL:
            print("[{}]".format(Status.FAIL.value))
        elif seclog_status == Execution.OK:
            print("[{}]".format(Status.OK.value))
        else:
            print("[{}]".format(Status.NO_ACTION.value))

        #update linked account stacks
        if seclog_status == Execution.FAIL and len(linked_accounts) > 0:
            print("Skipping linked accounts update")
        else:
            for linked in linked_accounts:
                
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

                if ssm_actions:
                    #update SSM parameters
                    if account_id:
                        result=update_ssm_parameter('/org/member/SecLogMasterAccountId', account_id)
                        if result != Execution.NO_ACTION:
                            linked_status = result  
                    if will_update(ssm_actions, 'seclog-ou') and linked_status != Execution.FAIL:
                        result=update_ssm_parameter('/org/member/SecLogOU', ssm_actions['seclog-ou']['value'])
                        if result != Execution.NO_ACTION:
                            linked_status = result     
                    if will_update(ssm_actions, 'notification-mail') and linked_status != Execution.FAIL:
                        result=update_ssm_parameter('/org/member/SecLog_notification-mail', ssm_actions['notification-mail']['value'])
                        if result != Execution.NO_ACTION:
                            linked_status = result     
                    if will_update(manifest, 'version') and linked_status != Execution.FAIL:
                        result=update_ssm_parameter('/org/member/SLZVersion', manifest['version'])
                        if result != Execution.NO_ACTION:
                            linked_status = result  
                    if will_update(ssm_actions, 'cloudtrail-groupname') and linked_status != Execution.FAIL:
                        result=update_ssm_parameter('/org/member/SecLog_cloudtrail-groupname', ssm_actions['cloudtrail-groupname']['value'])
                        if result != Execution.NO_ACTION:
                            linked_status = result  
                    if  will_update(ssm_actions, 'insight-groupname') and linked_status != Execution.FAIL:
                        result=update_ssm_parameter('/org/member/SecLog_insight-groupname', ssm_actions['insight-groupname']['value'])
                        if result != Execution.NO_ACTION:
                            linked_status = result  
                    if  will_update(ssm_actions, 'guardduty-groupname') and linked_status != Execution.FAIL:
                        result=update_ssm_parameter('/org/member/SecLog_guardduty-groupname', ssm_actions['guardduty-groupname']['value'])
                        if result != Execution.NO_ACTION:
                            linked_status = result  
                    if  will_update(ssm_actions, 'securityhub-groupname') and linked_status != Execution.FAIL:
                        result=update_ssm_parameter('/org/member/SecLog_securityhub-groupname', ssm_actions['securityhub-groupname']['value'])
                        if result != Execution.NO_ACTION:
                            linked_status = result  
                    if  will_update(ssm_actions, 'config-groupname') and linked_status != Execution.FAIL:
                        result=update_ssm_parameter('/org/member/SecLog_config-groupname', ssm_actions['config-groupname']['value'])
                        if result != Execution.NO_ACTION:
                            seclog_status = result

                #password policy
                if will_update(stack_actions, 'SECLZ-Iam-Password-Policy') and linked_status != Execution.FAIL:
                    result = update_stack(cfn, 'SECLZ-Iam-Password-Policy', stacks)
                    if result != Execution.NO_ACTION:
                        linked_status = result
                        
                #cloudtrail SNS
                if will_update(stack_actions, 'SECLZ-config-cloudtrail-SNS') and linked_status != Execution.FAIL:
                    result = update_stack(cfn, 'SECLZ-config-cloudtrail-SNS', stacks)
                    if result != Execution.NO_ACTION:
                        linked_status = result
                        
                #securityhub
                if will_update(stack_actions, 'SECLZ-SecurityHub') and linked_status != Execution.FAIL:
                    result = update_stack(cfn, 'SECLZ-SecurityHub', stacks)
                    if result != Execution.NO_ACTION:
                        linked_status = result
                        
                #cloudtrail notification
                if will_update(stack_actions, 'SECLZ-Notifications-Cloudtrail') and linked_status != Execution.FAIL:
                    result = update_stack(cfn, 'SECLZ-Notifications-Cloudtrail', stacks)
                    if result != Execution.NO_ACTION:
                        linked_status = result
                    
                #local SNS topic
                if will_update(stack_actions, 'SECLZ-local-SNS-topic') and linked_status != Execution.FAIL:
                    result = update_stack(cfn, 'SECLZ-local-SNS-topic', stacks)
                    if result != Execution.NO_ACTION:
                        linked_status = result
                    

                print("")
                print("Linked account {} update ".format(linked), end="")
                if linked_status == Execution.FAIL:
                    print("[{}]".format(Status.FAIL.value))
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

def null_empty(dict, key):
    """
    Function that checks if the a key exists in the dict and the value is not empty
        :return: true or false
    """
   
    if key in dict:
        return False
    return True

def will_update(dict, key):
    """
    Function that checks if the a key exists in the dict and the value is not empty
        :return: true or false
    """
    if not null_empty(dict, key) and 'update' in dict[key] and dict[key]['update'] == True:
        return True
    else: return False

def update_ssm_parameter(parameter, value):
    """
    Function used to update an SSM parameter if the value is different
        :paremter:      parameter name
        :params:        the value to be updated
        :return: true or false
    """
    exists = True
    client = boto3.client('ssm')
    print(f"SSM parameter {parameter} update ", end="")
    try:
        response = client.get_parameter(Name=parameter)
    except client.exceptions.ParameterNotFound as err:
        print("\033[2K\033[1GSSM parameter {} does not exist. Creating...".format(parameter), end="")
        exists=False
    try:
        if exists == False or ('Value' in response['Parameter'] and value != response['Parameter']['Value']):
            response = client.put_parameter(
                Name=parameter,
                Value=value,
                Type='String',
                Overwrite=True|False)
            if response['Version']:
                print("\033[2K\033[1SSM parameter {parameter} update [{}]".format(parameter,Status.OK.value))
                return Execution.OK
    
    except Exception as err:
        print("\033[2K\033[1SSM parameter {parameter} update failed. Reason {} [{}]".format(parameter,err.response['Error']['Message'], Status.FAIL.value))
        return Execution.FAIL
    
    print(" [{}]".format(Status.NO_ACTION.value))
    return Execution.NO_ACTION

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

    print("Stack {} update ".format(stack), end="")

    try:
        with open(template, "r") as f:
            template_body=f.read()
        response = client.describe_stacks(StackName=stack)
    except FileNotFoundError as err:
        print("\033[2K\033[Stack template file not found : {} [{}]".format(err.strerror,Status.FAIL.value))
        return Execution.FAIL
    except ClientError as err:
        if err.response['Error']['Code'] == 'AmazonCloudFormationException':
            print("\033[2K\033[1GStack {} not found : {} [{}]".format(stack,err.response['Error']['Message'],Status.FAIL.value))
        else:
            print("\033[2K\033[1GStack {} update failed. Reason : {} [{}]".format(stack,err.response['Error']['Message'],Status.FAIL.value))
    

    if not params: 
        if not null_empty(templates[stack], 'Params'):
            try:
                with open(templates[stack]['Params']) as f:
                    params = json.load(f)
            except FileNotFoundError as err:
                print("\033[2K\033[1GParameter file not found : {} [{}]".format(err.strerror,Status.FAIL.value))
                Execution.FAIL
            except json.decoder.JSONDecodeError as err:
                print("\033[2K\033[1GParameter file problem : {} [{}]".format(err.strerror,Status.FAIL.value))
                Execution.FAIL
        else: 
            if not null_empty(response['Stacks'][0], 'Parameters'):
                params = response['Stacks'][0]['Parameters']
    
    
    if not null_empty(response['Stacks'][0], 'Capabilities'):
        capabilities = response['Stacks'][0]['Capabilities']
    


    if response['Stacks'][0]['StackStatus'] not in ('CREATE_COMPLETE', 'UPDATE_COMPLETE','UPDATE_ROLLBACK_COMPLETE'):
        print("Cannot update stack {}. Current status is : {} [{}]".format(stack,response['Stacks'][0]['StackStatus'],Status.FAIL.value ))
        return Execution.FAIL
        
    print("in progress ".format(stack), end="")
    with Spinner():
        try:
            client.update_stack(StackName=stack, TemplateBody=template_body, Parameters=params, Capabilities=capabilities)
            updated=False
        
            while updated == False:
                response = client.describe_stacks(StackName=stack)
                if 'COMPLETE' in response['Stacks'][0]['StackStatus'] :
                    print("\033[2K\033[1GStack {} update [{}]".format(stack,Status.OK.value))
                    updated=True
                    break
                elif 'FAILED' in response['Stacks'][0]['StackStatus'] or 'ROLLBACK' in response['Stacks'][0]['StackStatus'] :
                    print("\033[2K\033[1GStack {} update failed. Reason {} [{}]".format(stack, response['Stacks'][0]['StackStatusReason'],Status.FAIL.value))
                    return Execution.FAIL
               
            return Execution.OK
        
        except ClientError as err:
            if err.response['Error']['Code'] == 'AmazonCloudFormationException':
                print("\033[2K\033[1GStack {} not found : {} [{}]".format(stack,err.response['Error']['Message'],Status.FAIL.value))
            elif err.response['Error']['Code'] == 'ValidationError' and err.response['Error']['Message'] == 'No updates are to be performed.':
                print("\033[2K\033[1GStack {} update [{}]".format(stack,Status.NO_ACTION.value))
                return Execution.NO_ACTION
            else:
                print("\033[2K\033[1GStack {} update failed. Reason : {} [{}]".format(stack,err.response['Error']['Message'],Status.FAIL.value))
        
        return Execution.FAIL

def update_stackset(client, stackset, templates, params=[]):
    """
    Function that updates a stackset defined in the parameters
        :stackset:         The stackset name
        :template_data: dict holding CFT details
        :params:        parameters to be passed to the stackset
        :return:        True or False
    """
    template = templates[stackset]['Template']
    capabilities=[]

    print("StackSet {} update ".format(stackset), end="")

    try:
        with open(template, "r") as f:
            template_body=f.read()
        response = client.describe_stack_set(StackSetName=stackset)
    except FileNotFoundError as err:
        print("\033[2K\033[StackSet template file not found : {} [{}]".format(err.strerror,Status.FAIL.value))
        return Execution.FAIL
    except ClientError as err:
        if err.response['Error']['Code'] == 'AmazonCloudFormationException':
            print("\033[2K\033[1GStackSet {} not found : {} [{}]".format(stackset,err.response['Error']['Message'],Status.FAIL.value))
        else:
            print("\033[2K\033[1GStackSet {} update failed. Reason : {} [{}]".format(stackset,err.response['Error']['Message'],Status.FAIL.value))
    

    if not params: 
        if not null_empty(templates[stackset], 'Params'):
            try:
                with open(templates[stackset]['Params']) as f:
                    params = json.load(f)
            except FileNotFoundError as err:
                print("\033[2K\033[1GParameter file not found : {} [{}]".format(err.strerror,Status.FAIL.value))
                Execution.FAIL
            except json.decoder.JSONDecodeError as err:
                print("\033[2K\033[1GParameter file problem : {} [{}]".format(err.strerror,Status.FAIL.value))
                Execution.FAIL
        else: 
            if not null_empty(response['StackSet'], 'Parameters'):
                params = response['StackSet']['Parameters']
    
    
    if not null_empty(response['StackSet'], 'Capabilities'):
        capabilities = response['StackSet']['Capabilities']
    


    if response['StackSet']['Status'] not in ('ACTIVE'):
        print("Cannot update stackset {}. Current status is : {} [{}]".format(stackset,response['StackSet']['Status'],Status.FAIL.value ))
        return Execution.FAIL
        
    print("in progress ".format(stackset), end="")
    with Spinner():
        try:
            operationPreferences={
                'RegionConcurrencyType': 'PARALLEL',
                'FailureToleranceCount': 9,
                'MaxConcurrentCount': 10,
            }
            client.update_stack_set(
                StackSetName=stackset, 
                TemplateBody=template_body, 
                Parameters=params, 
                Capabilities=capabilities,
                OperationPreferences=operationPreferences
                )
           
            updated=False
        
            while updated == False:
                response = client.describe_stack_set(StackSetName=stackset)
                if 'ACTIVE' in response['StackSet']['Status'] :
                    print("\033[2K\033[1GStackSet {} update [{}]".format(stackset,Status.OK.value))
                    updated=True
                    break
                
            return Execution.OK
        
        except ClientError as err:
            if err.response['Error']['Code'] == 'AmazonCloudFormationException':
                print("\033[2K\033[1GStackSet {} not found : {} [{}]".format(stackset,err.response['Error']['Message'],Status.FAIL.value))
            elif err.response['Error']['Code'] == 'ValidationError' and err.response['Error']['Message'] == 'No updates are to be performed.':
                print("\033[2K\033[1GStackSet {} update [{}]".format(stackset,Status.NO_ACTION.value))
                return Execution.NO_ACTION
            else:
                print("\033[2K\033[1GStackSet {} update failed. Reason : {} [{}]".format(stackset,err.response['Error']['Message'],Status.FAIL.value))
        
        return Execution.FAIL
    

class Execution(Enum):
    FAIL = -1
    OK = 0
    NO_ACTION = 2

class Status(Enum):
    FAIL = Fore.RED + "FAIL" + Style.RESET_ALL
    OK = Fore.GREEN + "OK" + Style.RESET_ALL
    NO_ACTION = Fore.YELLOW + "NO ACTION" + Style.RESET_ALL

class Unbuffered(object):
   def __init__(self, stream):
       self.stream = stream
   def write(self, data):
       self.stream.write(data)
       self.stream.flush()
   def writelines(self, datas):
       self.stream.writelines(datas)
       self.stream.flush()
   def __getattr__(self, attr):
       return getattr(self.stream, attr)


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


