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
batch=${batch:-false}

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

# parameters for scripts

CFN_LOG_TEMPLATE='./CFN/EC-lz-config-cloudtrail-logging.yml'
CFN_GUARDDUTY_DETECTOR_TEMPLATE='./CFN/EC-lz-guardDuty-detector.yml'
CFN_SECURITYHUB_TEMPLATE='./CFN/EC-lz-securityHub.yml'
CFN_NOTIFICATIONS_CT_TEMPLATE='./CFN/EC-lz-notifications.yml'
CFN_IAM_PWD_POLICY='./CFN/EC-lz-iam-setting_password_policy.yml'
CFN_TAGS_PARAMS_FILE='./CFN/EC-lz-TAGS-params.json'
CFN_STACKSET_EXEC_ROLE='./CFN/AWSCloudFormationStackSetExecutionRole.yml'
CFN_PROFILES_ROLES='./CFN/EC-lz-Profiles-Roles.yml'
CFN_LOCAL_SNS_TEMPLATE='./CFN/EC-lz-local-config-SNS.yml'


#   ---------------------
#   The command line help
#   ---------------------
display_help() {
    echo "Usage: $0  --clientaccprofile <Client Acc. Profile>  [--batch <true|false>]" >&2
    echo ""
    echo "   Provide "
    echo "   --clientaccprofile  : The client account as configured in your AWS profile"
    echo "   --batch             : Flag to enable or disable batch execution mode. Default: false (optional)"
    echo ""
    exit 1
}

update_client() {


    # Get account Identity
    accountId=`aws --profile $clientaccprofile sts get-caller-identity --query 'Account' --output text`


    echo ""
    echo "   Executing Configure Client account script"
    echo "   ========================================="
    echo "   This script will configure a client account with following settings:"
    echo "   ----------------------------------------------------"
    echo "     Account name:                     $clientaccprofile"
    echo "     Account Id:                       $accountId"
    echo "     Primary AWS Region:               $AWS_REGION"
    echo "   ----------------------------------------------------"
    echo ""
    if [ "$batch" == "false" ] ; then
        echo "   If this is correct press enter to continue"
        read -p "  or CTRL-C to break"
    fi

   
    #   Update ExecRole
    #   -------------------

    echo ""
    echo "- Updating StackSetExecutionRole"
    echo "--------------------------------"
    echo ""

    # ExecutionRole
    StackName=SECLZ-StackSetExecutionRole
    aws cloudformation update-stack \
    --stack-name $StackName \
    --template-body file://$CFN_STACKSET_EXEC_ROLE \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $clientaccprofile

  
    sleep 5

    echo ""
    echo "- Enable guardduty in new client account"
    echo "----------------------------------------"
    echo ""

    StackName=SECLZ-Guardduty-detector
    aws cloudformation update-stack \
    --stack-name $StackName \
    --template-body file://$CFN_GUARDDUTY_DETECTOR_TEMPLATE \
    --capabilities CAPABILITY_IAM \
    --profile $clientaccprofile

    aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "UPDATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName


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
 
    echo ""
    echo "- Updating local SNS notifications topic"
    echo "------------------------------------------------"
    echo ""

    StackName=SECLZ-local-SNS-topic
    aws cloudformation update-stack \
    --stack-name $StackName \
    --template-body file://$CFN_LOCAL_SNS_TEMPLATE \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $clientaccprofile

    aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "UPDATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName


    sleep 5

    echo ""
    echo "- Update enabling SecurityHub in new client account"
    echo "------------------------------------------"
    echo ""

    aws cloudformation update-stack \
    --stack-name 'SECLZ-SecurityHub' \
    --template-body file://$CFN_SECURITYHUB_TEMPLATE \
    --parameters file://$CFN_TAGS_PARAMS_FILE \
    --profile $clientaccprofile

    sleep 5

    echo ""
    echo "- Updating password policy for IAM in new client account"
    echo "----------------------------------------------------------"
    echo ""

    aws cloudformation update-stack \
    --stack-name 'SECLZ-Iam-Password-Policy' \
    --template-body  file://$CFN_IAM_PWD_POLICY \
    --capabilities CAPABILITY_IAM \
    --profile $clientaccprofile

    sleep 5

    echo ""
    echo "- Update Enabling Notifications for cloudtrail"
    echo "-------------------------------------"
    echo ""

    StackName=SECLZ-Notifications-Cloudtrail
    aws cloudformation update-stack \
    --stack-name $StackName \
    --template-body file://$CFN_NOTIFICATIONS_CT_TEMPLATE \
    --profile $clientaccprofile

    aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "UPDATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    sleep 5


}

# ---------------------------------------------
# Check if correct options are given
# on the commandline and start configurations
# ---------------------------------------------

# Simple check if two arguments are provided
if [ -z "$clientaccprofile" ] ; then
    display_help
    exit 0
fi


#start account configuration
update_client