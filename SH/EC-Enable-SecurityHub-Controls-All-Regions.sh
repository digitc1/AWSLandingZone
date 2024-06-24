#!/bin/bash

#   --------------------------------------------------------
#
#               Enables securityhub controls for all regions:
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
#       Parameters
#       --------------------
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

    # Disable CIS controls only in eu-west-1
    # ------------------
    for region in $(aws --profile $PROFILE ec2 describe-regions --output text --query "Regions[?(RegionName=='eu-west-1')].[RegionName]"); do
        echo "auto-enable-controls for securityhub for region $region ..."
        aws --profile $PROFILE --region $region securityhub batch-enable-standards --standards-subscription-requests StandardsArn="arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0"
        aws --profile $PROFILE --region $region securityhub batch-enable-standards --standards-subscription-requests StandardsArn="arn:aws:securityhub:$region::standards/aws-foundational-security-best-practices/v/1.0.0"
        aws --profile $PROFILE --region $region securityhub update-security-hub-configuration --auto-enable-controls

        # Fix for https://github.com/digitc1/AWSLandingZone/issues/136
        for cischeck in 1.11 3.1 3.2 3.3 3.4 3.5 3.6 3.7 3.8 3.9 3.10 3.11 3.12 3.13 3.14
        do
            aws --profile $PROFILE --region $region securityhub update-standards-control --standards-control-arn "arn:aws:securityhub:$region:$accountid:control/cis-aws-foundations-benchmark/v/1.2.0/$cischeck" --control-status "DISABLED" --disabled-reason "Alarm action unmanaged by SNS but cloudwatch event"
            echo "CIS Check $cischeck update for cis-aws-foundations-benchmark in region $region: exit code $?"
        done
        # Disable "ControlId": "IAM.6", "Title": "Hardware MFA should be enabled for the root user"
        aws --profile $PROFILE --region $region securityhub update-standards-control --standards-control-arn "arn:aws:securityhub:$region:$accountid:control/aws-foundational-security-best-practices/v/1.0.0/IAM.6" --control-status "DISABLED" --disabled-reason "Managed by Cloud Broker Team"
        echo "CIS Check $cischeck update for aws-foundational-security-best-practices in region $region: exit code $?"
        # Disable "ControlId": "CIS1.14", "1.14 Ensure hardware MFA is enabled for the \"root\" account"
        aws --profile $PROFILE --region $region securityhub update-standards-control --standards-control-arn "arn:aws:securityhub:$region:$accountid:control/cis-aws-foundations-benchmark/v/1.2.0/1.14" --control-status "DISABLED" --disabled-reason "Managed by Cloud Broker Team"
        echo "CIS Check $cischeck update for cis-aws-foundations-benchmark in region $region: exit code $?"
    done

    # ------------------
    # https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-standards-fsbp-to-disable.html
    # Disable some CIS controls in all regions except eu-west-1 
    # ------------------
    for region in $(aws --profile $PROFILE ec2 describe-regions --output text --query "Regions[?( RegionName!='eu-west-1')].[RegionName]"); do
        echo "auto-enable-controls for securityhub for region $region ..."
        aws --profile $PROFILE --region $region securityhub batch-enable-standards --standards-subscription-requests StandardsArn="arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0"
        aws --profile $PROFILE --region $region securityhub batch-enable-standards --standards-subscription-requests StandardsArn="arn:aws:securityhub:$region::standards/aws-foundational-security-best-practices/v/1.0.0"
        aws --profile $PROFILE --region $region securityhub update-security-hub-configuration --auto-enable-controls

        # Fix for https://github.com/digitc1/AWSLandingZone/issues/136
        for cischeck in 1.11 3.1 3.2 3.3 3.4 3.5 3.6 3.7 3.8 3.9 3.10 3.11 3.12 3.13 3.14
        do
            aws --profile $PROFILE --region $region securityhub update-standards-control --standards-control-arn "arn:aws:securityhub:$region:$accountid:control/cis-aws-foundations-benchmark/v/1.2.0/$cischeck" --control-status "DISABLED" --disabled-reason "alarm action unmanaged by SNS but cloudwatch event"
            echo "CIS Check $cischeck update for cis-aws-foundations-benchmark in region $region: exit code $?"
        done
        # Fix for https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-standards-fsbp-to-disable.html
        for cischeck in IAM.1 IAM.2 IAM.3 IAM.4 IAM.6 IAM.7 Config.1
        do
            aws --profile $PROFILE --region $region securityhub update-standards-control --standards-control-arn "arn:aws:securityhub:$region:$accountid:control/aws-foundational-security-best-practices/v/1.0.0/$cischeck" --control-status "DISABLED" --disabled-reason "Disable recording of global resources in all but one Region"
            echo "CIS Check $cischeck update for aws-foundational-security-best-practices in region $region: exit code $?"
        done
        aws --profile $PROFILE --region $region securityhub update-standards-control --standards-control-arn "arn:aws:securityhub:$region:$accountid:control/cis-aws-foundations-benchmark/v/1.2.0/1.14" --control-status "DISABLED" --disabled-reason "Managed by Cloud Broker Team"
        echo "CIS Check $cischeck update for cis-aws-foundations-benchmark in region $region: exit code $?"
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
