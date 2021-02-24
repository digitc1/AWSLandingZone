#!/bin/bash

#   --------------------------------------------------------
#   Updates/1.3.2/EC-Update-Client.sh
#   
#   v1.0.0    J. Silva          Initial version.
#   --------------------------------------------------------

#   --------------------
#       Parameters
#   --------------------

clientaccprofile=${clientaccprofile:-}
batch=${batch:-false}

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
    echo "   --clientaccprofile        : The account profile of the client account as configured in your AWS profile"
    echo "   --batch                  : Flag to enable or disable batch execution mode. Default: false (optional)"
    echo ""
    exit 1
}

#   ----------------------------
#   Update Client Account
#   ----------------------------
update_client() {




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
