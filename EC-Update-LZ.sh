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

    echo "" 
    echo "#######"
    echo "####### AWS Landing Zone update script environment configuration"
    echo "####### Checking environment..."
    echo ""
    
    #installing python 3
    if [[ "$(python3 -V)" =~ "Python 3" ]] ; then
        echo "Python 3 installed [${GREEN}OK${NC}]"
    else
        echo "Python 3 installed [${RED}FAIL${NC}]"
        echo "Exiting..."
        exit 1
    fi
    
    #installing pip3
    if [[ "$(pip3 -V)" =~ "pip" ]] ; then
        echo "PIP 3 installed [${GREEN}OK${NC}]"
    else
        echo "PIP 3 installed [${RED}FAIL${NC}]"
        echo "Exiting..."
        exit 1
    fi
    
   
    #setting up venv
    if [[ "$(env |grep VIRTUAL_ENV |wc -l)" == '1' ]] ; then
        echo "Python running on venv [${GREEN}OK${NC}]"
    else
        echo -ne "Virtual virtual environment installing... \033[0K\r"
        
        python3 -m venv $venv &> /dev/null
        source $venv/bin/activate
        
        if [[ "$(env |grep VIRTUAL_ENV |wc -l)" == '1' ]] ; then
            echo "${EL}Virtual environment configured [${GREEN}OK${NC}]"
        else
            echo "${EL}Virtual environment configured [${RED}FAIL${NC}]"
            echo "Exiting..."
            exit
        
        fi
    fi
    
    
    
    DEPENDENCIES=(boto3 botocore time json colorama zipfile shlex cursor pyyaml cfn_flip)
    
    #installing python dependencies
    for dep in "${DEPENDENCIES[@]}" 
        do
        idep=$dep
        if [[ $idep == "pyyaml" ]] ; then
                idep='yaml'
            fi
        #if [[ "$(python3 -c 'import sys, pkgutil; print(True) if pkgutil.find_loader(sys.argv[1]) else print(False)' $idep)" == "True" ]] ; then
        #    echo "$dep installed [${GREEN}OK${NC}]"
        #else
        echo -ne "Installing $dep... \033[0K\r"
            
            
            

        pip3 install -U $dep &> /dev/null;
        if [[ "$(python3 -c 'import sys, pkgutil; print(True) if pkgutil.find_loader(sys.argv[1]) else print(False)' $idep)" == "True" ]] ; then
            echo ${EL}"$dep installed [${GREEN}OK${NC}]"
        else
            echo "${EL}$dep installed [${RED}FAIL${NC}]"
            echo "Exiting..."
            exit 1
        fi
            
        #fi
    done

#run python update script
echo ""
echo "####### Environment is in good shape. Starting update script..."
echo "#######"
echo ""

params="-m $manifest"
if  [ ! -z "$seclog" ] ; then
    params="$params -s $seclog"
fi
if  [ ! -z "$org" ] ; then
    params="$params -o $org"
fi

python3 ./EC-Update-LZ.py $params

#deactivating pyton runtime environment
deactivate
}



# Check to validate number of parameters entered
if  [ -z "$manifest" ] ; then
    display_help
    exit 0
fi

update