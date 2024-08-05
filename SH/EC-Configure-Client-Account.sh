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

    # get version number
    LZ_VERSION=`cat ./EC-SLZ-Version.txt | xargs`

    # Set parameters
    CFN_LOG_TEMPLATE='./CFN/EC-lz-config-cloudtrail-logging.yml'
    CFN_GUARDDUTY_DETECTOR_TEMPLATE='./CFN/EC-lz-guardDuty-detector.yml'
    CFN_SECURITYHUB_TEMPLATE='./CFN/EC-lz-securityHub.yml'
    CFN_NOTIFICATIONS_CT_TEMPLATE='./CFN/EC-lz-notifications.yml'
    CFN_IAM_PWD_POLICY='./CFN/EC-lz-iam-setting_password_policy.yml'
    CFN_TAGS_PARAMS_FILE='./CFN/EC-lz-TAGS-params.json'
    CFN_STACKSET_EXEC_ROLE_INIT='./CFN/AWSCloudFormationStackSetExecutionRoleInit.yml'
    CFN_STACKSET_EXEC_ROLE='./CFN/AWSCloudFormationStackSetExecutionRole.yml'
    CFN_PROFILES_ROLES='./CFN/EC-lz-Profiles-Roles.yml'
    CFN_LOCAL_SNS_TEMPLATE='./CFN/EC-lz-local-config-SNS.yml'

    CFN_TAGS_FILE='./CFN/EC-lz-TAGS.json'

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
    
    cloudtrailgroupname=`aws --profile $SECLOG ssm get-parameter --name "/org/member/SecLog_cloudtrail-groupname" --output text --query 'Parameter.Value'`
    insightgroupname=`aws --profile $SECLOG ssm get-parameter --name "/org/member/SecLog_insight-groupname" --output text --query 'Parameter.Value'`
    guarddutygroupname=`aws --profile $SECLOG ssm get-parameter --name "/org/member/SecLog_guardduty-groupname" --output text --query 'Parameter.Value'`
    securityhubgroupname=`aws --profile $SECLOG ssm get-parameter --name "/org/member/SecLog_securityhub-groupname" --output text --query 'Parameter.Value'`
    configgroupname=`aws --profile $SECLOG ssm get-parameter --name "/org/member/SecLog_config-groupname" --output text --query 'Parameter.Value'`
    alarmsgroupname=`aws --profile $SECLOG ssm get-parameter --name "/org/member/SecLog_alarms-groupname" --output text --query 'Parameter.Value'`
    alarmsgroupname=`aws --profile $SECLOG ssm get-parameter --name "/org/member/SecLog_alarms-groupname" --output text --query 'Parameter.Value'`
    

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
    echo "    - /org/member/SecLogVersion"
    echo "    - /org/member/SecLog_cloudtrail-groupname"
    echo "    - /org/member/SecLog_insight-groupname"
    echo "    - /org/member/SecLog_guardduty-groupname"
    echo "    - /org/member/SecLog_securityhub-groupname"
    echo "    - /org/member/SecLog_config-groupname"

    tags=`cat $CFN_TAGS_FILE`

    aws --profile $CLIENT ssm put-parameter --name /org/member/SecLog_notification-mail --type String --value "SeeSecLog@seclogaccount" --overwrite 
    aws --profile $CLIENT ssm add-tags-to-resource --resource-type "Parameter" --resource-id /org/member/SecLog_notification-mail --tags  file://$CFN_TAGS_FILE

    aws --profile $CLIENT ssm put-parameter --name /org/member/SecLogMasterAccountId --type String --value $AWS_ACC_NUM --overwrite 
    aws --profile $CLIENT ssm add-tags-to-resource --resource-type "Parameter" --resource-id /org/member/SecLogMasterAccountId --tags  file://$CFN_TAGS_FILE
    
    aws --profile $CLIENT ssm put-parameter --name /org/member/SecLogOU --type String --value $OrgOuId --overwrite 
    aws --profile $CLIENT ssm add-tags-to-resource --resource-type "Parameter" --resource-id /org/member/SecLogOU --tags  file://$CFN_TAGS_FILE
    
    aws --profile $CLIENT ssm put-parameter --name /org/member/KMSCloudtrailKey_arn --type String --value $KMS_KEY_ARN --overwrite 
    aws --profile $CLIENT ssm add-tags-to-resource --resource-type "Parameter" --resource-id /org/member/KMSCloudtrailKey_arn --tags  file://$CFN_TAGS_FILE
    
    aws --profile $CLIENT ssm put-parameter --name /org/member/SLZVersion --type String --value $LZ_VERSION --overwrite 
    aws --profile $CLIENT ssm add-tags-to-resource --resource-type "Parameter" --resource-id /org/member/SLZVersion --tags  file://$CFN_TAGS_FILE
    


    if  [ ! -z "$cloudtrailgroupname" ] ; then
        aws --profile $CLIENT ssm put-parameter --name /org/member/SecLog_cloudtrail-groupname --type String --value $cloudtrailgroupname --overwrite 
    else
        aws --profile $CLIENT ssm put-parameter --name /org/member/SecLog_cloudtrail-groupname --type String --value "/aws/cloudtrail" --overwrite 
    fi
    aws --profile $CLIENT ssm add-tags-to-resource --resource-type "Parameter" --resource-id /org/member/SecLog_cloudtrail-groupname --tags  file://$CFN_TAGS_FILE

    aws --profile $CLIENT --region $region ssm put-parameter --name /org/member/SecLog_cloudtrail-group-subscription-filter-name --type String --value "DEFAULT" --overwrite
    aws --profile $CLIENT --region $region ssm add-tags-to-resource --resource-type "Parameter" --resource-id /org/member/SecLog_cloudtrail-group-subscription-filter-name --tags  file://$CFN_TAGS_FILE

    
    
    if  [ ! -z "$insightgroupname" ] ; then
        aws --profile $CLIENT ssm put-parameter --name /org/member/SecLog_insight-groupname --type String --value $insightgroupname --overwrite 
    else
        aws --profile $CLIENT ssm put-parameter --name /org/member/SecLog_insight-groupname --type String --value "/aws/cloudtrail/insight" --overwrite 
    fi
    aws --profile $CLIENT ssm add-tags-to-resource --resource-type "Parameter" --resource-id /org/member/SecLog_insight-groupname --tags  file://$CFN_TAGS_FILE

    aws --profile $CLIENT --region $region ssm put-parameter --name /org/member/SecLog_insight-group-subscription-filter-name --type String --value "DEFAULT" --overwrite
    aws --profile $CLIENT --region $region ssm add-tags-to-resource --resource-type "Parameter" --resource-id /org/member/SecLog_insight-group-subscription-filter-name --tags  file://$CFN_TAGS_FILE

    
    for region in $(aws --profile $CLIENT ec2 describe-regions --output text --query "Regions[*].[RegionName]"); do
        if  [ ! -z "$guarddutygroupname" ] ; then
            aws --profile $CLIENT --region $region ssm put-parameter --name /org/member/SecLog_guardduty-groupname --type String --value $guarddutygroupname --overwrite 
        else
            aws --profile $CLIENT --region $region ssm put-parameter --name /org/member/SecLog_guardduty-groupname --type String --value "/aws/events/guardduty" --overwrite 
        fi
        aws --profile $CLIENT --region $region  ssm add-tags-to-resource --resource-type "Parameter" --resource-id /org/member/SecLog_guardduty-groupname --tags  file://$CFN_TAGS_FILE
    
        aws --profile $CLIENT --region $region ssm put-parameter --name /org/member/SecLog_guardduty-group-subscription-filter-name --type String --value "DEFAULT" --overwrite
        aws --profile $CLIENT --region $region ssm add-tags-to-resource --resource-type "Parameter" --resource-id /org/member/SecLog_guardduty-group-subscription-filter-name --tags  file://$CFN_TAGS_FILE

    done
    
    if  [ ! -z "$securityhubgroupname" ] ; then
        aws --profile $CLIENT ssm put-parameter --name /org/member/SecLog_securityhub-groupname --type String --value $securityhubgroupname --overwrite 
    else
        aws --profile $CLIENT ssm put-parameter --name /org/member/SecLog_securityhub-groupname --type String --value "/aws/events/securityhub" --overwrite 
    fi
    aws --profile $CLIENT ssm add-tags-to-resource --resource-type "Parameter" --resource-id /org/member/SecLog_securityhub-groupname --tags  file://$CFN_TAGS_FILE
    

    if  [ ! -z "$configgroupname" ] ; then
        aws --profile $CLIENT ssm put-parameter --name /org/member/SecLog_config-groupname --type String --value $configgroupname --overwrite 
    else
        aws --profile $CLIENT ssm put-parameter --name /org/member/SecLog_config-groupname --type String --value "/aws/events/config" --overwrite 
    fi
    aws --profile $CLIENT ssm add-tags-to-resource --resource-type "Parameter" --resource-id /org/member/SecLog_config-groupname --tags  file://$CFN_TAGS_FILE


    aws --profile $CLIENT --region $region ssm put-parameter --name /org/member/SecLog_config-group-subscription-filter-name --type String --value "DEFAULT" --overwrite
    aws --profile $CLIENT --region $region ssm add-tags-to-resource --resource-type "Parameter" --resource-id /org/member/SecLog_config-group-subscription-filter-name --tags  file://$CFN_TAGS_FILE


    if  [ ! -z "$alarmsgroupname" ] ; then
        aws --profile $CLIENT ssm put-parameter --name /org/member/SecLog_alarms-groupname --type String --value $alarmsgroupname --overwrite 
    else
        aws --profile $CLIENT ssm put-parameter --name /org/member/SecLog_alarms-groupname --type String --value "/aws/events/cloudwatch-alarms" --overwrite 
    fi
    aws --profile $CLIENT ssm add-tags-to-resource --resource-type "Parameter" --resource-id /org/member/SecLog_alarms-groupname --tags  file://$CFN_TAGS_FILE
    


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
    --template-body file://$CFN_STACKSET_EXEC_ROLE_INIT \
    --tags file://$CFN_TAGS_FILE \
    --enable-termination-protection \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $CLIENT
   
    aws --profile $CLIENT cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $CLIENT cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "CREATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $CLIENT cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    sleep 5

    aws cloudformation update-stack \
    --stack-name $StackName \
    --template-body file://$CFN_STACKSET_EXEC_ROLE \
    --tags  file://$CFN_TAGS_FILE \
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

    # echo ""
    # echo "Granting new account access to EventBus"
    # echo "--------------"
    # echo ""
    # To allow to send to central EventBus
    # aws --profile $SECLOG events put-permission --action events:PutEvents --principal $accountId --statement-id $SECLOG



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
    --tags file://$CFN_TAGS_FILE \
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
    --tags file://$CFN_TAGS_FILE \
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
    --tags file://$CFN_TAGS_FILE \
    --capabilities CAPABILITY_NAMED_IAM \
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
    --tags file://$CFN_TAGS_FILE \
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
    --tags file://$CFN_TAGS_FILE \
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
    --tags file://$CFN_TAGS_FILE \
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
