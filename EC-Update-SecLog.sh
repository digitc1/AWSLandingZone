#!/bin/bash

#   --------------------------------------------------------
#
#			Automates the following:
#			- updates existing landing zone to push logs and alerts to C2 Splunk logs destinations 
#
#			Usage
#
#			$ ./EC-Update-SecLog-Splunk.sh [--organisation <Org Account Profile>] --seclogprofile <Seclog Acc Profile> --splunkprofile <Splunk Acc Profile>  --notificationemail <Notification Email> --logdestination <Log Destination DG name>  [--batch <true|false>]
#
#			
#
#
#
#   Version History
#
#   v1.0.0  João Silva  Initial Version
#   v1.1.0  João Silva  Updates to cater for parameter based conditionality or resource installation
#   v1.1.1  João Silva  Updated instructions
#   --------------------------------------------------------

#       --------------------
#       Parameters
#       --------------------

organisation=${organisation:-}
seclogprofile=${seclogprofile:-}
splunkprofile=${splunkprofile:-}
logdestination=${logdestination:-}
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

# parameters for scripts

CFN_BUCKETS_TEMPLATE='CFN/EC-lz-s3-buckets.yml'
CFN_TAGS_PARAMS_FILE='CFN/EC-lz-TAGS-params.json'
CFN_LOG_TEMPLATE='CFN/EC-lz-config-cloudtrail-logging.yml'
CFN_GUARDDUTY_DETECTOR_TEMPLATE='CFN/EC-lz-guardDuty-detector.yml'
CFN_SECURITYHUB_LOG_TEMPLATE='CFN/EC-lz-config-securityhub-logging.yml'
CFN_NOTIFICATIONS_CT_TEMPLATE='CFN/EC-lz-notifications.yml'
CFN_STACKSET_CONFIG_SECHUB_GLOBAL='CFN/EC-lz-Config-SecurityHub-all-regions.yml'

#   ---------------------
#   The command line help
#   ---------------------
display_help() {
    echo "Usage: $0 [--organisation <Org Account Profile>] --seclogprofile <Seclog Acc Profile> --splunkprofile <Splunk Acc Profile>  --notificationemail <Notification Email> --logdestination <Log Destination DG name>  [--batch <true|false>]" >&2
    echo ""
    echo "   Provide "
    echo "   --organisation       : The orgnisation account as configured in your AWS profile (optional)"
    echo "   --seclogprofile      : The account profile of the central SecLog account as configured in your AWS profile"
    echo "   --splunkprofile      : The Splunk account profile as configured in your AWS profile"
    echo "   --notificationemail  : The notification email to where logs are to be sent"
    echo "   --logdestination     : The name of the DG of the firehose log destination"
    echo "   --batch              : Flag to enable or disable batch execution mode. Default: false (optional)"
    echo ""
    exit 1
}

update_seclog() {

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

    # Getting C2 Splunk Account Id
    SPLUNK_ACCOUNT_ID=`aws --profile $splunkprofile sts get-caller-identity --query 'Account' --output text`

    # Getting available log destinations from 
    DESCRIBE_DESTINATIONS=`aws --profile $splunkprofile  logs describe-destinations`

    # Extract select Log destination details
    FIREHOSE_ARN=`echo $DESCRIBE_DESTINATIONS | jq -r '.destinations[]| select (.destinationName | contains("'$logdestination'")) .arn'`
    FIREHOSE_DESTINATION_NAME=`echo $DESCRIBE_DESTINATIONS | jq -r '.destinations[]| select (.destinationName | contains("'$logdestination'")) .destinationName'`
    FIREHOSE_ACCESS_POLICY=`echo $DESCRIBE_DESTINATIONS | jq -r '.destinations[]| select (.destinationName | contains("'$logdestination'")) .accessPolicy'`

    echo ""
    echo "- This script will configure a the SecLog account with following settings:"
    echo "   ----------------------------------------------------"
    echo "     SecLog Account to be configured:  $seclogprofile"
    echo "     SecLog Account Id:                $SECLOG_ACCOUNT_ID"
    echo "     Splunk Account Id:                $SPLUNK_ACCOUNT_ID"
    echo "     Security Notifications e-mail:    $notificationemail"
    echo "     Log Destination Name:             $FIREHOSE_DESTINATION_NAME"
    echo "     Log Destination ARN:              $FIREHOSE_ARN"
    echo "     in AWS Region:                    $AWS_REGION"
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
    echo "   - /org/member/SecLog_notification-mail"

    aws --profile $seclogprofile ssm put-parameter --name /org/member/SecLog_notification-mail --type String --value $notificationemail --overwrite
    aws --profile $seclogprofile ssm put-parameter --name /org/member/SecLogMasterAccountId --type String --value $SECLOG_ACCOUNT_ID --overwrite


    #	------------------------------------
    #	 Updates the policy that defines write access to the log destination on the C2 SPLUNK account
    #	------------------------------------

    echo ""
    echo "- Updates the policy that defines write access to the log destination"
    echo "--------------------------------------------------"
    echo ""

    echo $FIREHOSE_ACCESS_POLICY | jq '.Statement[0].Principal.AWS = (.Statement[0].Principal.AWS | if type == "array" then . += ["'$SECLOG_ACCOUNT_ID'", "'$ORG_ACCOUNT_ID'"] else [.,"'$SECLOG_ACCOUNT_ID'", "'$ORG_ACCOUNT_ID'"] end)' > ./SecLogAccessPolicy.json  

    aws logs put-destination-policy \
    --destination-name $FIREHOSE_DESTINATION_NAME \
    --profile $splunkprofile \
    --access-policy file://./SecLogAccessPolicy.json

    rm -f ./SecLogAccessPolicy.json

    sleep 5

    #   ------------------------------------
    #   Creating config, cloudtrail, SNS notifications
    #   ------------------------------------


    echo ""
    echo "- Creating config, cloudtrail, SNS notifications"
    echo "--------------------------------------------------"
    echo ""

    aws cloudformation update-stack \
    --stack-name 'SECLZ-config-cloudtrail-SNS' \
    --template-body file://$CFN_LOG_TEMPLATE \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $seclogprofile \
    --parameters ParameterKey=FirehoseDestinationArn,ParameterValue=$FIREHOSE_ARN

    StackName="SECLZ-config-cloudtrail-SNS"
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "UPDATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    sleep 5

    #   ------------------------------------
    #   Enable guardduty and securityhub in seclog master account
    #   ------------------------------------


    echo "" 
    echo "- Enable guardduty in seclog master account"
    echo "--------------------"
    echo ""

    aws cloudformation update-stack \
    --stack-name 'SECLZ-Guardduty-detector' \
    --template-body file://$CFN_GUARDDUTY_DETECTOR_TEMPLATE \
    --capabilities CAPABILITY_IAM \
    --profile $seclogprofile \
    --parameters ParameterKey=FirehoseDestinationArn,ParameterValue=$FIREHOSE_ARN

    sleep 5

	#   ------------------------------------
	#   Enable Cloudwatch Event Rules to Cloudwatch logs for Security Hub
	#   ------------------------------------


	echo ""
	echo "- Enable Cloudwatch Event Rules to Cloudwatch logs for Security Hub"
	echo "---------------------------------------"
	echo ""

	aws cloudformation update-stack \
	--stack-name 'SECLZ-CloudwatchLogs-SecurityHub' \
	--template-body file://$CFN_SECURITYHUB_LOG_TEMPLATE \
    --capabilities CAPABILITY_IAM \
	--profile $seclogprofile \
    --parameters ParameterKey=FirehoseDestinationArn,ParameterValue=$FIREHOSE_ARN 

	StackName="SECLZ-CloudwatchLogs-SecurityHub"
	aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
	while [ `aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` = "UPDATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
	aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    sleep 5

    #   ------------------------------------
    #   Enable Notifications for CIS cloudtrail metrics filters
    #   ------------------------------------


    echo ""
    echo "- Enable Notifications for CIS cloudtrail metrics filters"
    echo "---------------------------------------"
    echo ""

    aws cloudformation update-stack \
    --stack-name 'SECLZ-Notifications-Cloudtrail' \
    --template-body file://$CFN_NOTIFICATIONS_CT_TEMPLATE \
    --profile $seclogprofile

    StackName="SECLZ-Notifications-Cloudtrail"
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "UPDATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    sleep 5
    
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

    sleep 5



    #   ------------------------------------
    #   Enable Config and SecurityHub globally using stacksets
    #   ------------------------------------

    # Create StackSet (Enable Config and SecurityHub globally)
    aws cloudformation update-stack-set \
    --stack-set-name 'SECLZ-Enable-Config-SecurityHub-Globally' \
    --template-body file://$CFN_STACKSET_CONFIG_SECHUB_GLOBAL \
    --parameters ParameterKey=SecLogMasterAccountId,ParameterValue=$SECLOG_ACCOUNT_ID \
    --capabilities CAPABILITY_IAM \
    --profile $seclogprofile

    # Create StackInstances (globally except Ireland)
    # aws cloudformation update-stack-instances \
    # --stack-set-name 'SECLZ-Enable-Config-SecurityHub-Globally' \
    # --accounts $SECLOG_ACCOUNT_ID \
    # --parameter-overrides ParameterKey=SecLogMasterAccountId,ParameterValue=$SECLOG_ACCOUNT_ID \
    # --regions $ALL_REGIONS_EXCEPT_IRELAND \
    # --operation-preferences FailureToleranceCount=3,MaxConcurrentCount=5 \
    # --profile $seclogprofile
}

# ---------------------------------------------
# Check if correct options are given
# on the commandline and start configurations
# ---------------------------------------------

# Simple check if two arguments are provided
if [ -z "$seclogprofile" ] || [ -z "$splunkprofile" ]  || [ -z "$logdestination" ] || [ -z "$notificationemail" ]; then
    display_help
    exit 0
fi

#start account configuration
update_seclog
