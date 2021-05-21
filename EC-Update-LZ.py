#!/usr/bin/python

import sys, getopt
import subprocess, pkg_resources
import os
import logging
import boto3
import json

from botocore.exceptions import ClientError


account_id = ''

def main(argv):

    manifest = ''
    orgprofile = ''
    seclogprofile = ''
    verbosity = logging.ERROR

    try:
        opts, args = getopt.getopt(argv,"hvm:s:o:",["manifest", "seclog", "org", "verbose"])
    except getopt.GetoptError:
        usage()
        sys.exit(2)
    
    # Parsing script parameters
    for opt, arg in opts:
        if opt == '-h':
            usage()
            sys.exit()
        elif opt in ("-m", "--manifest"):
            manifest = arg
        elif opt in ("-o", "--org"):
            orgprofile = arg
        elif opt in ("-s", "--seclog"):
            print("Using AWS profile : {}".format(arg))
            boto3.setup_default_session(profile_name=arg)
        elif opt in ("-v", "--verbose"):
            verbosity = logging.DEBUG
    
    logging.basicConfig(level=verbosity)
    

    print("Checking account...")
    if (is_seclog() == False):
        print(f"\033[F\033[{20}G Not a SECLOG account. Exiting.")
        sys.exit(1)
    
    print(f"\033[F\033[{20}G SECLOG account identified.")    
    
    

def usage():
    """
    This function prints the usage
    """
    print('Usage:')
    print('python EC-Update-LZ.py -m <manifest> -s <seclogprofile> -o <orgprofile>')

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

def update_seclog_KMS_key_for_cloudtrail_encryption():
    """
    Function that installs the KMS key for cloudtrail stack
        :return: true or false
    """
    stack_name='SECLZ-Cloudtrail-KMS'
    template='./EC/EC-lz-Cloudtrail-kms-key.yml'
    updated=False
    
    try:
        f=open(template, "r")
        template_body=f.read()
        print("Updating stack : {}".format(stack_name))
        client = boto3.client('cloudformation')
        stack_id = client.update_stack(StackName=stack_name, TemplateBody=template_body)
        
        while updated == False:
            response = client.describe_stacks(StackName=stack_name)
            if response['Stacks'][0]['StackStatus'] == 'UPDATE_COMPLETE':
                print("\rUpdating stack : {} complete".format(stack_name))
                updated=True
                break
            elif response['Stacks'][0]['StackStatus'] == 'ERROR':
                print("\rUpdating stack : {} failed".format(stack_name))
                return False
        
        
    except FileNotFoundError as err:
        logging.error("Template not found : {}".format(err.strerror))
            
    

if __name__ == "__main__":
    main(sys.argv[1:])