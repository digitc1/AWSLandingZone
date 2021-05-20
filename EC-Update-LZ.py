#!/usr/bin/python

import sys, getopt
import subprocess, pkg_resources
import os
import logging
import boto3
import json

logging.basicConfig(level=logging.DEBUG)

account_id = ''

def main(argv):

    manifest = ''
    orgprofile = ''
    seclogprofile = ''

    try:
        opts, args = getopt.getopt(argv,"hms:o:",["manifest=", "seclog=", "org="])
    except getopt.GetoptError:
        display_help()
        sys.exit(2)
    
    for opt, arg in opts:
        if opt == '-h':
            display_help()
            sys.exit()
        elif opt in ("-m", "--manifest"):
            manifest = arg
        elif opt in ("-o", "--org"):
            orgprofile = arg
        elif opt in ("-s", "--seclog"):
            seclogprofile = arg
    
    print('Manifest "', manifest)

    if seclogprofile != '':
        print('SECLOG Profile "', seclogprofile)
        boto3.setup_default_session(profile_name=seclogprofile)
        
    if orgprofile != '':
        print('Organisation Profile "', orgprofile)
        
        
        
    linked_accounts = get_linked_accounts()

def display_help():
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
        account_id = data['Account']
        
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

    

if __name__ == "__main__":
    main(sys.argv[1:])