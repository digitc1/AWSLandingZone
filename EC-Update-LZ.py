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
import yaml
from cfn_tools import load_yaml, dump_yaml

from zipfile import ZipFile
from datetime import datetime
from enum import Enum
from colorama import Fore, Back, Style
from botocore.exceptions import BotoCoreError, ClientError, ProfileNotFound
from botocore.config import Config

 
 
account_id = ''

stacks = { 'SECLZ-Cloudtrail-KMS' : { 'Template' : 'CFN/EC-lz-Cloudtrail-kms-key.yml' } ,
     'SECLZ-LogShipper-Lambdas-Bucket' : { 'Template' : 'CFN/EC-lz-s3-bucket-lambda-code.yml' } ,
     'SECLZ-LogShipper-Lambdas' : { 'Template' : 'CFN/EC-lz-logshipper-lambdas.yml' } ,
     'SECLZ-Central-Buckets' : { 'Template' : 'CFN/EC-lz-s3-buckets.yml'} ,
     'SECLZ-Iam-Password-Policy' : { 'Template' : 'CFN/EC-lz-iam-setting_password_policy.yml', 'Linked':True } ,
     'SECLZ-config-cloudtrail-SNS' : { 'Template' : 'CFN/EC-lz-config-cloudtrail-logging.yml', 'Linked':True } ,
     'SECLZ-Guardduty-detector' : { 'Template' : 'CFN/EC-lz-guardDuty-detector.yml', 'Linked':True } ,
     'SECLZ-SecurityHub' : { 'Template' : 'CFN/EC-lz-securityHub.yml', 'Linked':True } ,
     'SECLZ-Notifications-Cloudtrail' : { 'Template' : 'CFN/EC-lz-notifications.yml', 'Linked':True } ,
     'SECLZ-CloudwatchLogs-SecurityHub' : { 'Template' : 'CFN/EC-lz-config-securityhub-logging.yml' } ,
     'SECLZ-local-SNS-topic' : { 'Template' : 'CFN/EC-lz-local-config-SNS.yml', 'Linked':True} }


stacksets = { 'SECLZ-Enable-Config-SecurityHub-Globally' :  { 'Template' : 'CFN/EC-lz-Config-SecurityHub-all-regions.yml' } ,
     'SECLZ-Enable-Guardduty-Globally' :  { 'Template' : 'CFN/EC-lz-Config-Guardduty-all-regions.yml' } }

tags = []

all_regions = ["ap-northeast-1","ap-northeast-2","ap-northeast-3","ap-south-1","ap-southeast-1","ap-southeast-2","ca-central-1","eu-central-1","eu-north-1","eu-west-1", "eu-west-2","eu-west-3","sa-east-1","us-east-1","us-east-2","us-west-1","us-west-2"]

def main(argv):
    
    global tags
    start_time = time.time()
    manifest = ''
    profile = ''
    org_account='246933597933'
    has_profile = False
    verbosity = logging.ERROR
    ssm_actions = []
    stack_actions = []
    securityhub_actions = []
    stacksets_actions = []
    cis_actions = []
    version=None
    
    
    boto3_config = Config(
        retries = dict(
            max_attempts = 10
        )
    )

    
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
                print(f"Manifest has not been provided. [{Status.FAIL.value}]")
                print("Exiting...")
                sys.exit(1)
            else:
                try:
                    with open(arg) as f:
                        manifest = json.load(f)
                except FileNotFoundError as err:
                    print(f"Manifest file not found : {err.strerror} [{Status.FAIL.value}]")
                    print("Exiting...")
                    sys.exit(1)
                except AttributeError:
                    print("fManifest file {arg} is not a valid json [{Status.FAIL.value}]")
                    print("Exiting...")
                    sys.exit(1)
        elif opt in ("-o", "--org"):
            print(f"Using Organization account : {arg}")
            org_account = arg
        elif opt in ("-s", "--seclog"):
            profiles = arg.split(',')
            has_profile = True
            if len(profiles) > 1:
                print(f"Multiple AWS profiles delected  : {profiles}")
        elif opt in ("-v", "--verbose"):
            verbosity = logging.DEBUG
    

    try:
        with open('CFN/EC-lz-TAGS.json') as f:
            tags = json.load(f)
    except FileNotFoundError as err:
                    print(f"Tag file not found : {err.strerror} [{Status.FAIL.value}]")
                    print("Exiting...")
                    sys.exit(1)
    except AttributeError:
                    print(f"Manifest file {arg} is not a valid json [{Status.FAIL.value}]")
                    print("Exiting...")
                    sys.exit(1)

    if 'tags' in manifest:
        tags = merge_tags(tags, manifest['tags'])
    
    logging.basicConfig(level=verbosity)
    p = 0
    loop = True
    while loop:
        if has_profile:
            if p  < len(profiles):
                profile = profiles[p]
                p=p+1
                try:
                    print(f"Using AWS profile : {profile}")
                    boto3.setup_default_session(profile_name=profile)
                    get_account_id(True)
                except ProfileNotFound as err:
                    print(f"{err} [{Status.FAIL.value}]")
                    print("Exiting...")
                    sys.exit(1)
            else:
                break
        else:
            loop = False 

        if (is_seclog() == False):
            print(f"Not a SECLOG account. [{Status.FAIL.value}]")
            print("Exiting...")
            sys.exit(1)
        
        print(f"SECLOG account identified. [{Status.OK.value}]")
        print("")

        linked_accounts = get_linked_accounts()
        
        
 
        if not null_empty(manifest, 'stacks'): 
            stack_actions = manifest['stacks']

        if not null_empty(manifest, 'version'): 
            version = manifest['version']


        if not null_empty(manifest, 'stacksets'):
            stacksets_actions = manifest['stacksets']

        if not null_empty(manifest, 'ssm'):
            ssm_actions = manifest['ssm']

        if not null_empty(manifest, 'cis'):
            all_regions = manifest['regions']
            cis_actions = manifest['cis']
        
        if not null_empty(manifest, 'regions'):
            all_regions = manifest['regions']

        if not null_empty(manifest, 'accounts'):
            all_regions = manifest['accounts']
        
        if not null_empty(manifest, 'securityhub'):
            securityhub_actions = manifest['securityhub']

        seclog_status = Execution.NO_ACTION
        
        #update seclog stacks

        if len(all_regions['exclude']) > 0 and account_id in all_regions['exclude']:
            print(f"Skipping SECLOG account {account_id}")
        else:
        
            print(f"Updating SECLOG account {account_id}")
            print("")
            

            if ssm_actions:
                cfnssm = boto3.client('ssm')
                #update SSM parameters
                if do_update(ssm_actions, 'seclog-ou') and seclog_status != Execution.FAIL:
                    result=update_ssm_parameter(cfnssm, '/org/member/SecLogOU', ssm_actions['seclog-ou']['value'])
                    if result != Execution.OK:
                        will_update(stack_actions,'SECLZ-config-cloudtrail-SNS')
                    if result != Execution.NO_ACTION:
                        seclog_status = result
                #add tags
                if 'tags' in ssm_actions['seclog-ou'] and ssm_actions['seclog-ou']['tags'] == True:
                    seclog_status = add_tags_parameter(cfnssm, '/org/member/SecLogOU')

                if do_update(ssm_actions, 'notification-mail') and seclog_status != Execution.FAIL:
                    result=update_ssm_parameter(cfnssm, '/org/member/SecLog_notification-mail', ssm_actions['notification-mail']['value'])
                    if result != Execution.OK:
                        will_update(stack_actions,'SECLZ-config-cloudtrail-SNS')
                    if result != Execution.NO_ACTION:
                        seclog_status = result
                #add tags
                if 'tags' in ssm_actions['notification-mail'] and ssm_actions['notification-mail']['tags'] == True:
                    seclog_status = add_tags_parameter(cfnssm, '/org/member/SecLog_notification-mail')

                if do_update(ssm_actions, 'cloudtrail-groupname') and seclog_status != Execution.FAIL:
                    result=update_ssm_parameter(cfnssm, '/org/member/SecLog_cloudtrail-groupname', ssm_actions['cloudtrail-groupname']['value'])
                    if result != Execution.OK:
                        will_update(stack_actions,'SECLZ-config-cloudtrail-SNS')
                        will_update(stack_actions,'SECLZ-LogShipper-Lambdas')
                        will_update(stack_actions,'SECLZ-Notifications-Cloudtrail')
                    if result != Execution.NO_ACTION:
                        seclog_status = result  
                #add tags
                if 'tags' in ssm_actions['cloudtrail-groupname'] and ssm_actions['cloudtrail-groupname']['tags'] == True:
                    seclog_status = add_tags_parameter(cfnssm, '/org/member/SecLog_cloudtrail-groupname')

                if  do_update(ssm_actions, 'insight-groupname') and seclog_status != Execution.FAIL:
                    result=update_ssm_parameter(cfnssm, '/org/member/SecLog_insight-groupname', ssm_actions['insight-groupname']['value'])
                    if result != Execution.OK:
                        will_update(stack_actions,'SECLZ-config-cloudtrail-SNS')
                        will_update(stack_actions,'SECLZ-LogShipper-Lambdas')
                    if result != Execution.NO_ACTION:
                        seclog_status = result  
                #add tags
                if 'tags' in ssm_actions['insight-groupname'] and ssm_actions['insight-groupname']['tags'] == True:
                    seclog_status = add_tags_parameter(cfnssm, '/org/member/SecLog_insight-groupname')

                if  do_update(ssm_actions, 'guardduty-groupname') and seclog_status != Execution.FAIL:
                    for reg in all_regions:
                        cfnssm = boto3.client('ssm', region_name=reg)
                        result=update_ssm_parameter(cfnssm, '/org/member/SecLog_guardduty-groupname', ssm_actions['guardduty-groupname']['value'], reg)
                        if result != Execution.OK:
                            will_update(stack_actions,'SECLZ-Guardduty-detector')
                            will_update(stacksets_actions,'SECLZ-Enable-Guardduty-Globally')
                        if result != Execution.NO_ACTION:
                            seclog_status = result  
                    cfnssm = boto3.client('ssm')
                #add tags
                if 'tags' in ssm_actions['guardduty-groupname'] and ssm_actions['seclog-ou']['tags'] == True:
                    for reg in all_regions:
                        cfnssm = boto3.client('ssm', region_name=reg)
                        seclog_status = add_tags_parameter(cfnssm, '/org/member/SecLog_guardduty-groupname', reg)
                
                    cfnssm = boto3.client('ssm')
                if  do_update(ssm_actions, 'securityhub-groupname') and seclog_status != Execution.FAIL:
                    result=update_ssm_parameter(cfnssm, '/org/member/SecLog_securityhub-groupname', ssm_actions['securityhub-groupname']['value'])
                    if result != Execution.OK:
                        will_update(stack_actions,'SECLZ-CloudwatchLogs-SecurityHub')                            
                    if result != Execution.NO_ACTION:
                        seclog_status = result  
                #add tags
                if 'tags' in ssm_actions['securityhub-groupname'] and ssm_actions['securityhub-groupname']['tags'] == True:
                    seclog_status = add_tags_parameter(cfnssm, '/org/member/SecLog_securityhub-groupname')

                if  do_update(ssm_actions, 'config-groupname') and seclog_status != Execution.FAIL:
                    result=update_ssm_parameter(cfnssm, '/org/member/SecLog_config-groupname', ssm_actions['config-groupname']['value'])
                    if result != Execution.OK:
                        will_update(stack_actions,'SECLZ-config-cloudtrail-SNS')                            
                        will_update(stack_actions,'SECLZ-LogShipper-Lambdas')       
                    if result != Execution.NO_ACTION:
                        seclog_status = result
                #add tags
                if 'tags' in ssm_actions['config-groupname'] and ssm_actions['config-groupname']['tags'] == True:
                    seclog_status = add_tags_parameter(cfnssm, '/org/member/SecLog_config-groupname')

                if  do_update(ssm_actions, 'alarms-groupname') and seclog_status != Execution.FAIL:
                    result=update_ssm_parameter(cfnssm, '/org/member/SecLog_alarms-groupname', ssm_actions['alarms-groupname']['value'])
                    if result != Execution.OK:
                        will_update(stack_actions,'SECLZ-config-cloudtrail-SNS')  
                    if result != Execution.NO_ACTION:
                        seclog_status = result
                #add tags
                if 'tags' in ssm_actions['alarms-groupname'] and ssm_actions['alarms-groupname']['tags'] == True:
                    seclog_status = add_tags_parameter(cfnssm, '/org/member/SecLog_alarms-groupname')


            cfn = boto3.client('cloudformation',config=boto3_config)
            
            #KMS template
            if do_update(stack_actions, 'SECLZ-Cloudtrail-KMS') and seclog_status != Execution.FAIL:            
                result = update_stack(cfn, 'SECLZ-Cloudtrail-KMS', stacks, get_params(stack_actions,'SECLZ-Central-Buckets'))
                if result != Execution.NO_ACTION:
                    seclog_status = result
                elif result == Execution.OK :
                    print("SSM parameter /org/member/KMSCloudtrailKey_arn update", end="")
                    #response = update_ssm_parameter(cfnssm,'/org/member/KMSCloudtrailKey_arn', response['Parameter']['Value'])
                    add_tags_parameter(cfnssm, '/org/member/KMSCloudtrailKey_arn')
                    print(f" [{Status.OK.value}]")

            #logshipper lambdas S3 bucket
            if do_update(stack_actions, 'SECLZ-LogShipper-Lambdas-Bucket') and seclog_status != Execution.FAIL:
                result = update_stack(cfn, 'SECLZ-LogShipper-Lambdas-Bucket', stacks, get_params(stack_actions,'SECLZ-LogShipper-Lambdas-Bucket'))
                if result != Execution.NO_ACTION:
                    seclog_status = result
            
            #logshipper lambdas
            if do_update(stack_actions, 'SECLZ-LogShipper-Lambdas') and seclog_status != Execution.FAIL:
                
                #packaging lambdas
                now = datetime.now().strftime('%d%m%Y')
                cloudtrail_lambda=f'CloudtrailLogShipper-{now}.zip'
                with ZipFile(cloudtrail_lambda,'w') as zip:
                    zip.write('LAMBDAS/CloudtrailLogShipper.py','CloudtrailLogShipper.py')

                config_lambda=f'ConfigLogShipper-{now}.zip'
                with ZipFile(config_lambda,'w') as zip:
                    zip.write('LAMBDAS/ConfigLogShipper.py','ConfigLogShipper.py')

                #update CFT file
                if seclog_status != Execution.FAIL:
                    template = stacks['SECLZ-LogShipper-Lambdas']['Template']
                    print("Template SECLZ-LogShipper-Lambdas update ", end="")

                    try:
                        template = stacks['SECLZ-LogShipper-Lambdas']['Template']
                        
                        with open(template, "r") as f:
                            template_body=f.read()
                    
                        template_body = template_body.replace('##cloudtrailCodeURI##',cloudtrail_lambda).replace('##configCodeURI##',config_lambda)

                        template = f'EC-lz-logshipper-lambdas-{now}.yml'
                        with open(template, "w") as f:
                            f.write(template_body)
                    

                        print(f" [{Status.OK.value}]")
                    except FileNotFoundError as err:
                        print(f" [{Status.FAIL.value}]")
                        seclog_status = Execution.FAIL
                
                #package stack
                print("Template SECLZ-LogShipper-Lambdas package ", end="")
                bucket=f'lambda-artefacts-{account_id}'
                if seclog_status != Execution.FAIL:
                    prf=''
                    if has_profile:
                        prf = f'--profile {profile}'
                    with Spinner():
                        cmd = f"aws cloudformation package --template-file {template} {prf} --s3-bucket {bucket} --output-template-file EC-lz-logshipper-lambdas-{now}.packaged.yml"
                        cmdarg = shlex.split(cmd)
                        proc = subprocess.Popen(cmdarg,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
                        output, errors = proc.communicate()
                    
                    if len(errors) > 0:
                        print(f" failed. Readon {errors} [{Status.FAIL.value}]")
                        seclog_status = Execution.FAIL
                    else:
                        print(f" [{Status.OK.value}]")

                    os.remove(template)
                    os.remove(cloudtrail_lambda)
                    os.remove(config_lambda)
                    
                    #updating stack
                    if seclog_status != Execution.FAIL:
                        stacks['SECLZ-LogShipper-Lambdas']['Template'] = f'EC-lz-logshipper-lambdas-{now}.packaged.yml'
                        result = update_stack(cfn, 'SECLZ-LogShipper-Lambdas', stacks, get_params(stack_actions,'SECLZ-LogShipper-Lambdas'))
                        if result != Execution.NO_ACTION:
                            seclog_status = result
                        os.remove(f'EC-lz-logshipper-lambdas-{now}.packaged.yml')

            #central buckets
            if do_update(stack_actions, 'SECLZ-Central-Buckets') and seclog_status != Execution.FAIL:
                result = update_stack(cfn, 'SECLZ-Central-Buckets', stacks, get_params(stack_actions,'SECLZ-Central-Buckets'))
                if result != Execution.NO_ACTION:
                    seclog_status = result
            
            #password policy
            if do_update(stack_actions, 'SECLZ-Iam-Password-Policy') and seclog_status != Execution.FAIL:
                result = update_stack(cfn, 'SECLZ-Iam-Password-Policy', stacks, get_params(stack_actions,'SECLZ-Iam-Password-Policy'))
                if result != Execution.NO_ACTION:
                    seclog_status = result

            #cloudtrail SNS
            if do_update(stack_actions, 'SECLZ-config-cloudtrail-SNS') and seclog_status != Execution.FAIL:
                result = update_stack(cfn, 'SECLZ-config-cloudtrail-SNS', stacks, get_params(stack_actions,'SECLZ-config-cloudtrail-SNS'))
                if result != Execution.NO_ACTION:
                    seclog_status = result
            
            #guardduty detector
            if do_update(stack_actions, 'SECLZ-Guardduty-detector') and seclog_status != Execution.FAIL:
                result = update_stack(cfn, 'SECLZ-Guardduty-detector', stacks, get_params(stack_actions,'SECLZ-Guardduty-detector'))
                if result != Execution.NO_ACTION:
                    seclog_status = result
            
            #securityhub
            if do_update(stack_actions, 'SECLZ-SecurityHub') and seclog_status != Execution.FAIL:
                result = update_stack(cfn, 'SECLZ-SecurityHub', stacks, get_params(stack_actions,'SECLZ-SecurityHub'))
                if result != Execution.NO_ACTION:
                    seclog_status = result
            
            #cloudtrail notifications
            if do_update(stack_actions, 'SECLZ-Notifications-Cloudtrail') and seclog_status != Execution.FAIL:
                result = update_stack(cfn, 'SECLZ-Notifications-Cloudtrail', stacks, get_params(stack_actions,'SECLZ-Notifications-Cloudtrail'))
                if result != Execution.NO_ACTION:
                    seclog_status = result
            
            #cloudwatch logs
            if do_update(stack_actions, 'SECLZ-CloudwatchLogs-SecurityHub') and seclog_status != Execution.FAIL:
                result = update_stack(cfn, 'SECLZ-CloudwatchLogs-SecurityHub', stacks, get_params(stack_actions,'SECLZ-CloudwatchLogs-SecurityHub'))
                if result != Execution.NO_ACTION:
                    seclog_status = result
            
            #stackset Enable-Config-SecurityHub
            if do_update(stacksets_actions, 'SECLZ-Enable-Config-SecurityHub-Globally') and seclog_status != Execution.FAIL:            
                result = update_stackset(cfn, 'SECLZ-Enable-Config-SecurityHub-Globally', stacksets, get_params(stacksets_actions,'SECLZ-Enable-Config-SecurityHub-Globally'))
                if result != Execution.NO_ACTION:
                    seclog_status = result
           
            #stackset Enable-Guardduty-Globally
            if do_update(stacksets_actions, 'SECLZ-Enable-Guardduty-Globally') and seclog_status != Execution.FAIL:            
                result = update_stackset(cfn, 'SECLZ-Enable-Guardduty-Globally', stacksets, get_params(stacksets_actions,'SECLZ-Enable-Guardduty-Globally'))
                if result != Execution.NO_ACTION:
                    seclog_status = result

            #stackset add stack Enable-Config-SecurityHub
            if do_add_stack(stacksets_actions, 'SECLZ-Enable-Config-SecurityHub-Globally') and seclog_status != Execution.FAIL and len(linked_accounts) > 0:            
                result = add_stack_to_stackset(cfn, 'SECLZ-Enable-Config-SecurityHub-Globally', linked_accounts, stacksets_actions['deploy'])
                if result != Execution.NO_ACTION:
                    seclog_status = result
            
            #stackset  add stack Enable-Guardduty-Globally
            if do_add_stack(stacksets_actions, 'SECLZ-Enable-Guardduty-Globally') and seclog_status != Execution.FAIL and len(linked_accounts) > 0:            
                result = add_stack_to_stackset(cfn, 'SECLZ-Enable-Guardduty-Globally', linked_accounts, stacksets_actions['deploy'])
                if result != Execution.NO_ACTION:
                    seclog_status = result

             

            #securityhub actions
            if securityhub_actions:
                cfn = boto3.client('securityhub')
                print("Enable SecurityHub Multi-region findings", end="")
                toggle_securityhub_multiregion_findings(cfn, securityhub_actions['multiregion-findings']['enable'])
            

            #cis controls
            if not null_empty(manifest, 'cis') and seclog_status != Execution.FAIL:
                seclog_status = update_cis_controls(rules=cis_actions) 

            #update LZ version
            if version and seclog_status != Execution.FAIL:
                    cfn = boto3.client('ssm')
                    result=update_ssm_parameter(cfn, '/org/member/SLZVersion', version)
                    #add tags
                    result = add_tags_parameter(cfn, '/org/member/SLZVersion')
                    if result != Execution.NO_ACTION:
                        seclog_status = result 

            print("")
            print(f"SECLOG account {account_id} update ", end="")
            if seclog_status == Execution.FAIL:
                print(f"[{Status.FAIL.value}]")
            elif seclog_status == Execution.OK:
                print(f"[{Status.OK.value}]")
            else:
                print(f"[{Status.NO_ACTION.value}]")

        #update linked account stacks
        if seclog_status == Execution.FAIL and len(linked_accounts) > 0:
            print("Skipping linked accounts update")
        else:
            if len(all_regions['include']) > 0:
                linked_accounts = [d for d in all_regions['include'] if d != account_id]

            for linked in linked_accounts:
                if len(all_regions['exclude']) > 0 and linked in all_regions['exclude']:
                    print(f"Skipping linked account {linked}")
                else:
                    sts = boto3.client('sts')
                    assumedRole = sts.assume_role(
                        RoleArn=f"arn:aws:iam::{linked}:role/AWSCloudFormationStackSetExecutionRole",
                        RoleSessionName='CloudFormationSession'
                    )
                    credentials = assumedRole['Credentials']
                    accessKey = credentials['AccessKeyId']
                    secretAccessKey = credentials['SecretAccessKey']
                    sessionToken = credentials['SessionToken']

                    
                    
                    print("")
                    print(f"Updating linked account {linked}")
                    print("")
                    linked_status = Execution.NO_ACTION

                    if ssm_actions:
                        cfn = boto3.client('ssm',  
                            aws_access_key_id=accessKey,
                            aws_secret_access_key=secretAccessKey, 
                            aws_session_token=sessionToken)
                        #update SSM parameters
                        if do_update(ssm_actions, 'seclog-ou') and linked_status != Execution.FAIL:
                            result=update_ssm_parameter(cfn, '/org/member/SecLogOU', ssm_actions['seclog-ou']['value'])
                            if result != Execution.OK:
                                will_update(stack_actions,'SECLZ-config-cloudtrail-SNS')
                            if result != Execution.NO_ACTION:
                                linked_status = result     
                        #add tags
                        if 'tags' in ssm_actions['seclog-ou'] and ssm_actions['seclog-ou']['tags'] == True:
                            linked_status = add_tags_parameter(cfn, '/org/member/SecLogOU')

                        if do_update(ssm_actions, 'notification-mail') and linked_status != Execution.FAIL:
                            result=update_ssm_parameter(cfn, '/org/member/SecLog_notification-mail', ssm_actions['notification-mail']['value'])
                            if result != Execution.OK:
                                will_update(stack_actions,'SECLZ-config-cloudtrail-SNS')
                            if result != Execution.NO_ACTION:
                                linked_status = result     
                        #add tags
                        if 'tags' in ssm_actions['notification-mail'] and ssm_actions['notification-mail']['tags'] == True:
                            linked_status = add_tags_parameter(cfn, '/org/member/SecLog_notification-mail')


                        if do_update(ssm_actions, 'cloudtrail-groupname') and linked_status != Execution.FAIL:
                            result=update_ssm_parameter(cfn, '/org/member/SecLog_cloudtrail-groupname', ssm_actions['cloudtrail-groupname']['value'])
                            if result != Execution.OK:
                                will_update(stack_actions,'SECLZ-config-cloudtrail-SNS')
                                will_update(stack_actions,'SECLZ-LogShipper-Lambdas')
                                will_update(stack_actions,'SECLZ-Notifications-Cloudtrail')
                            if result != Execution.NO_ACTION:
                                linked_status = result  
                        #add tags
                        if 'tags' in ssm_actions['cloudtrail-groupname'] and ssm_actions['cloudtrail-groupname']['tags'] == True:
                            linked_status = add_tags_parameter(cfn, '/org/member/SecLog_cloudtrail-groupname')


                        if  do_update(ssm_actions, 'insight-groupname') and linked_status != Execution.FAIL:
                            result=update_ssm_parameter(cfn, '/org/member/SecLog_insight-groupname', ssm_actions['insight-groupname']['value'])
                            if result != Execution.OK:
                                will_update(stack_actions,'SECLZ-config-cloudtrail-SNS')
                                will_update(stack_actions,'SECLZ-LogShipper-Lambdas')
                            if result != Execution.NO_ACTION:
                                linked_status = result  
                        #add tags
                        if 'tags' in ssm_actions['insight-groupname'] and ssm_actions['insight-groupname']['tags'] == True:
                            linked_status = add_tags_parameter(cfn, '/org/member/SecLog_insight-groupname')


                        if  do_update(ssm_actions, 'guardduty-groupname') and linked_status != Execution.FAIL:
                            for region in all_regions:
                                cfn = boto3.client('ssm', aws_access_key_id=accessKey,
                                    aws_secret_access_key=secretAccessKey, 
                                    aws_session_token=sessionToken,
                                    region_name=region)
                                result=update_ssm_parameter(cfn, '/org/member/SecLog_guardduty-groupname', ssm_actions['guardduty-groupname']['value'])
                                if result != Execution.OK:
                                    will_update(stack_actions,'SECLZ-Guardduty-detector')
                                if result != Execution.NO_ACTION:
                                    linked_status = result  
                            cfn = boto3.client('ssm',  
                                aws_access_key_id=accessKey,
                                aws_secret_access_key=secretAccessKey, 
                                aws_session_token=sessionToken)
                        #add tags
                        if 'tags' in ssm_actions['guardduty-groupname'] and ssm_actions['guardduty-groupname']['tags'] == True:
                            for region in all_regions:
                                cfn = boto3.client('ssm', aws_access_key_id=accessKey,
                                    aws_secret_access_key=secretAccessKey, 
                                    aws_session_token=sessionToken,
                                    region_name=region)
                                linked_status = add_tags_parameter(cfn, '/org/member/SecLog_guardduty-groupname')
                            cfn = boto3.client('ssm',  
                                aws_access_key_id=accessKey,
                                aws_secret_access_key=secretAccessKey, 
                                aws_session_token=sessionToken)


                        if  do_update(ssm_actions, 'securityhub-groupname') and linked_status != Execution.FAIL:
                            result=update_ssm_parameter(cfn, '/org/member/SecLog_securityhub-groupname', ssm_actions['securityhub-groupname']['value'])
                            if result != Execution.OK:
                                will_update(stack_actions,'SECLZ-CloudwatchLogs-SecurityHub')                            
                            if result != Execution.NO_ACTION:
                                linked_status = result  
                        #add tags
                        if 'tags' in ssm_actions['securityhub-groupname'] and ssm_actions['securityhub-groupname']['tags'] == True:
                            linked_status = add_tags_parameter(cfn, '/org/member/SecLog_securityhub-groupname')


                        if  do_update(ssm_actions, 'config-groupname') and linked_status != Execution.FAIL:
                            result=update_ssm_parameter(cfn, '/org/member/SecLog_config-groupname', ssm_actions['config-groupname']['value'])
                            if result != Execution.OK:
                                will_update(stack_actions,'SECLZ-config-cloudtrail-SNS')                            
                                will_update(stack_actions,'SECLZ-LogShipper-Lambdas')       
                            if result != Execution.NO_ACTION:
                                linked_status = result
                        #add tags
                        if 'tags' in ssm_actions['config-groupname'] and ssm_actions['config-groupname']['tags'] == True:
                            linked_status = add_tags_parameter(cfn, '/org/member/SecLog_config-groupname')


                        if  do_update(ssm_actions, 'alarms-groupname') and linked_status != Execution.FAIL:
                            result=update_ssm_parameter(cfn, '/org/member/SecLog_alarms-groupname', ssm_actions['alarms-groupname']['value'])
                            if result != Execution.OK:
                                will_update(stack_actions,'SECLZ-config-cloudtrail-SNS')  
                            if result != Execution.NO_ACTION:
                                linked_status = result
                        #add tags
                        if 'tags' in ssm_actions['alarms-groupname'] and ssm_actions['alarms-groupname']['tags'] == True:
                            linked_status = add_tags_parameter(cfn, '/org/member/SecLog_alarms-groupname')



                    cfn = boto3.client('cloudformation',  
                        aws_access_key_id=accessKey,
                        aws_secret_access_key=secretAccessKey, 
                        aws_session_token=sessionToken)

                    #password policy
                    if do_update(stack_actions, 'SECLZ-Iam-Password-Policy') and linked_status != Execution.FAIL:
                        result = update_stack(cfn, 'SECLZ-Iam-Password-Policy', stacks, get_params(stack_actions,'SECLZ-Iam-Password-Policy'))
                        if result != Execution.NO_ACTION:
                            linked_status = result
                            
                    #cloudtrail SNS
                    if do_update(stack_actions, 'SECLZ-config-cloudtrail-SNS') and linked_status != Execution.FAIL:
                        result = update_stack(cfn, 'SECLZ-config-cloudtrail-SNS', stacks, get_params(stack_actions,'SECLZ-config-cloudtrail-SNS'))
                        if result != Execution.NO_ACTION:
                            linked_status = result
                            
                    #securityhub
                    if do_update(stack_actions, 'SECLZ-SecurityHub') and linked_status != Execution.FAIL:
                        result = update_stack(cfn, 'SECLZ-SecurityHub', stacks, get_params(stack_actions,'SECLZ-SecurityHub'))
                        if result != Execution.NO_ACTION:
                            linked_status = result
                            
                    #cloudtrail notification
                    if do_update(stack_actions, 'SECLZ-Notifications-Cloudtrail') and linked_status != Execution.FAIL:
                        result = update_stack(cfn, 'SECLZ-Notifications-Cloudtrail', stacks, get_params(stack_actions,'SECLZ-Notifications-Cloudtrail'))
                        if result != Execution.NO_ACTION:
                            linked_status = result
                        
                    #local SNS topic
                    if do_update(stack_actions, 'SECLZ-local-SNS-topic') and linked_status != Execution.FAIL:
                        result = update_stack(cfn, 'SECLZ-local-SNS-topic', stacks, get_params(stack_actions,'SECLZ-local-SNS-topic'))
                        if result != Execution.NO_ACTION:
                            linked_status = result

                    #cis controls
                    if not null_empty(manifest, 'cis') and linked_status != Execution.FAIL:
                        linked_status = update_cis_controls(
                            rules=cis_actions, 
                            accessKey=accessKey,
                            secretAccessKey=secretAccessKey, 
                            sessionToken=sessionToken
                        ) 

                    #update LZ version
                    if version and linked_status != Execution.FAIL:
                        cfn = boto3.client('ssm',  
                            aws_access_key_id=accessKey,
                            aws_secret_access_key=secretAccessKey, 
                            aws_session_token=sessionToken)
                        result=update_ssm_parameter(cfn, '/org/member/SLZVersion', version)
                        result=add_tags_parameter(cfn, '/org/member/SLZVersion')
                        if result != Execution.NO_ACTION:
                            linked_status = result 

                    print("")
                    print(f"Linked account {linked} update ", end="")
                    if linked_status == Execution.FAIL:
                        print(f"[{Status.FAIL.value}]")
                    elif linked_status == Execution.OK:
                        print(f"[{Status.OK.value}]")
                    else:
                        print(f"[{Status.NO_ACTION.value}]")
                    print("")
        
        
                

    print("")
    print(f"####### AWS Landing Zone update script finished. Executed in {time.time() - start_time} seconds")
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
                print(f"Access denied getting account id [{Status.FAIL.value}]")
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

def do_update(dict, key):
    """
    Function that checks if the a key exists in the dict and the value is not empty
        :return: true or false
    """
    if not null_empty(dict, key) and 'update' in dict[key] and dict[key]['update'] == True:
        return True
    else: return False

def do_add_stack(dict, key):
    """
    Function that checks if the a key exists in the dict and the value is not empty
        :return: true or false
    """
    if not null_empty(dict, key) and 'deploy' in dict[key] and dict[key]['deploy']:
        return True
    else: return False

def will_update(dict, key):
    """
    Function that sets a stack to be updated
    """
    if not null_empty(dict, key) and 'update' in dict[key] and dict[key]['update'] == False:
        dict[key]['update'] = True
    
def merge_tags(list1, list2):
    """
    Function to merge two list of tags
    """
    res = {}
    output = []

    for item in list1:
        res[item['Key']] = item['Value']

    for item in list2:
        res[item['Key']] = item['Value']
       
    
    for item in res:
        output.append({"Key": item, "Value": res[item]})

    return output

def merge_params(list1, list2):
    """
    Function to merge two list of params
    """
    res = {}
    output = []

    for item in list1:
        res[item['ParameterKey']] = item['ParameterValue'] 

    for item in list2:
        res[item['ParameterKey']] = item['ParameterValue']
       
    
    for item in res:
        output.append({"ParameterKey": item, "ParameterValue": res[item]})

    return output

def get_params(actions, key):
    return actions[key]['params'] if key in actions and 'params' in actions[key] else []

def add_tags_parameter(client,parameter,region=None):

    global tags

    if region:
        print(f"Adding tags to SSM parameter {parameter} [{region}]", end="")
    else 
        print(f"Adding tags to SSM parameter {parameter} ", end="")
    try:
        response = client.get_parameter(Name=parameter)
    except Exception as err:
        print(f"\033[2K\033[1GSSM parameter {parameter} tag update failed, reason {err.response['Error']['Message']} [{Status.FAIL.value}]")
        return Execution.FAIL
    try:
        response=client.add_tags_to_resource(
        ResourceType='Parameter',
        ResourceId=parameter,
        Tags=tags)

        print(f"\033[2K\033[1GAdding tags to SSM parameter {parameter} [{Status.OK.value}]")
        return Execution.OK
    
    except Exception as err:
        print(f"\033[2K\033[1GSSM parameter {parameter} tag update failed failed, reason {err.response['Error']['Message']} [{Status.FAIL.value}]")
        return Execution.FAIL
    

def update_ssm_parameter(client, parameter, value, region=None):
    """
    Function used to update an SSM parameter if the value is different
        :paremter:      parameter name
        :value:         the value to be updated
        :return:        execution status
    """
    exists = True
    if region:
        print(f"SSM parameter {parameter} update [{region}]", end="")
    else:
        print(f"SSM parameter {parameter} update ", end="")

    try:
        response = client.get_parameter(Name=parameter)
    except Exception as err:
        print(f"\033[2K\033[1GSSM parameter {parameter} does not exist. Creating...", end="")
        exists=False
    try:
        if not exists or ('Value' in response['Parameter'] and value != response['Parameter']['Value']):
            response = client.put_parameter(
                Name=parameter,
                Value=value,
                Type='String',
                Overwrite=True|False)
            if response['Version']:
                print(f"\033[2K\033[1GSSM parameter {parameter} update [{Status.OK.value}]")
                return Execution.OK
        
    
    except Exception as err:
        print(f"\033[2K\033[1GSSM parameter {parameter} update failed. Reason {err.response['Error']['Message']} [{Status.FAIL.value}]")
        return Execution.FAIL
    
    print(f"[{Status.NO_ACTION.value}]")
    return Execution.NO_ACTION

def get_controls(client, region, sub_arn, NextToken=None):
    
    controls = client.describe_standards_controls(
        NextToken=NextToken,
        StandardsSubscriptionArn=sub_arn) if NextToken else client.describe_standards_controls(
        StandardsSubscriptionArn=sub_arn)
    if ('NextToken' in controls):
        return controls['Controls'] + get_controls(client, region, sub_arn, NextToken=controls['NextToken'])
    else:
        return controls['Controls']

def toggle_securityhub_multiregion_findings(client, enable=True):
    
    response0 = client.list_finding_aggregators()

    if len(response0['FindingAggregators']) == 0 and enable:
        try:
            response = client.create_finding_aggregator(
                RegionLinkingMode='ALL_REGIONS'
            )
            print(f" [{Status.OK.value}]")
            return Execution.OK
        except Exception as err:
            print(f"failed. Reason {err.response['Error']['Message']} [{Status.FAIL.value}]")
            return Execution.FAIL
    elif len(response0['FindingAggregators']) == 1 and enable == False:
        try:
            response = client.delete_finding_aggregator(
                FindingAggregatorArn=response0['FindingAggregators'][0]['FindingAggregatorArn']
            )
            print(f" [{Status.OK.value}]")
            return Execution.OK
        except Exception as err:
            print(f"failed. Reason {err.response['Error']['Message']} [{Status.FAIL.value}]")
            return Execution.FAIL
    else: 
        print(f" [{Status.NO_ACTION.value}]")
        return Execution.NO_ACTION


def update_cis_controls(rules,
    accessKey=None,
    secretAccessKey=None, 
    sessionToken=None): 
    
    global all_regions
   
    print(f"CIS controls update ", end="")
    try:
        with Spinner():
            #enable all rules
          
            regions = [d for d in all_regions if d  != 'ap-northeast-3']
            
            failed_regions = []
            for region in regions:
                try:
                    client = boto3.client('securityhub',aws_access_key_id=accessKey,
                        aws_secret_access_key=secretAccessKey, 
                        aws_session_token=sessionToken,
                        region_name=region
                    )



                    client.batch_enable_standards(
                        StandardsSubscriptionRequests=[
                            {
                                'StandardsArn': "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0",
                                
                            },
                        ]
                    )

                    client.batch_enable_standards(
                        StandardsSubscriptionRequests=[
                            {
                                'StandardsArn': f"arn:aws:securityhub:{region}::standards/aws-foundational-security-best-practices/v/1.0.0",
                                
                            },
                        ]
                    )
                except Exception as err:
                        
                        failed_regions.append(region)

            if len(failed_regions) > 0:
                print(f"failed. Reason Account is not subscribed to AWS Security Hub on the following regions {failed_regions} [{Status.FAIL.value}]")
                return Execution.FAIL

            enabled_rules = { key:value for (key,value) in rules.items() if value['disabled'] == False}
            disabled_rules = { key:value for (key,value) in rules.items() if value['disabled'] == True}

            #enabled rules
            for rule,value in enabled_rules.items():
                regions = value['regions'] if 'regions' in value and len(value['regions']) > 0  else all_regions
                if 'exclusions' in value:
                    regions = [d for d in regions if d not in value['exclusions']]
              
                for region in regions:
                
                    client = boto3.client('securityhub',aws_access_key_id=accessKey,
                        aws_secret_access_key=secretAccessKey, 
                        aws_session_token=sessionToken,
                        region_name=region
                    )
                
                    stds = client.get_enabled_standards()
                    
                    for std in stds['StandardsSubscriptions']:
                        controls = []
                        available_controls = get_controls(client, region, std['StandardsSubscriptionArn'])
                        if 'checks' not in value:
                            controls = [d for d in available_controls if rule in d['StandardsControlArn'] ]
                        else:
                            for check in value['checks']:
                                controls.extend([d for d in available_controls if f"{rule}/{check}" in d['StandardsControlArn'] ])

                        for control in controls:
                            
                            try:
                                client.update_standards_control(
                                        StandardsControlArn=control['StandardsControlArn'],
                                        ControlStatus='ENABLED'
                                    ) 
                            except ClientError as err:
                                if err.response['Error']['Code'] == 'ThrottlingException':
                                    continue
                   
            #disabled rules
            for rule,value in disabled_rules.items():
                regions = value['regions'] if 'regions' in value and len(value['regions']) > 0  else all_regions
                if 'exclusions' in value:
                    regions = [d for d in regions if d not in value['exclusions']]
               
                for region in regions:
                
                    client = boto3.client('securityhub',aws_access_key_id=accessKey,
                        aws_secret_access_key=secretAccessKey, 
                        aws_session_token=sessionToken,
                        region_name=region
                    )
                
                    stds = client.get_enabled_standards()
                    
                    for std in stds['StandardsSubscriptions']:
                        available_controls = get_controls(client, region, std['StandardsSubscriptionArn'])
                        controls = []
                        if 'checks' not in value:
                            controls = [d for d in available_controls if rule in d['StandardsControlArn'] ]
                        else:
                            for check in value['checks']:
                                controls.extend([d for d in available_controls if f"{rule}/{check}" in d['StandardsControlArn'] ])

                        for control in controls:
                            
                            try:
                                response=client.update_standards_control(
                                        StandardsControlArn=control['StandardsControlArn'],
                                        ControlStatus='DISABLED',
                                        DisabledReason='Managed by Cloud Broker Team' if 'disabled-reason' not in value else value['disabled-reason'],
                                    ) 
                                
                            except ClientError as err:
                                if err.response['Error']['Code'] == 'ThrottlingException':
                                    continue
                
        print(f" [{Status.OK.value}]")
        return Execution.OK
    except Exception as err:
        print(f"failed. Reason {err.response['Error']['Message']} [{Status.FAIL.value}]")
        return Execution.FAIL


def validate_params(params, template):

    new_params = []
    dict_template = load_yaml(template)
    return [elem for elem in params if elem['ParameterKey'] in dict_template['Parameters']]
   
def update_stack(client, stack, templates, params=[]):
    """
    Function that updates a stack defined in the parameters
        :stack:         The stack name
        :template_data: dict holding CFT details
        :params:        parameters to be passed to the stack
        :return:        True or False
    """
    global tags
    template = templates[stack]['Template']
    capabilities=[]
    
    print(f"Stack {stack} update ", end="")

    try:
        with open(template, "r") as f:
            template_body=f.read()
        response = client.describe_stacks(StackName=stack)
    except FileNotFoundError as err:
        print(f"\033[2K\033[Stack template file not found : {err.strerror} [{Status.FAIL.value}]")
        return Execution.FAIL
    except ClientError as err:
        print(f"\033[2K\033[1GStack {stack} update failed. Reason : {err.response['Error']['Message']} [{Status.FAIL.value}]")
        return Execution.FAIL
    
    if 'Parameters:' in template_body:
        
        if not null_empty(templates[stack], 'Params'):
            try:
                with open(templates[stack]['Params']) as f:
                    params = json.load(f)
            except FileNotFoundError as err:
                print(f"\033[2K\033[1GParameter file not found : {err.strerror} [{Status.FAIL.value}]")
                Execution.FAIL
            except json.decoder.JSONDecodeError as err:
                print(f"\033[2K\033[1GParameter file problem : {err.strerror} [{Status.FAIL.value}]")
                Execution.FAIL
        elif not null_empty(response['Stacks'][0], 'Parameters'):
            params = merge_params(response['Stacks'][0]['Parameters'], params)
        
        

    if not null_empty(response['Stacks'][0], 'Capabilities'):
        capabilities = response['Stacks'][0]['Capabilities']

    if not null_empty(response['Stacks'][0], 'Tags'):
        apply_tags =  merge_tags(response['Stacks'][0]['Tags'], tags)

   
    if response['Stacks'][0]['StackStatus'] not in ('CREATE_COMPLETE', 'UPDATE_COMPLETE','UPDATE_ROLLBACK_COMPLETE'):
        print(f"Cannot update stack {stack}. Current status is : {response['Stacks'][0]['StackStatus']} [{Status.FAIL.value}]")
        return Execution.FAIL
        
    print("in progress ", end="")
    
    with Spinner():
        try:
            
            client.update_stack(
                StackName=stack, 
                TemplateBody=template_body, 
                Parameters=validate_params(params, template_body), 
                Capabilities=capabilities, 
                Tags=apply_tags)
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
                        return Execution.FAIL
                except ClientError as err:
                    if err.response['Error']['Code'] == 'ThrottlingException':
                        continue
                    else:
                        raise err
                
               
            return Execution.OK
        
        except ClientError as err:
            if err.response['Error']['Code'] == 'AmazonCloudFormationException':
                print(f"\033[2K\033[1GStack {stack} not found : {err.response['Error']['Message']} [{Status.FAIL.value}]")
            elif err.response['Error']['Code'] == 'ValidationError' and err.response['Error']['Message'] == 'No updates are to be performed.':
                print(f"\033[2K\033[1GStack {stack} update [{Status.NO_ACTION.value}]")
                return Execution.NO_ACTION
            else:
                print(f"\033[2K\033[1GStack {stack} update failed. Reason : {err.response['Error']['Message']} [{Status.FAIL.value}]")
        
        return Execution.FAIL

def add_stack_to_stackset(client, stackset, accounts, regions):
    """
    Function that updates a stackset defined in the parameters
        :stackset:         The stackset name
        :template_data: dict holding CFT details
        :params:        parameters to be passed to the stackset
        :return:        True or False
    """
    

    print(f"Adding stacks to StackSet {stackset} ", end="")
    response = client.describe_stack_set(StackSetName=stackset)
   
    if response['StackSet']['Status'] not in ('ACTIVE'):
        print(f"Cannot update stackset {stackset} instances. Current stackset status is : {response['StackSet']['Status']} [{Status.FAIL.value}]")
        return Execution.FAIL

    accounts.append(get_account_id())

    
        
    print("in progress ", end="")
    with Spinner():
        try:
            operationPreferences={
                'RegionConcurrencyType': 'PARALLEL',
                'FailureToleranceCount': 9,
                'MaxConcurrentCount': 10,
            }
            client.create_stack_instances(
                StackSetName=stackset, 
                Regions=regions, 
                Accounts=accounts,
                OperationPreferences=operationPreferences
                )
            updated=False
        
            while updated == False:
                try:
                    time.sleep(1)
                    response = client.describe_stack_set(StackSetName=stackset)
                    if 'ACTIVE' in response['StackSet']['Status'] :
                        print(f"\033[2K\033[1GStackSet {stackset} update [{Status.OK.value}]")
                        updated=True
                        break
                except ClientError as err:
                    if err.response['Error']['Code'] == 'ThrottlingException':
                        continue
                    else:
                        raise err
                
                
            return Execution.OK
        
        except ClientError as err:
            if err.response['Error']['Code'] == 'AmazonCloudFormationException':
                print(f"\033[2K\033[1GStackSet {stackset} not found : {err.response['Error']['Message']} [{Status.FAIL.value}]")
            elif err.response['Error']['Code'] == 'ValidationError' and err.response['Error']['Message'] == 'No updates are to be performed.':
                print(f"\033[2K\033[1GStackSet {stackset} update [{Status.NO_ACTION.value}]")
                return Execution.NO_ACTION
            else:
                print(f"\033[2K\033[1GStackSet {stackset} update failed. Reason : {err.response['Error']['Message']} [{Status.FAIL.value}]")
        
        return Execution.FAIL

def update_stackset(client, stackset, templates, params=[]):
    """
    Function that updates a stackset defined in the parameters
        :stackset:         The stackset name
        :template_data: dict holding CFT details
        :params:        parameters to be passed to the stackset
        :return:        True or False
    """
    global all_regions_except_ireland
    global tags
    template = templates[stackset]['Template']
    capabilities=[]

    print(f"StackSet {stackset} update ", end="")

    try:
        with open(template, "r") as f:
            template_body=f.read()
        response = client.describe_stack_set(StackSetName=stackset)
    except FileNotFoundError as err:
        print(f"\033[2K\033[StackSet template file not found : {err.strerror} [{Status.FAIL.value}]")
        return Execution.FAIL
    except ClientError as err:
        print(f"\033[2K\033[1GStackSet {stackset} update failed. Reason : {err.response['Error']['Message']} [{Status.FAIL.value}]")
        return Execution.FAIL
    
    
    if 'Parameters:' in template_body:
        
        if not null_empty(templates[stackset], 'Params'):
            try:
                with open(templates[stackset]['Params']) as f:
                    params = json.load(f)
            except FileNotFoundError as err:
                print(f"\033[2K\033[1GParameter file not found : {err.strerror} [{Status.FAIL.value}]")
                Execution.FAIL
            except json.decoder.JSONDecodeError as err:
                print(f"\033[2K\033[1GParameter file problem : {err.strerror} [{Status.FAIL.value}]")
                Execution.FAIL
        elif not null_empty(response['StackSet'], 'Parameters'):
            params = merge_params(response['StackSet']['Parameters'], params)        

    if not null_empty(response['StackSet'], 'Capabilities'):
        capabilities = response['StackSet']['Capabilities']
    
    if not null_empty(response['StackSet'], 'Tags'):
        apply_tags =  merge_tags(response['StackSet']['Tags'], tags)


    if response['StackSet']['Status'] not in ('ACTIVE'):
        print(f"Cannot update stackset {stackset}. Current status is : {response['StackSet']['Status']} [{Status.FAIL.value}]")
        return Execution.FAIL
        
    print("in progress ", end="")
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
                Parameters=validate_params(params, template_body), 
                Capabilities=capabilities,
                OperationPreferences=operationPreferences,
                Tags=apply_tags
                )
            updated=False
        
            while updated == False:
                try:
                    time.sleep(1)
                    response = client.describe_stack_set(StackSetName=stackset)
                    if 'ACTIVE' in response['StackSet']['Status'] :
                        print(f"\033[2K\033[1GStackSet {stackset} update [{Status.OK.value}]")
                        updated=True
                        break
                except ClientError as err:
                    if err.response['Error']['Code'] == 'ThrottlingException':
                        continue
                    else:
                        raise err
                
                
            return Execution.OK
        
        except ClientError as err:
            if err.response['Error']['Code'] == 'AmazonCloudFormationException':
                print(f"\033[2K\033[1GStackSet {stackset} not found : {err.response['Error']['Message']} [{Status.FAIL.value}]")
            elif err.response['Error']['Code'] == 'ValidationError' and err.response['Error']['Message'] == 'No updates are to be performed.':
                print(f"\033[2K\033[1GStackSet {stackset} update [{Status.NO_ACTION.value}]")
                return Execution.NO_ACTION
            else:
                print(f"\033[2K\033[1GStackSet {stackset} update failed. Reason : {err.response['Error']['Message']} [{Status.FAIL.value}]")
        
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


