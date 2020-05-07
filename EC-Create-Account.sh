#!/bin/bash

#   --------------------------------------------------------
#
#		Automates the following:
#		- AWS Account creation (Within an AWS Org)
#		- AWS CLI Role Profile creation for the new account
#
#       Usage
#       $ ./EC-Create-Account.sh ACCOUNT_Name E-mail_account_owner
#        ex:
#          $ ./EC-Create-Account.sh DIGITS3_Drupal1 janssens@ec.eu
#          $ ./EC-Create-Account.sh DIGITS3_SecLog janssens@ec.eu
#
#   Version History
#
#   v1.0    J. Vandenbergen    Initial Version
#   v1.1    Alexandre Levret   Check if the AWS account creation has succeeded
#   --------------------------------------------------------

#   --------------------
#	Parameters
#	--------------------
ACC_NAME=$1
ACC_EMAIL=$2

# Role that will be used to assume a role in other Accounts
ACC_ROLE_NAME='OrganizationAccountAccessRole'
AWS_REGION='eu-west-1'

# Script Spinner waiting for cloudformation completion
export i=1
export sp="/-\|"

#   ---------------------
#   The command line help
#   ---------------------
display_help() {
    echo "Usage: $0 ACCOUNT_Name E-mail_account_owner " >&2
    echo
    echo "   Provide an account name and e-mail address"
    echo "   to create a new account in the organization."
    echo
    exit 1
}

#   ----------------------------
#   The create account function
#   ----------------------------
create_account() {
    # Get organizations Identity
    Master_accountId=`aws sts get-caller-identity --query 'Account' --output text`
    Master_account=`aws organizations list-accounts --output text --query "Accounts[?Id=='$Master_accountId'][Name]"`

    printf "\n- This script will create a new AWS account with following settings:\n"
    echo "   ----------------------------------------------------"
    echo "     New Account name:                  $ACC_NAME"
    echo "     New Account e-mail:                $ACC_EMAIL"
    echo "     Organization Cross Account role:   $ACC_ROLE_NAME"
    echo "     in AWS Region:                     $AWS_REGION"
    echo "   ----------------------------------------------------"
    echo "     Under Master account:              $Master_account"
    echo "     Under Master accountId:            $Master_accountId"
    echo "   ----------------------------------------------------"
    printf "\n\n\tIf this is correct press enter to continue"
    read -p "  or CTRL-C to break"

    #	Create AWS Account
    #	--------------------
    printf "\n- Creating AWS Account: $ACC_NAME"
    printf "\n------------------------------------------------\n"


    echo "Creating the AWS account"

    CREATE_ACCOUNT_REQUEST_ID=`aws organizations create-account --email $ACC_EMAIL --account-name $ACC_NAME --iam-user-access-to-billing ALLOW --role-name $ACC_ROLE_NAME --output text --query 'CreateAccountStatus.Id'`

    sleep 10

    aws organizations describe-create-account-status --create-account-request-id $CREATE_ACCOUNT_REQUEST_ID --output text --query 'CreateAccountStatus.State'
    while [ `aws organizations describe-create-account-status --create-account-request-id $CREATE_ACCOUNT_REQUEST_ID --output text --query 'CreateAccountStatus.State'` == "IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws organizations describe-create-account-status --create-account-request-id $CREATE_ACCOUNT_REQUEST_ID --output text --query 'CreateAccountStatus.State'

    echo ""
    echo "Please, press enter if the creation account state has 'Succeeded'"
    read -p "  or CTRL-C to break"

    #	Get accountId
    #	--------------------
    #	aws organizations list-accounts

    AWS_ACC_NUM=`aws organizations list-accounts --query 'Accounts[*].[Id, Email]' --output text | grep $ACC_EMAIL | awk '{print $1}'`

    printf "\n New AWS Account number: $AWS_ACC_NUM\n"

    sleep 60


    #   Create CloudBroker cross account access role in newly created account
    #   Create Cloudbroker crossAccountAccessRole by running a stack-set from the master account
    #   ------------------------------------------------------------------------

    read -p "Press enter to continue"

    StackSetName="AB-SECLZ-CloudBroker-role"
    aws cloudformation create-stack-instances \
      --stack-set-name $StackSetName \
      --accounts $AWS_ACC_NUM \
      --regions eu-west-1

    sleep 5

    echo "Deploying stack instance  for cloudbroker role in new account $AWS_ACC_NUM "
    aws cloudformation describe-stack-instance --stack-set-name $StackSetName --stack-instance-region $AWS_REGION --stack-instance-account $AWS_ACC_NUM --query 'StackInstance.Status' --output text
    while [ `aws cloudformation describe-stack-instance --stack-set-name $StackSetName --stack-instance-region $AWS_REGION --stack-instance-account $AWS_ACC_NUM --query 'StackInstance.Status' --output text` == "OUTDATED" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws cloudformation describe-stack-instance --stack-set-name $StackSetName --stack-instance-region $AWS_REGION --stack-instance-account $AWS_ACC_NUM --query 'StackInstance.Status' --output text


    #	Create CLI role profile
    #	-------------------------

    printf "\n- Creating AWS CLI Role Profile for AWS account: $ACC_NAME"
    printf "\n------------------------------------------------"
    echo "" >> ~/.aws/config
    echo "[profile $ACC_NAME]" >> ~/.aws/config
    echo "role_arn = arn:aws:iam::$AWS_ACC_NUM:role/CloudBrokerAccountAccessRole" >> ~/.aws/config
    echo `cat ~/.aws/config | grep source_profile | head -1` >> ~/.aws/config
    echo `cat ~/.aws/config | grep mfa | grep $Master_accountId | uniq` >> ~/.aws/config
    echo "region = $AWS_REGION" >> ~/.aws/config

    printf "\n- CLI profile written to ~/.aws/config\n"

    #  Testing new CLI profile
    #  ------------------------

    printf "\n- Testing new CLI profile for account: $ACC_NAME"
    printf "\n- You should be prompted for a MFA token...."
    printf "\n------------------------------------------------"
    echo ""

    aws --profile $ACC_NAME sts get-caller-identity

    #   Delete default VPC
    #	-------------------------

    printf "\n- Deleting default VPC for AWS account: $ACC_NAME"
    printf "\n------------------------------------------------"
    echo ""

    sh ./SH/EC-Delete-Default-VPC.sh $ACC_NAME

	#   Sanitizing Account Not needed as this is a new account - setting SSM parameter
	#   ----------------------------------------------------------------

	# Set SSM parameter "SECLZ-Account_sanitized-or-New_account" to 1

	aws --profile $ACC_NAME ssm put-parameter --name /org/member/SECLZ-Account_sanitized-or-New_account --value "1" --type String &>/dev/null

    #   Final Message
    #   -------------

    echo ""
    echo "  Account Creation completed"
    echo "  New AccountID: $AWS_ACC_NUM"
    echo "  New Account Name: $ACC_NAME"
    echo ""
    echo ""

}

# ---------------------------------------------
# Check if correct options are given
# on the commandline and start account creation
# ---------------------------------------------

# Simple check to see if 2nd argument looks like an e-mail address "@"
second=`echo $2 | sed -e s/.*@.*/@/g`

while :
do
    case "$second" in
      @)
          # valid 2nd argument is an e-mail
          break
          ;;
      *)
          display_help  # Call your function
          exit 0
          ;;
    esac
done

#start account creation process
create_account
