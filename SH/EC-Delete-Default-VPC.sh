#!/bin/bash -e

#   --------------------------------------------------------
#
#	Automates the following:
#	- AWS Account creation (Within an AWS Org)
#	- AWS CLI Role Profile creation for the new account
#
#       Usage
#       $ ./EC-Create-Account.sh ACCOUNT_Name
#        ex:
#          $ ./EC-Create-Account.sh DIGITS3_Drupal1
#
#   Version History
#
#   v1.0    J. Vandenbergen   Initial Version
#   v1.1    A. Levret         Add 'jq' package installed check
#   v1.2    A. Levret         Remove 'jq' dependencies
#   --------------------------------------------------------

#   --------------------
#	Parameters
#	--------------------
ACC_NAME=$1


#if [ "$AWS_PROFILE" = "" ]; then
#  echo "No AWS_PROFILE set"
#  exit 1
#fi

#   ---------------------
#   The command line help
#   ---------------------
display_help() {
    echo "Usage: $0 ACCOUNT_Name" >&2
    echo
    echo "   Provide an account name to configure and"
    echo "   delete all the default VPC's in all regions"
    echo
    exit 1
}

#   --------------------------------
#   Function to delete default VPC's
#   --------------------------------

delete_vpc() {

    for region in $(aws --profile $ACC_NAME ec2 describe-regions --region eu-west-1 --output text --query 'Regions[*].[RegionName]'); do

    echo "* Region ${region}"

    # get default vpc
    vpc=$(aws --profile $ACC_NAME ec2 --region ${region} \
        describe-vpcs --filter Name=isDefault,Values=true \
        --output text --query 'Vpcs[*].VpcId')
    if [ -z ${vpc} ]
    then
      echo "No default vpc found"
      continue
    else
      echo "Found default vpc ${vpc}"
    fi

    # get internet gateway
    igw=$(aws --profile $ACC_NAME ec2 --region ${region} \
        describe-internet-gateways --filter Name=attachment.vpc-id,Values=${vpc} \
        --output text --query 'InternetGateways[0].InternetGatewayId')
    if [ "${igw}" != "null" ]; then
        echo "Detaching and deleting internet gateway ${igw}"
        aws --profile $ACC_NAME ec2 --region ${region} \
        detach-internet-gateway --internet-gateway-id ${igw} --vpc-id ${vpc}
        aws --profile $ACC_NAME ec2 --region ${region} \
        delete-internet-gateway --internet-gateway-id ${igw}
    fi

    # get subnets
    subnets=$(aws --profile $ACC_NAME ec2 --region ${region} \
        describe-subnets --filters Name=vpc-id,Values=${vpc} \
        --output text --query 'Subnets[*].SubnetId')
    if [ "${subnets}" != "null" ]; then
        for subnet in ${subnets}; do
        echo "Deleting subnet ${subnet}"
        aws --profile $ACC_NAME ec2 --region ${region} \
            delete-subnet --subnet-id ${subnet}
        done
    fi

    # https://docs.aws.amazon.com/cli/latest/reference/ec2/delete-vpc.html
    # - You can't delete the main route table
    # - You can't delete the default network acl
    # - You can't delete the default security group

    # delete default vpc
    echo "Deleting vpc ${vpc}"
    aws --profile $ACC_NAME ec2 --region ${region} \
        delete-vpc --vpc-id ${vpc}

    done
}

# ---------------------------------------------
# Check if correct options are given
# on the commandline and send invitation
# ---------------------------------------------

# Simple check if two arguments are provided
if [ -z $1 ]; then
    display_help  # Call your function
    exit 0
fi

#invite client to seclog account
delete_vpc
