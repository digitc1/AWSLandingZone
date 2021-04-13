#!/bin/bash

#   --------------------------------------------------------
#
#       Automates the following:
#       - Deployment of central buckets for cloudtrail/config/access_logs
#       - Setup cloudtrail, config and creates an SNS topic
#       - Enables Guardduty and Guardduty notifications to SNS
#       - Enables Security Hub
#       - Enable Cloudwatch Event Rules to Cloudwatch logs for Security Hub
#       - Deploys CIS notifications for Cloudtrail based on cloudwatch log metric filters
#       - Sets password policy for IAM
#       - Sets the Firehose subscription log destination
#
#       Usage
#       $  ./EC-Configure-SecLog-Account.sh [--organisation <Org Account Profile>] --seclogprofile <Seclog Acc Profile> --splunkprofile <Splunk Acc Profile> --notificationemail <Notification Email> --logdestination <Log Destination DG name> [--cloudtrailintegration <true|false] --guarddutyintegration [true|false>] [--securityhubintegration <true|false>] [--batch <true|false>]
#
#   Version History
#
#   v1.0      J. Vandenbergen   Initial Version
#   v1.0.1    L. Leonard        Version dedicated to EC-BROKER-IAM
#   v1.0.2    J. Silva          Add Cloudwatch Event Rules to Cloudwatch logs for Security Hub 
#   v1.0.3    J. Silva          Add Splunk log destinations for Cloudwatch logs
#   v1.1.0    J. Silva          Made log integration with Splunk optional.
#   v1.1.0    J. Silva          Made log integration with Splunk optional.
#   --------------------------------------------------------

#   --------------------
#       Parameters
#   --------------------

organisation=${organisation:-}
seclogprofile=${seclogprofile:-}
splunkprofile=${splunkprofile:-}
notificationemail=${notificationemail:-}
logdestination=${logdestination:-}
cloudtrailintegration=${cloudtrailintegration:-true}
guarddutyintegration=${guarddutyintegration:-true}
securityhubintegration=${securityhubintegration:-true}
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
ALL_REGIONS_EXCEPT_IRELAND='["ap-northeast-1","ap-northeast-2","ap-south-1","ap-southeast-1","ap-southeast-2","ca-central-1","eu-central-1","eu-north-1","eu-west-2","eu-west-3","sa-east-1","us-east-1","us-east-2","us-west-1","us-west-2"]'


# get version number
LZ_VERSION=`cat EC-SLZ-Version.txt | xargs`

# parameters for scripts
CFN_BUCKETS_TEMPLATE='CFN/EC-lz-s3-buckets.yml'
CFN_LAMBDAS_TEMPLATE='CFN/EC-lz-logshipper-lambdas.yml'
CFN_LAMBDAS_BUCKET_TEMPLATE='CFN/EC-lz-s3-bucket-lambda-code.yml'
CFN_GUARDDUTY_TEMPLATE_GLOBAL='CFN/EC-lz-Config-Guardduty-all-regions.yml'
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
CFN_SECURITYHUB_LOG_TEMPLATE='CFN/EC-lz-config-securityhub-logging.yml'


#   ---------------------
#   The command line help
#   ---------------------
display_help() {

    echo "Landing Zone installation script for SECLOG account version $LZ_Version"
    echo ""
    echo "Usage: $0 [--organisation <Org Account Profile>] --seclogprofile <Seclog Acc Profile> --splunkprofile <Splunk Acc Profile> --notificationemail <Notification Email> --logdestination <Log Destination DG name> [--cloudtrailintegration <true|false] [--guarddutyintegration <true|false>] [--securityhubintegration <true|false>] [--batch <true|false>]"
    echo ""
    echo "   Provide "
    echo "   --organisation           : The orgnisation account as configured in your AWS profile (optional)"
    echo "   --seclogprofile          : The account profile of the central SecLog account as configured in your AWS profile"
    echo "   --splunkprofile          : The Splunk account profile as configured in your AWS profile"
    echo "   --notificationemail      : The notification email to where logs are to be sent"
    echo "   --logdestination         : The name of the DG of the firehose log destination"
    echo "   --cloudtrailintegration  : Flag to enable or disable CloudTrail seclog integration. Default: true (optional)"
    echo "   --guarddutyintegration   : Flag to enable or disable GuardDuty seclog integration. Default: true (optional)"
    echo "   --securityhubintegration : Flag to enable or disable SecurityHub seclog integration. Default: true (optional)"
    echo "   --batch                  : Flag to enable or disable batch execution mode. Default: false (optional)"
    echo ""
    exit 1
}

#   ----------------------------
#   Configure Seclog Account
#   ----------------------------
configure_seclog() {
    
    ORG_ACCOUNT_ID=''
    ORG_OU_ID=''
    
    if [ -z "$organisation" ] ; then
        ORG_ACCOUNT_ID='246933597933'
        ORG_OU_ID='o-jyyw8qs5c8'
    else 
        # Get organizations Identity
        ORG_ACCOUNT_ID=`aws --profile $organisation sts get-caller-identity --query 'Account' --output text`
        #getting organization ouId
        ORG_OU_ID=`aws --profile $organisation organizations describe-organization --query '[Organization.Id]' --output text`
    fi
    # Getting SecLog Account Id
    SECLOG_ACCOUNT_ID=`aws --profile $seclogprofile sts get-caller-identity --query 'Account' --output text`

    if [ "$cloudtrailintegration" == "true" ] || [ "$guarddutyintegration" == "true" ] || [ "$securityhubintegration" == "true" ]; then
        # Getting C2 Splunk Account Id
        SPLUNK_ACCOUNT_ID=`aws --profile $splunkprofile sts get-caller-identity --query 'Account' --output text`

        # Getting available log destinations from
        DESCRIBE_DESTINATIONS=`aws --profile $splunkprofile  logs describe-destinations`

        # Extract select Log destination details
        FIREHOSE_ARN=`echo $DESCRIBE_DESTINATIONS | jq -r '.destinations[]| select (.destinationName | contains("'$logdestination'")) .arn'`
        FIREHOSE_DESTINATION_NAME=`echo $DESCRIBE_DESTINATIONS | jq -r '.destinations[]| select (.destinationName | contains("'$logdestination'")) .destinationName'`
        FIREHOSE_ACCESS_POLICY=`echo $DESCRIBE_DESTINATIONS | jq -r '.destinations[]| select (.destinationName | contains("'$logdestination'")) .accessPolicy'`
    fi

    echo ""
    echo "- This script will configure a the SecLog account with following settings:"
    echo "   ----------------------------------------------------"
    echo "     Landing Zone script version:         $LZ_VERSION"
    echo "     SecLog Account to be configured:     $seclogprofile"
    echo "     SecLog Account Id:                   $SECLOG_ACCOUNT_ID"
    echo "     Security Notifications e-mail:       $notificationemail"
    echo "     CloudTrail integration with Splunk:  $cloudtrailintegration"
    echo "     GuardDuty integration with Splunk:   $guarddutyintegration"
    echo "     SecurityHub integration with Splunk: $securityhubintegration"
    if [[ ("$cloudtrailintegration" == "true" || "$guarddutyintegration" == "true" || "$securityhubintegration" == "true" ) ]]; then
      echo "     Splunk Account Id:                   $SPLUNK_ACCOUNT_ID"
      echo "     Log Destination Name:                $FIREHOSE_DESTINATION_NAME"
      echo "     Log Destination ARN:                 $FIREHOSE_ARN"
    fi
    echo "     in AWS Region:                       $AWS_REGION"
    echo "   ----------------------------------------------------"
    echo ""
    if [ "$batch" == "false" ] ; then
        echo "   If this is correct press enter to continue"
        read -p "  or CTRL-C to break"
    fi
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
    echo "    - /org/member/SecLogVersion"
    
    aws --profile $seclogprofile ssm put-parameter --name /org/member/SecLog_notification-mail --type String --value $notificationemail --overwrite
    aws --profile $seclogprofile ssm put-parameter --name /org/member/SecLogMasterAccountId --type String --value $SECLOG_ACCOUNT_ID --overwrite
    aws --profile $seclogprofile ssm put-parameter --name /org/member/SecLogOU --type String --value $ORG_OU_ID --overwrite
    aws --profile $seclogprofile ssm put-parameter --name /org/member/SLZVersion --type String --value $LZ_VERSION --overwrite

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
    --profile $seclogprofile

    # ExecutionRole
    aws cloudformation create-stack \
    --stack-name SECLZ-StackSetExecutionRole \
    --template-body file://$CFN_STACKSET_EXEC_ROLE \
    --enable-termination-protection \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $seclogprofile

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
    --profile $seclogprofile

    StackName=SECLZ-Cloudtrail-KMS
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "CREATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    sleep 5

    # Getting KMS key encryption arn
    KMS_KEY_ARN=`aws --profile $seclogprofile ssm get-parameter --name "/org/member/KMSCloudtrailKey_arn" --output text --query 'Parameter.Value'`

    #Storing the KMSCloudTrailKeyArn into SSM Parameter Store
    aws --profile $seclogprofile ssm put-parameter --name /org/member/KMSCloudtrailKey_arn --type String --value $KMS_KEY_ARN --overwrite &>/dev/null


    #   ------------------------------------
    #   Logshipper lambdas for CloudTrail and AWSConfig ...
    #   ------------------------------------

    echo ""
    echo "- Logshipper lambdas for CloudTrail and AWSConfig ... "
    echo "-----------------------------------------------------------"
    echo ""

    
    REPO="lambda-artefacts-$SECLOG_ACCOUNT_ID"

    aws cloudformation create-stack \
    --stack-name 'SECLZ-LogShipper-Lambdas-Bucket' \
    --template-body file://$CFN_LAMBDAS_BUCKET_TEMPLATE \
    --capabilities CAPABILITY_NAMED_IAM \
    --enable-termination-protection \
    --profile $seclogprofile
    
    StackName=SECLZ-LogShipper-Lambdas-Bucket
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "CREATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName


    NOW=`date +"%d%m%Y"`
    LOGSHIPPER_TEMPLATE="EC-lz-logshipper-lambdas-packaged.yml"
    LOGSHIPPER_TEMPLATE_WITH_CODE="EC-lz-logshipper-lambdas.yml"
    CLOUDTRAIL_LAMBDA_CODE="CloudtrailLogShipper-$NOW.zip"
    CONFIG_LAMBDA_CODE="ConfigLogShipper-$NOW.zip"

    zip -j $CLOUDTRAIL_LAMBDA_CODE LAMBDAS/CloudtrailLogShipper.py
    zip -j $CONFIG_LAMBDA_CODE LAMBDAS/ConfigLogShipper.py

    
    awk -v cl=$CLOUDTRAIL_LAMBDA_CODE -v co=$CONFIG_LAMBDA_CODE '{ sub(/##cloudtrailCodeURI##/,cl);gsub(/##configCodeURI##/,co);print }' $CFN_LAMBDAS_TEMPLATE > $LOGSHIPPER_TEMPLATE_WITH_CODE

    aws cloudformation package --template $LOGSHIPPER_TEMPLATE_WITH_CODE --s3-bucket $REPO --output-template-file $LOGSHIPPER_TEMPLATE --profile $seclogprofile

    aws cloudformation deploy --stack-name  'SECLZ-LogShipper-Lambdas' \
    --template-file $LOGSHIPPER_TEMPLATE \
    --capabilities CAPABILITY_IAM \
    --profile $seclogprofile


    StackName=SECLZ-LogShipper-Lambdas
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    
    aws cloudformation update-termination-protection \
        --enable-termination-protection \
        --stack-name $StackName \
        --profile $seclogprofile

    rm -rf $LOGSHIPPER_TEMPLATE
    rm -rf $LOGSHIPPER_TEMPLATE_WITH_CODE
    rm -rf $CLOUDTRAIL_LAMBDA_CODE
    rm -rf $CONFIG_LAMBDA_CODE

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
    --profile $seclogprofile

    StackName=SECLZ-Central-Buckets
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "CREATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

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
    --profile $seclogprofile

    StackName="SECLZ-Iam-Password-Policy"
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "CREATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    if [ $cloudtrailintegration == "true" ] || [ $guarddutyintegration == "true" ] || [ $securityhubintegration == "true" ]; then
        sleep 5

        #	------------------------------------
        #	 Creates a policy that defines write access to the log destination on the C2 SPLUNK account
        #	------------------------------------

        echo ""
        echo "- Creates a policy that defines write access to the log destination"
        echo "--------------------------------------------------"
        echo ""

        echo $FIREHOSE_ACCESS_POLICY | jq '.Statement[0].Principal.AWS = (.Statement[0].Principal.AWS | if type == "array" then . += ["'$SECLOG_ACCOUNT_ID'", "'$ORG_ACCOUNT_ID'"] else [.,"'$SECLOG_ACCOUNT_ID'", "'$ORG_ACCOUNT_ID'"] end)' > ./SecLogAccessPolicy.json  

        aws logs put-destination-policy \
        --destination-name $FIREHOSE_DESTINATION_NAME \
        --profile $splunkprofile \
        --access-policy file://./SecLogAccessPolicy.json

        rm -f ./SecLogAccessPolicy.json
    fi

    sleep 5

    #   ------------------------------------
    #   Creating config, cloudtrail, SNS notifications
    #   ------------------------------------


    echo ""
    echo "- Creating config, cloudtrail, SNS notifications"
    echo "--------------------------------------------------"
    echo ""

    cloudtrailparams="ParameterKey=EnableSecLogForCloudTrailParam,ParameterValue=$cloudtrailintegration"
    if [ "$cloudtrailintegration" == "true" ]; then
        cloudtrailparams="ParameterKey=FirehoseDestinationArn,ParameterValue=$FIREHOSE_ARN"
    fi


    aws cloudformation create-stack \
    --stack-name 'SECLZ-config-cloudtrail-SNS' \
    --template-body file://$CFN_LOG_TEMPLATE \
    --enable-termination-protection \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $seclogprofile \
    --parameters $cloudtrailparams

    StackName="SECLZ-config-cloudtrail-SNS"
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "CREATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    sleep 5

    #   ------------------------------------
    #   Enable cloudtrail insights in seclog master account
    #   ------------------------------------

    echo ""
    echo "-  Enable cloudtrail insights in seclog master account"
    echo "--------------------------------------------------"
    echo ""

    aws --profile $seclogprofile cloudtrail put-insight-selectors --trail-name lz-cloudtrail-logging --insight-selectors '[{"InsightType": "ApiCallRateInsight"}]'


    #   ------------------------------------
    #   Enable guardduty and securityhub in seclog master account
    #   ------------------------------------


    echo ""
    echo "- Enable guardduty in seclog master account"
    echo "--------------------"
    echo ""

    guarddutyparams="ParameterKey=EnableSecLogIntegrationFoGuardDutyParam,ParameterValue=$guarddutyintegration"
    if [ "$guarddutyintegration" == "true" ]; then
        guarddutyparams="ParameterKey=FirehoseDestinationArn,ParameterValue=$FIREHOSE_ARN"
    fi

    aws cloudformation create-stack \
    --stack-name 'SECLZ-Guardduty-detector' \
    --template-body file://$CFN_GUARDDUTY_DETECTOR_TEMPLATE \
    --enable-termination-protection \
    --capabilities CAPABILITY_IAM \
    --profile $seclogprofile \
    --parameters $guarddutyparams

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
    --profile $seclogprofile

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
    --profile $seclogprofile

    StackName="SECLZ-Notifications-Cloudtrail"
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "CREATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    if  [ "$securityhubintegration" == "true" ]; then
        sleep 5
        
        #   ------------------------------------
        #   Enable Cloudwatch Event Rules to Cloudwatch logs for Security Hub
        #   ------------------------------------


        echo ""
        echo "- Enable Cloudwatch Event Rules to Cloudwatch logs for Security Hub"
        echo "---------------------------------------"
        echo ""

        aws cloudformation create-stack \
        --stack-name 'SECLZ-CloudwatchLogs-SecurityHub' \
        --template-body file://$CFN_SECURITYHUB_LOG_TEMPLATE \
        --enable-termination-protection \
        --capabilities CAPABILITY_IAM \
        --profile $seclogprofile \
        --parameters ParameterKey=FirehoseDestinationArn,ParameterValue=$FIREHOSE_ARN

        StackName="SECLZ-CloudwatchLogs-SecurityHub"
        aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
        while [ `aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` = "CREATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
	    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    fi

    sleep 5

    #   ------------------------------------
    #   Set Resource Policy to send Events to LogGroups
    #   ------------------------------------

    echo ""
    echo "-  Set Resource Policy to send Events to LogGroups"
    echo "--------------------------------------------------"
    echo ""

    cat > ./policy.json << EOM
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TrustEventsToStoreLogEvent",
      "Effect": "Allow",
      "Principal": {
        "Service": ["events.amazonaws.com","delivery.logs.amazonaws.com"]
      },
      "Action": [
        "logs:PutLogEvents",
        "logs:CreateLogStream"
      ],
      "Resource": "arn:aws:logs:*:${SECLOG_ACCOUNT_ID}:log-group:/aws/events/*:*"
    }
  ]
}
EOM

    aws --profile $seclogprofile logs put-resource-policy --policy-name TrustEventsToStoreLogEvents --policy-document file://./policy.json
    rm ./policy.json

    sleep 5

    #   ------------------------------------
    #   Enable Config and SecurityHub globally using stacksets
    #   ------------------------------------


    echo ""
    echo "-  Enable SecurityHub globally"
    echo "--------------------------------------------------"
    echo ""


    # Create StackSet (Enable Config and SecurityHub globally)
    aws cloudformation create-stack-set \
    --stack-set-name 'SECLZ-Enable-Config-SecurityHub-Globally' \
    --template-body file://$CFN_STACKSET_CONFIG_SECHUB_GLOBAL \
    --parameters ParameterKey=SecLogMasterAccountId,ParameterValue=$SECLOG_ACCOUNT_ID \
    --capabilities CAPABILITY_IAM \
    --profile $seclogprofile

    # Create StackInstances (globally except Ireland)
    aws cloudformation create-stack-instances \
    --stack-set-name 'SECLZ-Enable-Config-SecurityHub-Globally' \
    --accounts $SECLOG_ACCOUNT_ID \
    --parameter-overrides  ParameterKey=SecLogMasterAccountId,ParameterValue=$SECLOG_ACCOUNT_ID \
    --operation-preferences FailureToleranceCount=3,MaxConcurrentCount=5,RegionConcurrencyType=PARALLEL \
    --regions $ALL_REGIONS_EXCEPT_IRELAND \
    --profile $seclogprofile



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
    --operation-preferences FailureToleranceCount=3,MaxConcurrentCount=5,RegionConcurrencyType=PARALLEL \
    --regions $ALL_REGIONS_EXCEPT_IRELAND \
    --profile $seclogprofile


    echo "---------------------------------------------------------------------------------------------------------"
    echo "|                                         ATTENTION PLEASE:                                             |"
    echo "---------------------------------------------------------------------------------------------------------"
    echo "|                                                                                                       |"
    echo "|  Please check the installation of the stackset instances from the AWS console for the SECLOG account  |"
    echo "|  The moment all instances are deployed, please execute the 2nd stage of the LZ installation with the  |"
    echo "|  following command:                                                                                   |"
    echo "|                                                                                                       |"
    echo "|               sh ./SH/EC-Enable-SecurityHub-Controls-All-Regions.sh $seclogprofile                    |"
    echo "|                                                                                                       |"
    echo "---------------------------------------------------------------------------------------------------------"

}


# ---------------------------------------------
# Check if correct options are given
# on the commandline and start configurations
# ---------------------------------------------

# Check to validate number of parameters entered
if  [ -z "$seclogprofile" ] || [ -z "$notificationemail" ] ; then
    display_help
    exit 0
fi

if [[ ( -z "$logdestination" || -z "$splunkprofile" ) && ( "$cloudtrailintegration" == "true" ||  "$guarddutyintegration" == "true"  ||  "$securityhubintegration" == "true" ) ]]; then
    display_help
    exit 0
fi

# Simple check to see if 3rd argument looks like an e-mail address "@"
mail=`echo $notificationemail | sed -e s/.*@.*/@/g`

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
