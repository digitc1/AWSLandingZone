#!/bin/bash

#   --------------------------------------------------------
#   Adds eu-north-1 to the stackset instances for SecurityHub-all-regions
#   
#   v1.0.0    J. Silva          Initial version.
#   --------------------------------------------------------

#   --------------------
#       Parameters
#   --------------------

seclogprofile=${seclogprofile:-}
guarddutyintegration=${guarddutyintegration:-}

while [ $# -gt 0 ]; do

   if [[ $1 == *"--"* ]]; then
        param="${1/--/}"
        declare $param="$2"
        # echo $1 $2 // Optional to see the parameter:value result
   fi

  shift
done




# Script Spinner waiting for cloudformation completion
export i=1
export sp="/-\|"

AWS_REGION='eu-west-1'
REGIONS_EXCEPT_IRELAND='["ap-northeast-1","ap-northeast-2","ap-south-1","ap-southeast-1","ap-southeast-2","ca-central-1","eu-central-1","eu-north-1","eu-west-2","eu-west-3","sa-east-1","us-east-1","us-east-2","us-west-1","us-west-2"]'


# parameters for scripts
CFN_GUARDDUTY_TEMPLATE_GLOBAL='../CFN/EC-lz-Config-Guardduty-all-regions.yml'


#   ---------------------
#   The command line help
#   ---------------------
display_help() {

    echo "Usage: $0 --seclogprofile <Seclog Acc Profile> --guarddutyintegration <true|false>"
    echo ""
    echo "   Provide "
    echo "   --seclogprofile     : The account profile of the central SecLog account as configured in your AWS profile"
    echo "   --guarddutyintegration   : Flag to enable or disable GuardDuty seclog integration. Default: true (optional)"
    echo ""
    exit 1
}

#   ----------------------------
#   Configure Seclog Account
#   ----------------------------
update_seclog() {

  
    # Getting SecLog Account Id
    SECLOG_ACCOUNT_ID=`aws --profile $seclogprofile sts get-caller-identity --query 'Account' --output text`
    
    #   ------------------------------------
    #    Enable cloudtrail globally using stacksets
    #   ------------------------------------


    echo ""
    echo "-  Enable cloudtrail globally"
    echo "--------------------------------------------------"
    echo ""

    # Create StackSet (Enable Guardduty globally)
    aws cloudformation create-stack-set \
    --stack-set-name 'SECLZ-Enable-Guardduty-Globally' \
    --parameters ParameterKey=SecLogMasterAccountId,ParameterValue=$SECLOG_ACCOUNT_ID ParameterKey=EnableSecLogIntegrationFoGuardDutyParam,ParameterValue=$guarddutyintegration \
    --template-body file://$CFN_GUARDDUTY_TEMPLATE_GLOBAL \
    --capabilities CAPABILITY_IAM \
    --profile $seclogprofile

    # Create StackInstances (globally excluding Ireland)
    aws cloudformation create-stack-instances \
    --stack-set-name 'SECLZ-Enable-Guardduty-Globally' \
    --accounts $SECLOG_ACCOUNT_ID \
    --parameter-overrides ParameterKey=SecLogMasterAccountId,ParameterValue=$SECLOG_ACCOUNT_ID ParameterKey=EnableSecLogIntegrationFoGuardDutyParam,ParameterValue=$guarddutyintegration \
    --operation-preferences FailureToleranceCount=3,MaxConcurrentCount=5 \
    --regions $ALL_REGIONS_EXCEPT_IRELAND \
    --profile $seclogprofile


}

# ---------------------------------------------
# Check if correct options are given
# on the commandline and start configurations
# ---------------------------------------------

# Check to validate number of parameters entered
if  [ -z "$seclogprofile" ] || [ -z "$guarddutyintegration" ] ; then
    display_help
    exit 0
fi


#start account configuration
update_seclog
