#!/bin/bash -e

#   --------------------------------------------------------
#
#  Update for Local SNS client on existing accounts
#    - (script executed in all accounts) Update “SECLZ-config-cloudtrail-SNS” with the new version of the cloudformation script. 
#      This will add a new parameter “/org/member/SecLog_sns_arn” to the parameterstore in seclog account for complaince. 
#    - (only executed in Client accounts) Create the local SNS-topic in the account from the new cloudformation script “SECLZ-local-SNS-topic”. 
#      This will create a new local SNS topics and lambda function. The lambda function will subscribe to the local SNS topic and forward the messages to the SNS topics in the seclog account.
#    - (script executed in all accounts)  Udpate Notification script for security hub metric filers “SECLZ-Notifications-Cloudtrail”. 
#      This will now sent all notifications to the local SNS topic in the client accounts.
#     
#
#
#
#   Version History
#
#   v1.0  Jef Vandenbergen   Initial Version
#
#   --------------------------------------------------------

#	--------------------
#	Parameters
#	--------------------

export CLIENT=$1
AWS_REGION='eu-west-1'


intro() {
	printf "\n- Update script for already existing CLIENT accounts \n"
	echo "   ----------------------------------------------------"
	echo "     This script will create a local SNS topic in account $CLIENT"
	echo "     and use a lambda function to fwd messages"
	echo "     to the central SNS topics in seclog account"
	echo "   ----------------------------------------------------"

}

#   ---------------------
#   The command line help
#   ---------------------
display_help() {
    echo "Usage: $0 Client_ACCOUNT_NAME" >&2
    echo
    echo "   Provide a client account to update with local SNS topic"
    echo
    exit 1
}

#   -----------------------------
#   Update the Client account
#   -----------------------------

update_client(){

	# Script Spinner waiting for cloudformation completion
    export i=1
    export sp="/-\|"

	#   -----------------------------
	#   Add parameter to parameterstore
	#   -----------------------------

    StackName=SECLZ-config-cloudtrail-SNS
    aws cloudformation update-stack \
      --stack-name $StackName \
      --template-body file://CFN/EC-lz-config-cloudtrail-logging.yml \
      --capabilities CAPABILITY_IAM  \
      --profile $CLIENT

	#   -----------------------------------------------------------------------------
	#   Create local SNS topic and lambda fwd function
	#   -----------------------------------------------------------------------------

    StackName=SECLZ-local-SNS-topic
    aws cloudformation create-stack \
      --stack-name $StackName \
      --template-body file://./CFN/EC-lz-local-config-SNS.yml \
      --capabilities CAPABILITY_NAMED_IAM \
      --enable-termination-protection \
      --profile $CLIENT

    aws --profile $CLIENT cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $CLIENT cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "CREATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $CLIENT cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

	#   -----------------------------------------------------------------------------
	#   Update alarms to use new local SNS topic
	#   -----------------------------------------------------------------------------

    StackName=SECLZ-Notifications-Cloudtrail
    aws cloudformation update-stack \
      --stack-name $StackName \
      --template-body file://CFN/EC-lz-notifications.yml \
      --capabilities CAPABILITY_IAM  \
      --profile $CLIENT
	
}

# ---------------------------------------------
# Check if correct options are given
# on the commandline and send invitation
# ---------------------------------------------

# Simple check if an argument is provided
if [ -z $1 ]; then
    display_help  # Call your function
    exit 0
fi

# Short intro on what is going to happen
intro

# Start the Client account configuration
update_client
