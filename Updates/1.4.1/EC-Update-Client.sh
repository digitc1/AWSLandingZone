#!/bin/bash

#   --------------------------------------------------------
#   Updates/1.4.1/EC-Update-Client.sh
#   
#   v1.0.0    J. Silva          Initial version.
#   --------------------------------------------------------

#   --------------------
#       Parameters
#   --------------------

clientaccprofile=${clientaccprofile:-}

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

    echo "Usage: $0 --clientaccprofile <Client Acc Profile>"
    echo ""
    echo "   Provide "
    echo "   --clientaccprofile        : The profile of the client account as configured in your AWS profile"
    echo ""
    exit 1
}

#   ----------------------------
#   Update Client Account
#   ----------------------------
update_client() {

    #   ------------------------------------
    # Store notification-E-mail, OrgID, SecAccountID in SSM parameters
    #   ------------------------------------

    echo ""
    echo "- Storing SSM parameters for Seclog account"
    echo "--------------------------------------------------"
    echo ""
    echo "  populating: "
    echo "    - /org/member/SLZVersion"

    LZ_VERSION=`cat ../../EC-SLZ-Version.txt | xargs`
    
    aws --profile $clientaccprofile ssm put-parameter --name /org/member/SLZVersion --type String --value $LZ_VERSION --overwrite


}

# ---------------------------------------------
# Check if correct options are given
# on the commandline and start configurations
# ---------------------------------------------



if  [ -z "$clientaccprofile" ] ; then
    display_help
    exit 0
fi



#start account configuration
update_client
