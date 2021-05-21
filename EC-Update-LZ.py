#!/usr/bin/python

import sys, getopt
import subprocess, pkg_resources
import os
import logging
import boto3
import json



account_id = ''

def main(argv):

    manifest = ''
    orgprofile = ''
    seclogprofile = ''
    verbosity = logging.ERROR

    try:
        opts, args = getopt.getopt(argv,"hms:ov:",["manifest", "seclog", "org", "verbose"])
    except getopt.GetoptError:
        usage()
        sys.exit(2)
    
    for opt, arg in opts:
        if opt == '-h':
            usage()
            sys.exit()
        elif opt in ("-m", "--manifest"):
            manifest = arg
        elif opt in ("-o", "--org"):
            orgprofile = arg
        elif opt in ("-s", "--seclog"):
            seclogprofile = arg
        elif opt in ("-v", "--verbose"):
            verbosity = logging.DEBUG
    
    logging.basicConfig(level=verbosity)
    

    if seclogprofile != '':
        print('SECLOG Profile "', seclogprofile)
        boto3.setup_default_session(profile_name=seclogprofile)
   
    
    print("Checking account...")
    if (is_seclog() == False):
        print(f"\033[F\033[{20}G Not a SECLOG account. Exiting.")
        sys.exit(1)
    
    print(f"\033[F\033[{20}G SECLOG account identified.")    
    linked_accounts = get_linked_accounts()

def usage():
    """
    This function prints the usage
    """
    print('python EC-Update-LZ.py -m <manifest> -s <seclogprofile> -o <orgprofile>')

def get_account_id(force = False):
    """
    This function gets te id of the account defined in the profile
        :param force: flag to force the retrieval of the account ID 
        :eturn: a string with the account id 
    """
    global account_id

    if account_id == '' or force == True:
        client = boto3.client('sts')
        data = client.get_caller_identity()
        seclog_account_id = data['Account']
        
    logging.debug("Account Id : {}".format(account_id))
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
    if not 'Value' in response or seclog_account_id != response['Value']:
        return False
    
    return True

    

if __name__ == "__main__":
    main(sys.argv[1:])