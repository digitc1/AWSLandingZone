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
#       $ ./EC-Update-Client.sh  --clientaccprofile <Client Acc. Profile> 
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


# parameters for scripts
CFN_LOG_TEMPLATE='../../CFN/EC-lz-config-cloudtrail-logging.yml'

#   ---------------------
#   The command line help
#   ---------------------
display_help() {
    echo "Usage: $0  --clientaccprofile <Client Acc. Profile> " >&2
    echo ""
    echo "   Provide "
    echo "   --clientaccprofile  : The client account as configured in your AWS profile"
    echo ""
    exit 1
}

update_client() {


 #	Update Cfn Stacks
    #	-------------------

    echo ""
    echo "- Updating config, cloudtrail, SNS notifications"
    echo "------------------------------------------------"
    echo ""


    # To allow to send to central EventBus
    #aws --profile $seclogprofile events put-permission --action events:PutEvents --principal $accountId --statement-id $clientaccprofile


    StackName=SECLZ-config-cloudtrail-SNS
    aws cloudformation update-stack \
    --stack-name $StackName \
    --template-body file://$CFN_LOG_TEMPLATE \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $clientaccprofile


    aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "UPDATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    sleep 5

    #   ------------------------------------
    #   Enable cloudtrail insights in seclog master account
    #   ------------------------------------


    echo ""
    echo "-  Enable cloudtrail insights in seclog master account"
    echo "--------------------------------------------------"
    echo ""

    aws --profile $clientaccprofile cloudtrail put-insight-selectors --trail-name lz-cloudtrail-logging --insight-selectors '[{"InsightType": "ApiCallRateInsight"}]'

}

# ---------------------------------------------
# Check if correct options are given
# on the commandline and start configurations
# ---------------------------------------------

# Simple check if two arguments are provided
if [ -z "$clientaccprofile" ]  ; then
    display_help
    exit 0
fi


#start account configuration
update_client