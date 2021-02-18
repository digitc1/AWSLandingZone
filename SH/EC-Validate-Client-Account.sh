#!/bin/bash -e

#   --------------------------------------------------------
#
#			Automates the following:
#			- Validate an AWS account
#
#			Prerequesites:
#			-
#
#			Usage:
#			$ ./EC-Validate-Client-Account.sh $CLIENT $SECLOG
#
#			ex:
#			$ ./EC-Validate-Client-Account.sh D2_newAcc1 D2_seclog
#
#
#   Version History
#
#   v1.0  Alexandre Levret   Initial Version
#
#   --------------------------------------------------------

#	  -------------
#	  Parameters
#	  -------------

export CLIENT=$1
export SECLOG=$2
export CLIENT_ACC_ID=`aws --profile $CLIENT sts get-caller-identity  --query 'Account' --output text`
export SECLOG_ACC_ID=`aws --profile $SECLOG sts get-caller-identity  --query 'Account' --output text`


# Check if account is created under the organization
function check_acc_created {

	#	Tests the account is active and has the right Master AWS Account

	ACC_ID=$1
	MASTER_ACC_ID=`aws sts get-caller-identity  --query 'Account' --output text`

	echo "Checking AWS Account configuration..."

	ACC_STATUS=$(aws organizations list-accounts --query "Accounts[?Id=='$ACC_ID'].Status" --output text)
	ACC_ARN=$(aws organizations list-accounts --query "Accounts[?Id=='$ACC_ID'].Arn" --output text)

	if [[ "$ACC_STATUS" == "ACTIVE" && "$ACC_ARN" == *"${MASTER_ACC_ID}"* ]]; then

		echo "PASSED (Status:$ACC_STATUS and Arn:$ACC_ARN)"

	else

		echo "FAILED (Status:$ACC_STATUS and Arn:$ACC_ARN)"
		exit 1

	fi

}

#Check if guardduty is enabled and linked to the seclog account
function check_gd_config {

	#	Tests the Guard Duty Status is enabled and has the right Master AWS Account

	CLIENT_ACC_ID=$1
	SECLOG_ACC_ID=$2

	echo "Checking Guard Duty configuration..."

	GD_DETECTOR_ID=`aws --profile $SECLOG guardduty list-detectors --query "DetectorIds" --output text`
	GD_STATUS=`aws --profile $SECLOG guardduty list-members --detector-id $GD_DETECTOR_ID --query "Members[?AccountId=='$CLIENT_ACC_ID'].RelationshipStatus" --output text`
	GD_MASTER=`aws --profile $SECLOG guardduty list-members --detector-id $GD_DETECTOR_ID --query "Members[?AccountId=='$CLIENT_ACC_ID'].MasterId" --output text`

	if [[ "$GD_STATUS" == "Enabled" && "$GD_MASTER" == "$SECLOG_ACC_ID" ]]; then

			echo "PASSED (Status:$GD_STATUS and Seclog Master: $GD_MASTER)"

	else

			echo "FAILED (Status:$GD_STATUS and Seclog Master: $GD_MASTER)"
			exit 1

	fi

}

#Check if securityhub is enabled and linked to the seclog account
function check_sechub_config {

	#	Tests the Security Hub.... code TBC :)

	CLIENT_ACC_ID=$1

	echo "Checking Security Hub configuration..."

	SH_STATUS=`aws --profile $SECLOG securityhub list-members --query "Members[?AccountId=='$CLIENT_ACC_ID'].MemberStatus" --output text`
	SH_MASTER=`aws --profile $SECLOG securityhub list-members --query "Members[?AccountId=='$CLIENT_ACC_ID'].MasterId" --output text`

	if [[ "$SH_STATUS" == "Enabled" && "$SH_MASTER" == "$SECLOG_ACC_ID" ]]; then

		echo "PASSED (Status:$SH_STATUS and Seclog Master: $SH_MASTER)"

	else

		echo "FAILED (Status:$SH_STATUS and Seclog Master: $SH_MASTER)"
		exit 1

	fi

}

#Check if Config is enabled and if the account is part of the SecLog Config aggregator
function check_configservice_config {

	CLIENT_ACC_ID=$1
	SECLOG_ACC_ID=$2

	echo "Checking Config configuration..."

	CONFIG_REC_NAME=`aws --profile $CLIENT configservice describe-configuration-recorders --output text --query 'ConfigurationRecorders[*].name'`

	if [ "$CONFIG_REC_NAME" == "lz-config-logging-recorder" ]; then

		echo "PASSED (Config is enabled on this account: $CLIENT_ACC_ID)"

		AUTHORIZED_ACC_ID=`aws --profile $CLIENT configservice describe-aggregation-authorizations --output text --query 'AggregationAuthorizations[*].AuthorizedAccountId'`

		if [ "$AUTHORIZED_ACC_ID" == "$SECLOG_ACC_ID" ]; then

			echo "PASSED (SecLog account $SECLOG_ACC_ID aggregates data from Client account $CLIENT_ACC_ID)"

		else

			echo "FAILED (SecLog account $SECLOG_ACC_ID doesn't aggregate data from Client account $CLIENT_ACC_ID)"
			exit 1

		fi

	else

		echo "FAILED (Config is not enabled on this account: $CLIENT_ACC_ID)"
		exit 1

	fi

}

#Check if the SNS topic is well created
function check_sns_topic {

	echo "Checking SNS configuration..."

	SNS_TOPIC_ARN=`aws --profile $SECLOG sns list-topics --output text --query 'Topics[0].TopicArn'`

	SNS_MESSAGE_ID=`aws --profile $CLIENT sns publish --topic-arn $SNS_TOPIC_ARN --message "Checking SNS Topic via email ..."`

	if [ -z "$SNS_MESSAGE_ID" ]; then

		echo "FAILED (SNS Topic is not sending any email)"
		exit 1

	else

		echo "PASSED (SNS Topic is able to send email)"

	fi

}



echo ""
echo "========================"
echo "VALIDATING CONFIGURATION"
echo ""

echo "Client Account ID: $CLIENT_ACC_ID"
echo "Seclog Account ID: $SECLOG_ACC_ID"
echo ""

#	Check account created and in Org OK
#check_acc_created $CLIENT_ACC_ID
echo ""

#	Check for correct Guard Duty Configuration
check_gd_config $CLIENT_ACC_ID $SECLOG_ACC_ID
echo ""

#	Check for correct Security Hub Configuration
check_sechub_config $CLIENT_ACC_ID $SECLOG_ACC_ID
echo ""

#	Check for correct Config Configuration
check_configservice_config $CLIENT_ACC_ID $SECLOG_ACC_ID
echo ""

#	Check for correct SNS Topic Configuration
check_sns_topic
echo ""

echo ""
echo "VALIDATION COMPLETED"
echo "===================="
echo ""
