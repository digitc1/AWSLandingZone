#!/bin/bash

#   --------------------------------------------------------
#
#       Automates the following:
#       
#       - Configure an AWS account
#
#       Prerequesites:
#       - We are assuming that all ssm parameters are in place
#       - We are assuming that the account has already a CloudBrokerAccountAccess role created
#
#       Usage:
#       $ ./EC-Update-Client.sh  --clientaccprofile <Client Acc. Profile>  [--batch <true|false>]
#
#
#   Version History
#
#   v1.0.0  J. Silva   Initial Version
#
#   --------------------------------------------------------

#       --------------------
#       Parameters
#       --------------------

clientaccprofile=${clientaccprofile:-}
seclogprofile=${seclogprofile:-}
guarddutyintegration=${guarddutyintegration:-true}


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
ALL_REGIONS_EXCEPT_IRELAND='["ap-northeast-1","ap-northeast-2","ap-south-1","ap-southeast-1","ap-southeast-2","ca-central-1","eu-central-1","eu-north-1","eu-west-2","eu-west-3","sa-east-1","us-east-1","us-east-2","us-west-1","us-west-2"]'


# parameters for scripts
CFN_GUARDDUTY_TEMPLATE_GLOBAL='../../CFN/EC-lz-Config-Guardduty-all-regions.yml'



#   ---------------------
#   The command line help
#   ---------------------
display_help() {
    echo "Usage: $0  --clientaccprofile <Client Acc. Profile> --seclogprofile <Seclog Acc Profile> --guarddutyintegration <true|false>" >&2
    echo ""
    echo "   Provide "
    echo "   --clientaccprofile  : The client account as configured in your AWS profile"
    echo "   --seclogprofile     : The account profile of the central SecLog account as configured in your AWS profile"
    echo "   --guarddutyintegration   : Flag to enable or disable GuardDuty seclog integration. Default: true (optional)"
    echo ""
    exit 1
}

update_client() {

    # Get client account Identity
    CLIENT_ACCOUNT_ID=`aws --profile $clientaccprofile sts get-caller-identity --query 'Account' --output text`
    # Get seclog account Identity
    SECLOG_ACCOUNT_ID=`aws --profile $seclogprofile sts get-caller-identity --query 'Account' --output text`

    #   --------------------------------------------------------------
    #   Granting the client to use Event-Bus in SecLog for all regions
    #   --------------------------------------------------------------

    echo ""
    echo "Granting new account access to EventBus on all regions"
    echo "--------------"
    echo ""

    ALL_REGIONS_EXCEPT_IRELAND_ARRAY=`echo $ALL_REGIONS_EXCEPT_IRELAND | sed -e 's/\[//g;s/\]//g;s/,/ /g;s/\"//g'`
	  for i in ${ALL_REGIONS_EXCEPT_IRELAND_ARRAY[@]}; 
      do
        aws --profile $seclogprofile --region $i events put-permission --action events:PutEvents --principal $CLIENT_ACCOUNT_ID --statement-id $clientaccprofile
      done

    #   ------------------------------------
    #    Enable cloudtrail globally using stacksets
    #   ------------------------------------


    echo ""
    echo "-  Enable cloudtrail globally"
    echo "--------------------------------------------------"
    echo ""

    # Create StackInstances (globally excluding Ireland)
    aws cloudformation create-stack-instances \
    --stack-set-name 'SECLZ-Enable-Guardduty-Globally' \
    --accounts $CLIENT_ACCOUNT_ID \
    --parameter-overrides ParameterKey=SecLogMasterAccountId,ParameterValue=$SECLOG_ACCOUNT_ID ParameterKey=EnableSecLogIntegrationFoGuardDutyParam,ParameterValue=$guarddutyintegration \
    --operation-preferences FailureToleranceCount=3,MaxConcurrentCount=5 \
    --regions $ALL_REGIONS_EXCEPT_IRELAND \
    --profile $seclogprofile


}

# ---------------------------------------------
# Check if correct options are given
# on the commandline and start configurations
# ---------------------------------------------

# Simple check if two arguments are provided
if [ -z "$clientaccprofile" ] || [ -z "$seclogprofile" ] ; then
    display_help
    exit 0
fi


#start account configuration
update_client