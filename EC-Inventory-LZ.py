
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

from datetime import datetime
from enum import Enum
from colorama import Fore, Back, Style
from botocore.exceptions import BotoCoreError, ClientError, ProfileNotFound
from botocore.config import Config

def exit_handler(signum, frame):
    print("Exiting...")
    sys.exit(1)


signal.signal(signal.SIGINT, exit_handler)



def main(argv):
    
    verbosity = logging.ERROR
    start_time = time.time()

    
    try:
        opts, args = getopt.getopt(argv,"hva:",["account" "verbose"])
    except getopt.GetoptError:
        usage()
        sys.exit(2)
    
    print("#######")
    print("####### AWS Landing Zone Inventory Generator script")
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
        
        
    
    logging.basicConfig(level=verbosity)


def usage():
    """
    This function prints the script usage
    """
    print('Usage:')
    print('')
    print('python EC-Inventory-LZ.py -a <account profile> [-v]')
    print('')
    print('   Provide ')
    print('   -a --account         : The AWS profile of the linked account to be switched')
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


