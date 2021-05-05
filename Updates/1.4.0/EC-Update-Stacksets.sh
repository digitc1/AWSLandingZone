#!/bin/bash

#   --------------------------------------------------------
#   Updates/1.4.0/EC-Update-Stacksets.sh
#   
#   v1.0.0    J. Silva          Initial version.
#   --------------------------------------------------------

#   --------------------
#       Parameters
#   --------------------

seclogprofile=${seclogprofile:-}
guarddutyintegration=${guarddutyintegration:-true}

while [ $# -gt 0 ]; do

   if [[ $1 == *"--"* ]]; then
        param="${1/--/}"
        declare $param="$2"
   fi

  shift
done


#   --------------------
#       Templates
#   --------------------

CFN_GUARDDUTY_TEMPLATE_GLOBAL='../../CFN/EC-lz-Config-Guardduty-all-regions.yml'

#   ---------------------
#   The command line help
#   ---------------------
display_help() {

    echo "Usage: $0 <params>"
    echo ""
    echo "   Provide "
    echo "   --seclogprofile                  : The account profile of the central SecLog account as configured in your AWS profile"
    echo "   --guarddutyintegration           : Flag to enable or disable GuardDuty seclog integration. Default: true (optional)"
    echo ""
    exit 1
}

#   ----------------------------
#   Update Seclog Account Stackets 
#   ----------------------------
update_client() {

    #   ------------------------------------
    #    Update cloudtrail globally using stacksets
    #   ------------------------------------


    echo ""
    echo "-  update cloudtrail globally"
    echo "--------------------------------------------------"
    echo ""

    # Getting SecLog Account Id
    SECLOG_ACCOUNT_ID=`aws --profile $seclogprofile sts get-caller-identity --query 'Account' --output text`


    # Create StackSet (Enable Guardduty globally)
    aws cloudformation  update-stack-set \
    --stack-set-name 'SECLZ-Enable-Guardduty-Globally' \
    --parameters ParameterKey=SecLogMasterAccountId,ParameterValue=$SECLOG_ACCOUNT_ID ParameterKey=EnableSecLogIntegrationFoGuardDutyParam,ParameterValue=$guarddutyintegration \
    --template-body file://$CFN_GUARDDUTY_TEMPLATE_GLOBAL \
    --capabilities CAPABILITY_IAM \
    --profile $seclogprofile

}


# ---------------------------------------------
# Check if correct options are given
# on the commandline and start configurations
# ---------------------------------------------


if [[ ( -z "$seclogprofile" ) ]]; then
    display_help
    exit 0
fi



#start account configuration
update_client
