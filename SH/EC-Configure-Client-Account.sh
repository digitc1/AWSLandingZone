#!/bin/bash

#   --------------------------------------------------------
#
#		!! Default AWS profile should be for organizations master !!
#
#		Automates the following in Client account:
#
#       - Setup cloudtrail, config and creates an SNS topic
#       - Enables Guardduty
#       - Enables Security Hub
#       - Deploys Basic set of notifications for Cloudtrail
#       - Sets password policy for IAM
#
#       Usage
#       $ ./EC-Configure-Client-Account.sh CUSTOMER_Account_Name CUSTOMER_SecLog_Account_Name
#
#   Version History
#
#   v1.0    J. Vandenbergen   Initial Version
#   --------------------------------------------------------

#   --------------------
#	Parameters
#	--------------------
CLIENT=$1
SECLOG=$2
#Query this from the seclog account parameterstore

AWS_REGION='eu-west-1'

#   ---------------------
#   The command line help
#   ---------------------
display_help() {
    echo "Usage: $0 ACCOUNT_Name SECLOG_Account_Name" >&2
    echo
    echo "   Provide an account name to configure, account name of the central SecLog account as configured in your AWS profile."
    echo
    exit 1
}

#   ----------------------------
#   Configure Client Account
#   ----------------------------
configure_client() {

    # Set parameters
    CFN_LOG_TEMPLATE='./CFN/EC-lz-config-cloudtrail-logging.yml'
    CFN_GUARDDUTY_DETECTOR_TEMPLATE='./CFN/EC-lz-guardDuty-detector.yml'
    CFN_SECURITYHUB_TEMPLATE='./CFN/EC-lz-securityHub.yml'
    CFN_NOTIFICATIONS_CT_TEMPLATE='./CFN/EC-lz-notifications.yml'
    CFN_IAM_PWD_POLICY='./CFN/EC-lz-iam-setting_password_policy.yml'
    CFN_TAGS_PARAMS_FILE='./CFN/EC-lz-TAGS-params.json'
    CFN_STACKSET_EXEC_ROLE='./CFN/AWSCloudFormationStackSetExecutionRole.yml'
    CFN_PROFILES_ROLES='./CFN/EC-lz-Profiles-Roles.yml'
    CFN_LOCAL_SNS_TEMPLATE='./CFN/EC-lz-local-config-SNS.yml'

    # Script Spinner waiting for cloudformation completion
    export i=1
    export sp="/-\|"

    # Get organizations Identity
    accountId=`aws --profile $CLIENT sts get-caller-identity --query 'Account' --output text`
    SecLogAccountId=`aws --profile $SECLOG sts get-caller-identity --query 'Account' --output text`

    #getting organization ouId
    OrgOuId=`aws organizations --profile $CLIENT describe-organization --query '[Organization.Id]' --output text`

    # Getting SecLog Account Id
    AWS_ACC_NUM=`aws --profile $SECLOG sts get-caller-identity --output text | awk '{print $1}'`

    # Getting KMS key encryption arn
    KMS_KEY_ARN=`aws --profile $SECLOG ssm get-parameter --name "/org/member/KMSCloudtrailKey_arn" --output text --query 'Parameter.Value'`

    echo ""
    echo "   Executing Configure Client account script"
    echo "   ========================================="
    echo "   This script will configure a client account with following settings:"
    echo "   ----------------------------------------------------"
    echo "     Account name:                     $CLIENT"
    echo "     Account Id:                       $accountId"
    echo "     SecLog account name:              $SECLOG"
    echo "     SecLog account id:                $SecLogAccountId"
    echo "     Primary AWS Region:               $AWS_REGION"
    echo "   ----------------------------------------------------"
    echo ""
    

    # Store notification-E-mail, OrgID, SecAccountID in SSM parameters
    # -----------------------

    echo ""
    echo "- Storing SSM parameters for KMS, Seclog accunt information"
    echo "------------------------------------------------------------"
    echo ""
    echo "  populating: "
    echo "    - /org/member/SecLogMasterAccountId"
    echo "    - /org/member/SecLogOU"
    echo "    - /org/member/KMSCloudtrailKey_arn"
    aws --profile $CLIENT ssm put-parameter --name /org/member/SecLog_notification-mail --type String --value "SeeSecLog@seclogaccount" --overwrite
    aws --profile $CLIENT ssm put-parameter --name /org/member/SecLogMasterAccountId --type String --value $AWS_ACC_NUM --overwrite
    aws --profile $CLIENT ssm put-parameter --name /org/member/SecLogOU --type String --value $OrgOuId --overwrite
    aws --profile $CLIENT ssm put-parameter --name /org/member/KMSCloudtrailKey_arn --type String --value $KMS_KEY_ARN --overwrite


    #   Create ExecRole
    #   -------------------

    echo ""
    echo "- Creating StackSetExecutionRole"
    echo "--------------------------------"
    echo ""

    # ExecutionRole
    StackName=SECLZ-StackSetExecutionRole
    aws cloudformation create-stack \
    --stack-name $StackName \
    --template-body file://$CFN_STACKSET_EXEC_ROLE \
    --enable-termination-protection \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $CLIENT

    #   Create Profiles Roles (PowerUser, ReadOnly and AdminAcces)
    #   -------------------

    #echo ""
    #echo "- Creating Profiles Roles (PowerUser, ReadOnly and Admin)"
    #echo "--------------------------------"
    #echo ""

    #StackName=SECLZ-ProfilesRoles
    #aws cloudformation create-stack \
    #--stack-name $StackName \
    #--template-body file://$CFN_PROFILES_ROLES \
    #--enable-termination-protection \
    #--capabilities CAPABILITY_NAMED_IAM \
    #--parameters ParameterKey=AccountType,ParameterValue=Client \
    #--profile $CLIENT


    #   ----------------------------------------------
    #   Granting the client to use Event-Bus in SecLog
    #   ----------------------------------------------

    echo ""
    echo "Granting new account access to EventBus"
    echo "--------------"
    echo ""
    # To allow to send to central EventBus
    aws --profile $SECLOG events put-permission --action events:PutEvents --principal $accountId --statement-id $CLIENT



    #	Create Cfn Stacks
    #	-------------------

    echo ""
    echo "- Creating config, cloudtrail, SNS notifications"
    echo "------------------------------------------------"
    echo ""



    StackName=SECLZ-config-cloudtrail-SNS
    aws cloudformation create-stack \
    --stack-name $StackName \
    --template-body file://$CFN_LOG_TEMPLATE \
    --capabilities CAPABILITY_NAMED_IAM \
    --enable-termination-protection \
    --profile $CLIENT


    aws --profile $CLIENT cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $CLIENT cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "CREATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $CLIENT cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    sleep 5
 
    echo ""
    echo "- Creating local SNS notifications topic"
    echo "------------------------------------------------"
    echo ""

    StackName=SECLZ-local-SNS-topic
    aws cloudformation create-stack \
    --stack-name $StackName \
    --template-body file://$CFN_LOCAL_SNS_TEMPLATE \
    --capabilities CAPABILITY_NAMED_IAM \
    --enable-termination-protection \
    --profile $CLIENT

    aws --profile $CLIENT cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $CLIENT cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "CREATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $CLIENT cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    sleep 5

    echo ""
    echo "- Enable guardduty in new client account"
    echo "----------------------------------------"
    echo ""

    aws cloudformation create-stack \
    --stack-name 'SECLZ-Guardduty-detector' \
    --template-body file://$CFN_GUARDDUTY_DETECTOR_TEMPLATE \
    --capabilities CAPABILITY_IAM \
    --enable-termination-protection \
    --profile $CLIENT

    sleep 5

    echo ""
    echo "- Enable SecurityHub in new client account"
    echo "------------------------------------------"
    echo ""

    aws cloudformation create-stack \
    --stack-name 'SECLZ-SecurityHub' \
    --template-body file://$CFN_SECURITYHUB_TEMPLATE \
    --parameters file://$CFN_TAGS_PARAMS_FILE \
    --enable-termination-protection \
    --profile $CLIENT

    sleep 5

    echo ""
    echo "- Creating a password policy for IAM in new client account"
    echo "----------------------------------------------------------"
    echo ""

    aws cloudformation create-stack \
    --stack-name 'SECLZ-Iam-Password-Policy' \
    --template-body  file://$CFN_IAM_PWD_POLICY \
    --capabilities CAPABILITY_IAM \
    --enable-termination-protection \
    --profile $CLIENT

    sleep 5

    echo ""
    echo "- Enable Notifications for cloudtrail"
    echo "-------------------------------------"
    echo ""

    StackName=SECLZ-Notifications-Cloudtrail
    aws cloudformation create-stack \
    --stack-name $StackName \
    --template-body file://$CFN_NOTIFICATIONS_CT_TEMPLATE \
    --enable-termination-protection \
    --profile $CLIENT

    aws --profile $CLIENT cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $CLIENT cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "CREATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $CLIENT cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

}

# ---------------------------------------------
# Check if correct options are given
# on the commandline and start configurations
# ---------------------------------------------

# Simple check if two arguments are provided
if [ -z $2 ]; then
    display_help  # Call your function
    exit 0
fi

#start account configuration
configure_client
