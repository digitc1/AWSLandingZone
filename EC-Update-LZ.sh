#!/bin/bash

#   --------------------------------------------------------
#
#       Landing Zone Update Script:


RED=`tput setaf 1`
GREEN=`tput setaf 2`
NC=`tput sgr0`


venv='.python'

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

PROFILE=''

    if [ -n "$seclog"] ; then
        PROFILE='--profile $seclog'
    fi


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
setup_environment() {

    echo 'Checking environment...'
    echo ''
    
    #python 3
    if [[ "$(python3 -V)" =~ "Python 3" ]] ; then
        echo "${GREEN}✔${NC} Python 3 is installed" 
    else
        echo "${RED}✘${NC} Python 3 is not installed... exiting"
        exit 1
    fi
    
    #pip3
    if [[ "$(pip3 -V)" =~ "pip 20" ]] ; then
        echo "${GREEN}✔${NC} PIP 3 is installed" 
    else
        echo "${RED}✘${NC} PIP 3 is not installed... exiting"
        exit 1
    fi
    
    #venv
    if python -c 'import sys; print(sys.prefix != sys.base_prefix)' == 'False' &> /dev/null ; then
        echo "${GREEN}✔${NC} Python running on venv" 
    else
        tput sc
        echo "   Python not running on venv... installing"
        
        python3 -m venv $venv &> /dev/null
        source $venv/bin/activate
        tput rc
        tput ed
        if python -c 'import sys; print(sys.prefix != sys.base_prefix)' == 'False' &> /dev/null ; then
            echo "${GREEN}✔${NC} Python venv configured" 
        else
            echo "${RED}✘${NC} Python not running on venv... exiting"
            exit
        
        fi
    fi
    
    DEPENDENCIES=(boto3)
    
    #python dependencies
    for dep in "${DEPENDENCIES[@]}" 
    do
        if python -c 'import pkgutil; print(not pkgutil.find_loader("$dep"))' == 'True' &> /dev/null; then
            echo "${GREEN}✔${NC} $dep is installed" 
        else
            tput sc
            echo "   $dep is not installed... installing"
           
            pip3 install $dep &> /dev/null;
            tput rc
            tput ed
            if python -c 'import pkgutil; print(not pkgutil.find_loader("$dep"))' == 'True' &> /dev/null; then
                echo " ${GREEN}✔${NC} $dep installed" 
            else
                echo " ${RED}✘${NC} $dep is not installed... exiting"
                exit 1
            fi
            
        fi
    done
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

setup_environment