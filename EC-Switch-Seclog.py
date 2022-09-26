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
import threading
import cursor
import yaml
from cfn_tools import load_yaml, dump_yaml

from datetime import datetime
from enum import Enum
from colorama import Fore, Back, Style
from botocore.exceptions import BotoCoreError, ClientError, ProfileNotFound
from botocore.config import Config


all_regions = ["ap-northeast-1","ap-northeast-2","ap-northeast-3","ap-south-1","ap-southeast-1","ap-southeast-2","ca-central-1","eu-central-1","eu-north-1","eu-west-1", "eu-west-2","eu-west-3","sa-east-1","us-east-1","us-east-2","us-west-1","us-west-2"]

def main(argv):
    
    global tags
    start_time = time.time()
  
    seclog_profile = ''
    account_profile = ''

    verbosity = logging.ERROR
   
    
    
    boto3_config = Config(
        retries = dict(
            max_attempts = 10
        )
    )

    
    sys.stdout = Unbuffered(sys.stdout)

    try:
        opts, args = getopt.getopt(argv,"hva:s:",["account", "seclog", "verbose"])
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
        elif opt in ("-a", "--account"):
            if (arg == ''):
                print(f"Account profile has not been provided. [{Status.FAIL.value}]")
                print("Exiting...")
                sys.exit(1)
            else:
                account_profile = arg
        
        elif opt in ("-s", "--seclog"):
            if (arg == ''):
                print(f"Target SECLOG profile has not been provided. [{Status.FAIL.value}]")
                print("Exiting...")
                sys.exit(1)
            else
                seclog_profile = arg
           
        elif opt in ("-v", "--verbose"):
            verbosity = logging.DEBUG
    
    logging.basicConfig(level=verbosity)

    # Reconfigure Client account
    boto3.setup_default_session(profile_name=account_profile)

    # guardduty
    cfn = boto3.client('guardduty')

    detector_response = client.list_detectors()
    for detector in detector_response['DetectorIds']

        response = client.disassociate_from_master_account(
            DetectorId=detector
        )


    print("")
    print(f"####### AWS Landing Zone switch SECLOG script finished. Executed in {time.time() - start_time} seconds")
    print("#######")
    print("")


if __name__ == "__main__":
    main(sys.argv[1:])


