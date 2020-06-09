#!/bin/bash

#   --------------------------------------------------------
#
#       Automates the following:
#       - Deployment of central buckets for cloudtrail/config/access_logs
#       - Setup cloudtrail, config and creates an SNS topic
#       - Enables Guardduty and Guardduty notifications to SNS
#       - Enables Security Hub
#       - Deploys CIS notifications for Cloudtrail based on cloudwatch log metric filters
#       - Sets password policy for IAM
#
#       Usage
#       $ ./EC-Configure-SecLog-Account.sh ORG_PROFILE E-SECLOG_PROFILE SECLOG_NOTIF_EMAIL
#
#   Version History
#
#   v1.0    J. Vandenbergen   Initial Version
#   v2.0    L. Leonard        Version dedicated to EC-BROKER-IAM
#   --------------------------------------------------------

#   --------------------
#       Parameters
#       --------------------
ORG_PROFILE=$1
SECLOG_PROFILE=$2
SECLOG_NOTIF_EMAIL=$3

# Script Spinner waiting for cloudformation completion
export i=1
export sp="/-\|"

AWS_REGION='eu-west-1'
ALL_REGIONS_EXCEPT_IRELAND='["ap-northeast-1","ap-northeast-2","ap-south-1","ap-southeast-1","ap-southeast-2","ca-central-1","eu-central-1","eu-west-2","eu-west-3","sa-east-1","us-east-1","us-east-2","us-west-1","us-west-2"]'

# parameters for scripts
CFN_BUCKETS_TEMPLATE='CFN/EC-lz-s3-buckets.yml'
CFN_LOG_TEMPLATE='CFN/EC-lz-config-cloudtrail-logging.yml'
CFN_GUARDDUTY_DETECTOR_TEMPLATE='CFN/EC-lz-guardDuty-detector.yml'
CFN_SECURITYHUB_TEMPLATE='CFN/EC-lz-securityHub.yml'
CFN_NOTIFICATIONS_CT_TEMPLATE='CFN/EC-lz-notifications.yml'
CFN_IAM_PWD_POLICY='CFN/EC-lz-iam-setting_password_policy.yml'
CFN_TAGS_PARAMS_FILE='CFN/EC-lz-TAGS-params.json'
CFN_CLOUDTRAIL_KMS='CFN/EC-lz-Cloudtrail-kms-key.yml'
CFN_STACKSET_ADMIN_ROLE='CFN/AWSCloudFormationStackSetAdministrationRole.yml'
CFN_STACKSET_EXEC_ROLE='CFN/AWSCloudFormationStackSetExecutionRole.yml'
CFN_STACKSET_CONFIG_SECHUB_GLOBAL='CFN/EC-lz-Config-SecurityHub-all-regions.yml'
CFN_USER_GROUP='CFN/EC-lz-Master-User-Groups.yml'
CFN_PROFILES_ROLES='CFN/EC-lz-Profiles-Roles.yml'


#   ---------------------
#   The command line help
#   ---------------------
display_help() {
    echo "Usage: $0 ORG_PROFILE E-SECLOG_PROFILE SECLOG_NOTIF_EMAIL" >&2
    echo ""
    echo "   Provide an account name of the SecLog account to configure"
    echo "   and e-mail address for the security notifications."
    echo ""
    exit 1
}

#   ----------------------------
#   Configure Seclog Account
#   ----------------------------
configure_seclog() {
    # Get organizations Identity
    ORG_ACCOUNT_ID=`aws --profile $ORG_PROFILE sts get-caller-identity --query 'Account' --output text`

    #getting organization ouId
    ORG_OU_ID=`aws --profile $ORG_PROFILE organizations describe-organization --query '[Organization.Id]' --output text`

    # Getting SecLog Account Id
    SECLOG_ACCOUNT_ID=`aws --profile $SECLOG_PROFILE sts get-caller-identity --query 'Account' --output text`

    echo ""
    echo "- This script will configure a the SecLog account with following settings:"
    echo "   ----------------------------------------------------"
    echo "     SecLog Account to be configured:  $SECLOG_PROFILE"
    echo "     SecLog Account Id:                $SECLOG_ACCOUNT_ID"
    echo "     Security Notifications e-mail:    $SECLOG_NOTIF_EMAIL"
    echo "     in AWS Region:                    $AWS_REGION"
    echo "   ----------------------------------------------------"
    echo ""
    echo "   If this is correct press enter to continue"
    read -p "  or CTRL-C to break"

    #   ------------------------------------
    # Store notification-E-mail, OrgID, SecAccountID in SSM parameters
    #   ------------------------------------

    echo ""
    echo "- Storing SSM parameters for Seclog accunt and notification e-mail"
    echo "--------------------------------------------------"
    echo ""
    echo "  populating: "
    echo "   - /org/member/SecLogMasterAccountId"
    echo "   - /org/member/SecLogOU"
    echo "   - /org/member/SecLog_notification-mail"

    aws --profile $SECLOG_PROFILE ssm put-parameter --name /org/member/SecLog_notification-mail --type String --value $SECLOG_NOTIF_EMAIL --overwrite
    aws --profile $SECLOG_PROFILE ssm put-parameter --name /org/member/SecLogMasterAccountId --type String --value $SECLOG_ACCOUNT_ID --overwrite
    aws --profile $SECLOG_PROFILE ssm put-parameter --name /org/member/SecLogOU --type String --value $ORG_OU_ID --overwrite

    #   ------------------------------------
    #   Create CFN template for AdministrationRole and ExecutionRole
    #   ------------------------------------

    echo ""
    echo "- Creating StackSetExecution- and Administrator-Role"
    echo "----------------------------------------------------"
    echo ""
    # AdministrationRole
    aws cloudformation create-stack \
    --stack-name SECLZ-StackSetAdministrationRole \
    --template-body file://$CFN_STACKSET_ADMIN_ROLE \
    --enable-termination-protection \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $SECLOG_PROFILE

    # ExecutionRole
    aws cloudformation create-stack \
    --stack-name SECLZ-StackSetExecutionRole \
    --template-body file://$CFN_STACKSET_EXEC_ROLE \
    --enable-termination-protection \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $SECLOG_PROFILE

    #   ------------------------------------
    #   Create Cfn Stacks KMS encryption key
    #   ------------------------------------

    echo ""
    echo "- Creating KMS key for cloudtrail encryption ... "
    echo "-----------------------------------------------------------"
    echo ""

    aws cloudformation create-stack \
    --stack-name 'SECLZ-Cloudtrail-KMS' \
    --template-body file://$CFN_CLOUDTRAIL_KMS \
    --enable-termination-protection \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $SECLOG_PROFILE

    StackName=SECLZ-Cloudtrail-KMS
    aws --profile $SECLOG_PROFILE cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $SECLOG_PROFILE cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "CREATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $SECLOG_PROFILE cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    sleep 5

    # Getting KMS key encryption arn
    KMS_KEY_ARN=`aws --profile $SECLOG_PROFILE ssm get-parameter --name "/org/member/KMSCloudtrailKey_arn" --output text --query 'Parameter.Value'`

    #Storing the KMSCloudTrailKeyArn into SSM Parameter Store
    aws --profile $SECLOG_PROFILE ssm put-parameter --name /org/member/KMSCloudtrailKey_arn --type String --value $KMS_KEY_ARN --overwrite &>/dev/null


    #   ------------------------------------
    #   Cloudtrail bucket / Config bucket / Access_log bucket ...
    #   ------------------------------------

    echo ""
    echo "- Cloudtrail bucket / Config bucket / Access_log bucket ... "
    echo "-----------------------------------------------------------"
    echo ""

    aws cloudformation create-stack \
    --stack-name 'SECLZ-Central-Buckets' \
    --template-body file://$CFN_BUCKETS_TEMPLATE \
    --parameters file://$CFN_TAGS_PARAMS_FILE \
    --enable-termination-protection \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $SECLOG_PROFILE

    StackName=SECLZ-Central-Buckets
    aws --profile $SECLOG_PROFILE cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $SECLOG_PROFILE cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "CREATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $SECLOG_PROFILE cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    sleep 5

    #   ------------------------------------
    #   Create password policy for IAM
    #   ------------------------------------

    echo ""
    echo "- Creating a password policy for IAM"
    echo "--------------------------------------"
    echo ""

    aws cloudformation create-stack \
    --stack-name 'SECLZ-Iam-Password-Policy' \
    --template-body file://$CFN_IAM_PWD_POLICY \
    --capabilities CAPABILITY_IAM \
    --enable-termination-protection \
    --profile $SECLOG_PROFILE

    StackName="SECLZ-Iam-Password-Policy"
    aws --profile $SECLOG_PROFILE cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $SECLOG_PROFILE cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "CREATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $SECLOG_PROFILE cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    sleep 5

    #   ------------------------------------
    #   Creating config, cloudtrail, SNS notifications
    #   ------------------------------------


    echo ""
    echo "- Creating config, cloudtrail, SNS notifications"
    echo "--------------------------------------------------"
    echo ""

    aws cloudformation create-stack \
    --stack-name 'SECLZ-config-cloudtrail-SNS' \
    --template-body file://$CFN_LOG_TEMPLATE \
    --enable-termination-protection \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $SECLOG_PROFILE

    StackName="SECLZ-config-cloudtrail-SNS"
    aws --profile $SECLOG_PROFILE cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $SECLOG_PROFILE cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "CREATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $SECLOG_PROFILE cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    sleep 5

    #   ------------------------------------
    #   Enable guardduty and securityhub in seclog master account
    #   ------------------------------------


    echo ""
    echo "- Enable guardduty in seclog master account"
    echo "--------------------"
    echo ""

    aws cloudformation create-stack \
    --stack-name 'SECLZ-Guardduty-detector' \
    --template-body file://$CFN_GUARDDUTY_DETECTOR_TEMPLATE \
    --enable-termination-protection \
    --profile $SECLOG_PROFILE

    sleep 5

    echo ""
    echo "- Enable SecurityHub in seclog master account"
    echo "----------------------"
    echo ""

    aws cloudformation create-stack \
    --stack-name 'SECLZ-SecurityHub' \
    --template-body file://$CFN_SECURITYHUB_TEMPLATE \
    --parameters file://$CFN_TAGS_PARAMS_FILE \
    --enable-termination-protection \
    --profile $SECLOG_PROFILE

    sleep 5

    #   ------------------------------------
    #   Enable Notifications for CIS cloudtrail metrics filters
    #   ------------------------------------


    echo ""
    echo "- Enable Notifications for CIS cloudtrail metrics filters"
    echo "---------------------------------------"
    echo ""

    aws cloudformation create-stack \
    --stack-name 'SECLZ-Notifications-Cloudtrail' \
    --template-body file://$CFN_NOTIFICATIONS_CT_TEMPLATE \
    --enable-termination-protection \
    --profile $SECLOG_PROFILE

    StackName="SECLZ-Notifications-Cloudtrail"
    aws --profile $SECLOG_PROFILE cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $SECLOG_PROFILE cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "CREATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $SECLOG_PROFILE cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    #   ------------------------------------
    #   Enable Config and SecurityHub globally using stacksets
    #   ------------------------------------

    # Create StackSet (Enable Config and SecurityHub globally)
    aws cloudformation create-stack-set \
    --stack-set-name 'SECLZ-Enable-Config-SecurityHub-Globally' \
    --template-body file://$CFN_STACKSET_CONFIG_SECHUB_GLOBAL \
    --parameters ParameterKey=SecLogMasterAccountId,ParameterValue=$SECLOG_ACCOUNT_ID \
    --capabilities CAPABILITY_IAM \
    --profile $SECLOG_PROFILE

    # Create StackInstances (globally except Ireland)
    aws cloudformation create-stack-instances \
    --stack-set-name 'SECLZ-Enable-Config-SecurityHub-Globally' \
    --accounts $SECLOG_ACCOUNT_ID \
    --parameter-overrides ParameterKey=SecLogMasterAccountId,ParameterValue=$SECLOG_ACCOUNT_ID \
    --regions $ALL_REGIONS_EXCEPT_IRELAND \
    --profile $SECLOG_PROFILE


}

# ---------------------------------------------
# Check if correct options are given
# on the commandline and start configurations
# ---------------------------------------------

# Simple check to see if 3rd argument looks like an e-mail address "@"
mail=`echo $3 | sed -e s/.*@.*/@/g`

while :
do
    case "$mail" in
      @)
          # valid 3rd argument is an e-mail
          break
          ;;
      *)
          display_help  # Call your function
          exit 0
          ;;
    esac
done

#start account configuration
configure_seclog
