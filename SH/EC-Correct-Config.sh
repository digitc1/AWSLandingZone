#!/bin/bash -e

#   --------------------------------------------------------
#
#			Automates the following:
#			- set the aggregation authorization on the config of all regions 
#
#			Usage
#
#			$ ./EC-Sanitize-Account.sh Client_account SecLog_account
#
#			ex:
#			$ ./EC-Sanitize-Account.sh newAcc1 SecLogAcc
#
#
#
#   Version History
#
#   v1.0  Laurent Léonard   Initial Version
#   --------------------------------------------------------

#       --------------------
#       Parameters
#       --------------------

CLIENT=$1
SECLOG=$2

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

config_all_regions() {

    AWS_REGION='eu-west-1'
    CLIENT_ID=`aws --profile $CLIENT sts get-caller-identity --query 'Account' --output text`
    SECLOG_ID=`aws --profile $SECLOG sts get-caller-identity --query 'Account' --output text`

    printf "\n- This script will config this AWS account with following settings:\n"
    echo "   ----------------------------------------------------"
    echo "     Client name:                     $CLIENT"
    echo "     Client ID:                       $CLIENT_ID"
    echo "     SecLog name:                     $SECLOG"
    echo "     SecLog ID:                       $SECLOG_ID"
    echo "   ----------------------------------------------------"
    

    for region in $(aws ec2 describe-regions --output text --query 'Regions[*].[RegionName]'); do
        echo "put-aggregation-authorization for region $region ..."
        aws --profile $CLIENT configservice put-aggregation-authorization --authorized-account-id $SECLOG_ID --authorized-aws-region $AWS_REGION --region $region
    done

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
config_all_regions
