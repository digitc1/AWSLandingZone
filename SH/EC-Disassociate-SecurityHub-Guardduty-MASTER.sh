#!/bin/bash

# Check if an Account ID is provided as a parameter
if [ -z "$1" ]; then
    echo "Usage: $0 <MEMBER_ACCOUNT_ID>"
    exit 1
fi

# Assign the passed Account ID to a variable
MEMBER_ACCOUNT_ID="$1"

# Fetch the list of all enabled AWS regions
REGIONS=$(aws ec2 describe-regions --query "Regions[].RegionName" --output text)

# Function to disassociate Security Hub member accounts
disassociate_securityhub() {
    echo "Disassociating Security Hub members in region: $1"

    aws securityhub disassociate-members \
        --account-ids $MEMBER_ACCOUNT_ID \
        --region $1

    if [ $? -eq 0 ]; then
        echo "Successfully disassociated Security Hub member in region: $1"
    else
        echo "Failed to disassociate Security Hub member in region: $1"
    fi
}

# Function to disassociate GuardDuty member accounts
disassociate_guardduty() {
    echo "Disassociating GuardDuty members in region: $1"

    # Retrieve the GuardDuty detector ID
    DETECTOR_ID=$(aws guardduty list-detectors --region $1 --query "DetectorIds[0]" --output text)

    if [ "$DETECTOR_ID" == "None" ] || [ -z "$DETECTOR_ID" ]; then
        echo "No GuardDuty detector found in region: $1. Skipping."
        return
    fi

    aws guardduty disassociate-members \
        --detector-id $DETECTOR_ID \
        --account-ids $MEMBER_ACCOUNT_ID \
        --region $1

    if [ $? -eq 0 ]; then
        echo "Successfully disassociated GuardDuty member in region: $1"
    else
        echo "Failed to disassociate GuardDuty member in region: $1"
    fi
}

# Loop through each region and disassociate members
for REGION in $REGIONS; do
    echo "Processing region: $REGION"

    # Disassociate Security Hub member
    disassociate_securityhub $REGION

    # Disassociate GuardDuty member
    disassociate_guardduty $REGION
done

echo "Disassociation process for Security Hub and GuardDuty completed."
