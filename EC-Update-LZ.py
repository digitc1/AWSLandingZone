#!/usr/bin/python

import sys, getopt
import subprocess, pkg_resources
import os

def main(argv):
    manifest = ''
    orgprofile = ''
    seclogprofile = ''
    
    setup_environment()
    
    import boto3
    
    try:
        opts, args = getopt.getopt(argv,"hms:o:",["manifest=", "seclog=", "org="])
    except getopt.GetoptError:
        display_help()
        sys.exit(2)
    
    for opt, arg in opts:
        if opt == '-h':
            display_help()
            sys.exit()
        elif opt in ("-m", "--manigest"):
            manifest = arg
        elif opt in ("-o", "--org"):
            orgprofile = arg
        elif opt in ("-s", "--seclog"):
            seclogprofile = arg
    
    print('Seclog Profile "', seclogprofile)
    print('Manifest "', manifest)

    if orgprofile.len == 0:
        print('Organisation Profile "', orgprofile)

def display_help():
    print('EC-Update-LZ.py -m <manifest> -s <seclogprofile> -o <orgprofile>')

def setup_environment():

    is_windows = sys.platform.startswith('win')

    # Setup virtual environment
    python = sys.executable
    subprocess.check_call([python, '-m', 'venv', './.python'], stdout=subprocess.DEVNULL)
    if is_windows:
        subprocess.check_call(['./.python/bin/activate'], stdout=subprocess.DEVNULL)
    else:
        subprocess.check_call(['source', './bin/activate'], stdout=subprocess.DEVNULL)

    # Install dependencies
    required = {'boto3'}
    installed = {pkg.key for pkg in pkg_resources.working_set}
    missing = required - installed

    if missing:
        print('Installing required python modules')
        subprocess.check_call([python, '-m', 'pip', 'install', *missing], stdout=subprocess.DEVNULL)
    

if __name__ == "__main__":
    main(sys.argv[1:])