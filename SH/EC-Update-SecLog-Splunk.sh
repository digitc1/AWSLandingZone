#!/bin/bash

#   --------------------------------------------------------
#
#			Automates the following:
#			- updates existing landing zone to push logs and alerts to C2 Splunk logs destinations 
#
#			Usage
#
#			$ ./EC-Update-SecLog-Splunk.sh ORG_PROFILE SECLOG_PROFILE SPLUNK_PROFILE LOG_DESTINATION_NAME
#
#			ex:
#			$ ./EC-Sanitize-Account.sh  D3_Acc1 D3_seclog EC_DIGIT_C2-SPLUNK dgtest
#
#
#
#   Version History
#
#   v1.0  João Silva  Initial Version
#   --------------------------------------------------------

#       --------------------
#       Parameters
#       --------------------

ORG_PROFILE=$1
SECLOG_PROFILE=$2
SPLUNK_PROFILE=$3
ACC_EMAIL_SecNotifications SECLOG_NOTIF_EMAIL=$4
LOG_DESTINATION_NAME=$5

# Script Spinner waiting for cloudformation completion
export i=1
export sp="/-\|"

AWS_REGION='eu-west-1'
ALL_REGIONS_EXCEPT_IRELAND='["ap-northeast-1","ap-northeast-2","ap-south-1","ap-southeast-1","ap-southeast-2","ca-central-1","eu-central-1","eu-west-2","eu-west-3","sa-east-1","us-east-1","us-east-2","us-west-1","us-west-2"]'

# parameters for scripts
CFN_LOG_TEMPLATE='CFN/EC-lz-config-cloudtrail-logging.yml'
CFN_GUARDDUTY_DETECTOR_TEMPLATE='CFN/EC-lz-guardDuty-detector.yml'
CFN_SECURITYHUB_LOG_TEMPLATE='CFN/EC-lz-config-securityhub-logging.yml'


#   ---------------------
#   The command line help
#   ---------------------
display_help() {
    echo "Usage: $0 ORG_PROFILE SECLOG_PROFILE SPLUNK_PROFILE LOG_DESTINATION_NAME" >&2
    echo
    echo "   Provide an account name to configure, account name of the central SecLog account as configured in your AWS profile,"
    echo "   account name for the Splunk log destination as in your AWS profile and the name of the DG of the firehose log destination"
    exit 1
}

config_all_regions() {

    # Get organizations Identity
    ORG_ACCOUNT_ID=`aws --profile $ORG_PROFILE sts get-caller-identity --query 'Account' --output text`

    #getting organization ouId
    ORG_OU_ID=`aws --profile $ORG_PROFILE organizations describe-organization --query '[Organization.Id]' --output text`

    # Getting SecLog Account Id
    SECLOG_ACCOUNT_ID=`aws --profile $SECLOG_PROFILE sts get-caller-identity --query 'Account' --output text`

    # Getting C2 Splunk Account Id
    SPLUNK_ACCOUNT_ID=`aws --profile $SPLUNK_PROFILE sts get-caller-identity --query 'Account' --output text`

    # Getting available log destinations from 
    DESCRIBE_DESTINATIONS=`aws --profile $SPLUNK_PROFILE  logs describe-destinations`

    # Extract select Log destination details
    FIREHOSE_ARN=`echo $DESCRIBE_DESTINATIONS | jq -r '.destinations[]| select (.destinationName | contains("'$LOG_DESTINATION_NAME'")) .arn'`
    FIREHOSE_DESTINATION_NAME=`echo $DESCRIBE_DESTINATIONS | jq -r '.destinations[]| select (.destinationName | contains("'$LOG_DESTINATION_NAME'")) .destinationName'`
    FIREHOSE_ACCESS_POLICY=`echo $DESCRIBE_DESTINATIONS | jq -r '.destinations[]| select (.destinationName | contains("'$LOG_DESTINATION_NAME'")) .accessPolicy'`

    echo ""
    echo "- This script will configure a the SecLog account with following settings:"
    echo "   ----------------------------------------------------"
    echo "     SecLog Account to be configured:  $SECLOG_PROFILE"
    echo "     SecLog Account Id:                $SECLOG_ACCOUNT_ID"
    echo "     Splunk Account Id:                $SPLUNK_ACCOUNT_ID"
    echo "     Log Destination Name:             $FIREHOSE_DESTINATION_NAME"
    echo "     Log Destination ARN:              $FIREHOSE_ARN"
    echo "     in AWS Region:                    $AWS_REGION"
    echo "   ----------------------------------------------------"
    echo ""
    echo "   If this is correct press enter to continue"
    read -p "  or CTRL-C to break"


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
    --profile $SPLUNK_PROFILE \
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
    --enable-termination-protection \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $SECLOG_PROFILE
    --parameters ParameterKey=FirehoseDestinationArn,ParameterValue=$FIREHOSE_ARN

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

    aws cloudformation update-stack \
    --stack-name 'SECLZ-Guardduty-detector' \
    --template-body file://$CFN_GUARDDUTY_DETECTOR_TEMPLATE \
    --enable-termination-protection \
    --capabilities CAPABILITY_IAM \
    --profile $SECLOG_PROFILE
    --parameters ParameterKey=FirehoseDestinationArn,ParameterValue=$FIREHOSE_ARN

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
	--profile $SECLOG_PROFILE \
    --parameters ParameterKey=FirehoseDestinationArn,ParameterValue=$FIREHOSE_ARN 

	StackName="SECLZ-CloudwatchLogs-SecurityHub"
	aws --profile $SECLOG_PROFILE cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
	while [ `aws --profile $SECLOG_PROFILE cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` = "CREATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
	aws --profile $SECLOG_PROFILE cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    sleep 5

    
}

# ---------------------------------------------
# Check if correct options are given
# on the commandline and start configurations
# ---------------------------------------------

# Simple check if two arguments are provided
if [ -z $4 ]; then
    display_help  # Call your function
    exit 0
fi

#start account configuration
update_seclog
