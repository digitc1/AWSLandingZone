#!/bin/bash

#   --------------------------------------------------------
#
#	Automates the following:
#	- Sanitize an AWS account (new / existing) on different services to run in Secure Landing Zone Solution
#	- Sanitize AWS Config (Delete configuration recorder)
#	- Sanitize AWS GuardDuty (Delete invitations, disassociate from GuardDuty's master account, delete detector)
#	- Sanitize AWS Security Hub (Delete invitations, disassociate from Security Hub's master account, disable Security Hub)
#
#
#	Prerequesites:
#	- We are assuming that the wished account to sanitize is already part of the AWS Organizations
#
#
#	Usage
#	$ ./EC-Sanitize-Account.sh Client_Name
#
#	ex:
#	$ ./EC-Sanitize-Account.sh newAcc1
#
#
#
#   Version History
#
#   v1.0  Alexandre Levret   Initial Version
#   v1.1  Alexandre Levret   Adding ctrl-c to break if parameters are not ok and adding region variable for every commands
#   v1.2  Alexandre Levret   Adding the checking part (for Organizations) + AssumeRole + CLI profile creation
#   v1.3  Alexandre Levret   Removing all previous invitations for GuardDuty and Security Hub (even if these services are disabled)
#   v1.4  Alexandre Levret   Removing the region variable
#   v1.5  Alexandre Levret   Add check (list-accounts within Organizations) to see if the default account has enough permissions to run this script
#   v1.6  Alexandre Levret   Refactor to keep only the sanitize function
#   v1.7  Alexandre Levret	 Update the script to be globally usable
#   --------------------------------------------------------

#	--------------------
#	Parameters
#	--------------------

CLIENT=$1
CLIENT_ID=`aws --profile $CLIENT sts get-caller-identity --query 'Account' --output text`

#	--------------------
#   Functions
#
#       sanitize_all_regions() -> To call the sanitize script in every AWS regions
#       sanitize() -> Sanitize the wished account by desabling / resetting multiple AWS services (Config, GuardDuty, Security Hub)
#	--------------------

sanitize_all_regions() {

	printf "\n- This script will sanitize globally this AWS account with following settings:\n"
	echo "   ----------------------------------------------------"
	echo "     Account name:                     	$CLIENT"
	echo "     Account ID:                       	$CLIENT_ID"
	echo "   ----------------------------------------------------"


	ALL_REGIONS=(ap-northeast-1 ap-northeast-2 ap-south-1 ap-southeast-1 ap-southeast-2 ca-central-1 eu-central-1 eu-west-2 eu-west-3 eu-west-1 sa-east-1 us-east-1 us-east-2 us-west-1 us-west-2)
	for AWS_REGION in "${ALL_REGIONS[@]}"; do
		export AWS_REGION
			sanitize
	done
        

        #   ----------------------------------------------------------------
        #   Sanitizing account completed - setting SSM parameter
        #   ----------------------------------------------------------------

        # Set SSM parameter "SECLZ-Account_sanitized-or-New_account" to 1
        aws --profile $CLIENT ssm put-parameter --name /org/member/SECLZ-Account_sanitized-or-New_account --value "1" --type String --overwrite

}

sanitize() {

	printf "\n- This script will sanitize this AWS account with following settings:\n"
	echo "   ----------------------------------------------------"
	echo "     Account name:                     	$CLIENT"
	echo "     Account ID:                       	$CLIENT_ID"
	echo "     in AWS Region:                    	$AWS_REGION"
	echo "   ----------------------------------------------------"

	#   ----------------------------------------------------------------
	#   Starting sanitizing
	#   ----------------------------------------------------------------

	echo "   "
	echo "    Sanitizing ..."
	echo "   "

	#   ----------------------------------------------------------------
	#   Sanitizing AWS Config
	#   ----------------------------------------------------------------

	# Looking for an existing configuration recorder (in the case of Config enabled)
	CONFIG_RECORDER_NAME=`aws --profile $CLIENT --region $AWS_REGION configservice describe-configuration-recorders --output text | grep CONFIGURATIONRECORDERS | awk '{print $2}'`

	# Deleting the configuration recorder (if the configuration recorder name is not null)
	if [ -z "$CONFIG_RECORDER_NAME" ]
	then
	  	CONFIG_RECORDER_NAME=""
	else
		aws --profile $CLIENT --region $AWS_REGION configservice delete-configuration-recorder --configuration-recorder-name $CONFIG_RECORDER_NAME

		# Deleting the Config delivery channel
		DELIVERY_CHANNEL_NAME=`aws --profile $CLIENT --region $AWS_REGION configservice describe-delivery-channels --output text --query 'DeliveryChannels[0].name'`
		aws --profile $CLIENT --region $AWS_REGION configservice delete-delivery-channel --delivery-channel-name $DELIVERY_CHANNEL_NAME
	fi



	echo "   - Config -> Done"

	#   ----------------------------------------------------------------
	#   Sanitizing AWS GuardDuty
	#   ----------------------------------------------------------------

	# Delete all previous invitations
	NB_INVITATIONS=`aws --profile $CLIENT guardduty get-invitations-count --region $AWS_REGION --output text | awk '{print $1}'`
	if [ $NB_INVITATIONS != 0 ]
	then
		LIST_INVITATIONS_IDS=`aws --profile $CLIENT guardduty list-invitations --region $AWS_REGION --output text | grep INVITATIONS | awk '{print $2}'`
		aws --profile $CLIENT guardduty delete-invitations --account-ids $LIST_INVITATIONS_IDS --region $AWS_REGION
	fi

	# Find if there's a detector
	GUARDDUTY_DETECTOR_ID=`aws --profile $CLIENT --region $AWS_REGION guardduty list-detectors --output text | grep DETECTORIDS | awk '{print $2}'`

	# Delete the detector (if the configuration recorder name is not null)
	if [ -z "$GUARDDUTY_DETECTOR_ID" ]
	then
		GUARDDUTY_DETECTOR_ID=""
	else
		# Find if the account is associated to a GuardDuty's master account
		GUARDDUTY_MASTER_ACCOUNT_ID=`aws --profile $CLIENT --region $AWS_REGION guardduty get-master-account --detector-id $GUARDDUTY_DETECTOR_ID`

		if [ -z "$GUARDDUTY_MASTER_ACCOUNT_ID" ]
		then
			GUARDDUTY_MASTER_ACCOUNT_ID=""
		else
			aws --profile $CLIENT guardduty disassociate-from-master-account --detector-id $GUARDDUTY_DETECTOR_ID --region $AWS_REGION
		fi

		aws --profile $CLIENT guardduty delete-detector --detector-id $GUARDDUTY_DETECTOR_ID --region $AWS_REGION
	fi
	echo "   - GuardDuty -> Done"

	#   ----------------------------------------------------------------
	#   Sanitizing AWS Security Hub
	#   ----------------------------------------------------------------

	# Delete all previous invitations
	NB_INVITATIONS=`aws --profile $CLIENT securityhub get-invitations-count --region $AWS_REGION --output text | awk '{print $1}'`
	if [ $NB_INVITATIONS != 0 ]
	then
		LIST_INVITATIONS_IDS=`aws --profile $CLIENT securityhub list-invitations --region $AWS_REGION --output text | grep INVITATIONS | awk '{print $2}'`
		aws --profile $CLIENT securityhub delete-invitations --account-ids $LIST_INVITATIONS_IDS --region $AWS_REGION
	fi

	# Find if the account is associated to a current Security Hub's master account
	SECURITYHUB_MASTER_ACCOUNT_ID=`aws --profile $CLIENT --region $AWS_REGION securityhub get-master-account --output text | grep MASTER | awk '{print $2}'`

	# If there's a current Security Hub's master account, disassociate from this one
	if [ -z "$SECURITYHUB_MASTER_ACCOUNT_ID" ]
	then
		SECURITYHUB_MASTER_ACCOUNT_ID=""
	else
		aws --profile $CLIENT securityhub disassociate-from-master-account --region $AWS_REGION
	fi

	aws --profile $CLIENT securityhub disable-security-hub --region $AWS_REGION &>/dev/null

	echo "   - Security Hub -> Done"

}

sanitize_all_regions
