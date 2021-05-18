#!/bin/bash

#   --------------------------------------------------------
#
#       Landing Zone Update Script:


RED=`tput setaf 1`
GREEN=`tput setaf 2`
NC=`tput sgr0`
EL=`tput el`

venv='.venv'

#   --------------------
#       Parameters
#   --------------------

manifest=${manifest:-}
seclog=${seclog:-}
org=${org:-}

# Parameter parsing
while [ $# -gt 0 ]; do

   if [[ $1 == *"--"* ]]; then
        param="${1/--/}"
        declare $param="$2"
   fi

  shift
done


# Script Spinner waiting for cloudformation completion
export i=1
export sp="/-\|"


#   ---------------------
#   The command line help
#   ---------------------
display_help() {
    echo "Usage: $0 <params>"
    echo ""
    echo "   Provide "
    echo "   --manifest     : Manifest file (json) for the Landing Zone update"
    echo "   --seclog       : The account profile of the central SECLOG account as configured in your AWS profile (optional)"
    echo "   --org          : The account profile of the central Organisation account as configured in your AWS profile (optional)"
    echo ""
    exit 1
}

#   ---------------------
#   Environment setup
#   ---------------------
update() {

    echo 'Checking environment...'
    echo ''
    
    #python 3
    if [[ "$(python3 -V)" =~ "Python 3" ]] ; then
        echo "${GREEN}✔${NC} Python 3 is installed" 
    else
        echo "${RED}✘${NC} Python 3 is not installed... exiting"
        exit 1
    fi
    
    #venv
    if [[ "$(env |grep VIRTUAL_ENV |wc -l)" == '1' ]] ; then
        echo "${GREEN}✔${NC} Python running on venv" 
    else
        echo -ne "  Virtual virtual environment installing... \033[0K\r"
        
        virtualenv $venv &> /dev/null
        source $venv/bin/activate
        
        if [[ "$(env |grep VIRTUAL_ENV |wc -l)" == '1' ]] ; then
            echo "${EL}${GREEN}✔${NC} Virtual environment configured"
        else
            echo "${EL}${RED}✘${NC} Virtual environment not configured... exiting"
            exit
        
        fi
    fi
    
     #pip3
    if [[ "$(pip3 -V)" =~ "pip" ]] ; then
        echo "${GREEN}✔${NC} PIP 3 is installed" 
    else
        echo "${RED}✘${NC} PIP 3 is not installed... exiting"
        exit 1
    fi
    
    DEPENDENCIES=(boto3 json)
    
    #python dependencies
    for dep in "${DEPENDENCIES[@]}" 
        do
        if [[ "$(python3 -c 'import sys, pkgutil; print(True) if pkgutil.find_loader(sys.argv[1]) else print(False)' $dep)" == "True" ]] ; then
            echo "${GREEN}✔${NC} $dep is installed" 
        else
            
            echo -ne "  $dep is not installed... installing \033[0K\r"
           
            pip3 install $dep &> /dev/null;
            if [[ "$(python3 -c 'import sys, pkgutil; print(True) if pkgutil.find_loader(sys.argv[1]) else print(False)' $dep)" == "True" ]] ; then
                echo "${EL}${GREEN}✔${NC} $dep installed" 
            else
                echo "${EL}${RED}✘${NC} $dep is not installed... exiting"
                exit 1
            fi
            
        fi
    done

#run python update script
echo ''
echo 'Starting update...'
echo ''

python3 ./EC-Update-LZ.py -m $manifest -o $org -s $seclog

#deactivating pyton runtime environment
deactivate
}


# ---------------------------------------------
# Check if correct options are given
# on the commandline and start configurations
# ---------------------------------------------

# Check to validate number of parameters entered
if  [ -z "$manifest" ] ; then
    display_help
    exit 0
fi

update