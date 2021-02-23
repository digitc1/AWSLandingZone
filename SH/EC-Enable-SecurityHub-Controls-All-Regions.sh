#!/bin/bash

#   --------------------------------------------------------
#
#		Enables securityhub controls for all regions:
#
#
#       Usage
#       $ ./SH/EC-Enable-SecurityHub-Controls-All-Regions.sh PROFILE
#
#   Version History
#
#   v1.0    J. Silva   Initial Version
#   --------------------------------------------------------

#   --------------------
#	Parameters
#	--------------------
PROFILE=$1

#   ---------------------
#   The command line help
#   ---------------------
display_help() {
    echo "Usage: $0 PROFILE" >&2
    echo
    echo "   Provide an account name to configure as defined in your AWS profile."
    echo
    exit 1
}

#   ----------------------------
#   Configure Client Account
#   ----------------------------
configure() {

   
    accountid=`aws --profile $PROFILE sts get-caller-identity --query 'Account' --output text`

    echo ""
    echo "- Enable securityhub controls for all regions. Account $accountid"
    echo "-------------------------------------"
    echo ""


    for region in $(aws --profile $PROFILE ec2 describe-regions --output text --query 'Regions[*].[RegionName]'); do
        echo "auto-enable-controls for securityhub for region $region ..."
        aws --profile $PROFILE --region $region securityhub batch-enable-standards --standards-subscription-requests StandardsArn="arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0"
        aws --profile $PROFILE --region $region securityhub batch-enable-standards --standards-subscription-requests StandardsArn="arn:aws:securityhub:$region::standards/aws-foundational-security-best-practices/v/1.0.0"
        aws --profile $PROFILE --region $region securityhub update-security-hub-configuration --auto-enable-controls

        sleep 2
        # Disable "ControlId": "IAM.6", "Title": "Hardware MFA should be enabled for the root user"
        aws --profile $PROFILE --region $region securityhub update-standards-control --standards-control-arn "arn:aws:securityhub:$region:$accountid:control/aws-foundational-security-best-practices/v/1.0.0/IAM.6" --control-status "DISABLED" --disabled-reason "Managed by Cloud Broker Team"
        
        sleep 2
        # Disable "ControlId": "IAM.6", "Title": "Hardware MFA should be enabled for the root user"
        aws --profile $PROFILE --region $region securityhub update-standards-control --standards-control-arn "arn:aws:securityhub:$region:$accountid:control/aws-foundational-security-best-practices/v/1.0.0/IAM.6" --control-status "DISABLED" --disabled-reason "Managed by Cloud Broker Team"

        # Disable "ControlId": "CIS1.14", "1.14 Ensure hardware MFA is enabled for the \"root\" account"
        aws securityhub --profile $PROFILE --region $region update-standards-control --standards-control-arn "arn:aws:securityhub:$region:$accountid:control/cis-aws-foundations-benchmark/v/1.2.0/1.14" --control-status "DISABLED" --disabled-reason "Managed by Cloud Broker Team"

    done
}

# ---------------------------------------------
# Check if correct options are given
# on the commandline and start configurations
# ---------------------------------------------

# Simple check if two arguments are provided
if [ -z $1 ]; then
    display_help  # Call your function
    exit 0
fi

#start account configuration
configure
