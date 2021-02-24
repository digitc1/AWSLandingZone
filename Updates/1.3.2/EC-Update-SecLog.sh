#!/bin/bash

#   --------------------------------------------------------
#   Updates/1.3.2/EC-Update-Seclog.sh
#   
#   v1.0.0    J. Silva          Initial version.
#   --------------------------------------------------------

#   --------------------
#       Parameters
#   --------------------

seclogprofile=${seclogprofile:-}
splunkprofile=${splunkprofile:-}
logdestination=${logdestination:-}
guarddutyintegration=${guarddutyintegration:-true}
cloudtrailintegration=${cloudtrailintegration:-true}
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

#   --------------------
#       Templates
#   --------------------

CFN_BUCKETS_TEMPLATE='../../CFN/EC-lz-s3-buckets.yml'
CFN_TAGS_PARAMS_FILE='../../CFN/EC-lz-TAGS-params.json'

#   ---------------------
#   The command line help
#   ---------------------
display_help() {

    echo "Usage: $0 --seclogprofile <Seclog Acc Profile>"
    echo ""
    echo "   Provide "
    echo "   --seclogprofile           : The account profile of the central SecLog account as configured in your AWS profile"
    echo "   --batch                  : Flag to enable or disable batch execution mode. Default: false (optional)"
    echo ""
    exit 1
}

#   ----------------------------
#   Update Seclog Account
#   ----------------------------
update_seclog() {



    echo ""
    echo "- This script will configure a the SecLog account with following settings:"
    echo "   ----------------------------------------------------"
    echo "     SecLog Account to be configured:     $seclogprofile"
    echo "     SecLog Account Id:                   $SECLOG_ACCOUNT_ID"
    echo "   ----------------------------------------------------"
    echo ""
    
    if [ "$batch" == "false" ] ; then
        echo "   If this is correct press enter to continue"
        read -p "  or CTRL-C to break"
    fi

    #   ------------------------------------
    #   Cloudtrail bucket / Config bucket / Access_log bucket ...
    #   ------------------------------------

    echo ""
    echo "- Cloudtrail bucket / Config bucket / Access_log bucket ... "
    echo "-----------------------------------------------------------"
    echo ""

    aws cloudformation update-stack \
    --stack-name 'SECLZ-Central-Buckets' \
    --template-body file://$CFN_BUCKETS_TEMPLATE \
    --parameters file://$CFN_TAGS_PARAMS_FILE \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $seclogprofile

    StackName=SECLZ-Central-Buckets
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "UPDATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName



}

# ---------------------------------------------
# Check if correct options are given
# on the commandline and start configurations
# ---------------------------------------------



if  [ -z "$seclogprofile" ] ; then
    display_help
    exit 0
fi



#start account configuration
update_seclog
