#!/bin/bash

# Fetch the list of all enabled AWS regions
REGIONS=$(aws ec2 describe-regions --query "Regions[].RegionName" --output text)

# Function to disable Security Hub
disable_securityhub() {
    echo "Disabling Security Hub in region: $1"

    # Check if Security Hub is enabled
    STATUS=$(aws securityhub get-findings --region $1 --max-items 1 2>&1)
    if [[ "$STATUS" == *"Security Hub is not enabled"* ]]; then
        echo "Security Hub is already disabled in region: $1"
        return
    fi

    # Disable Security Hub
    aws securityhub disable-security-hub --region $1 > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "Successfully disabled Security Hub in region: $1"
    else
        echo "Failed to disable Security Hub in region: $1"
    fi
}

# Function to disable GuardDuty
disable_guardduty() {
    echo "Disabling GuardDuty in region: $1"

    # Retrieve the GuardDuty Detector ID
    DETECTOR_ID=$(aws guardduty list-detectors --region $1 --query "DetectorIds[0]" --output text)

    if [ -z "$DETECTOR_ID" ] || [ "$DETECTOR_ID" == "None" ]; then
        echo "GuardDuty is already disabled in region: $1"
        return
    fi

    # Disable GuardDuty
    aws guardduty delete-detector --detector-id $DETECTOR_ID --region $1 > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "Successfully disabled GuardDuty in region: $1"
    else
        echo "Failed to disable GuardDuty in region: $1"
    fi
}

# Loop through all regions and disable Security Hub and GuardDuty
for REGION in $REGIONS; do
    echo "Processing region: $REGION"

    # Disable Security Hub
    disable_securityhub $REGION

    # Disable GuardDuty
    disable_guardduty $REGION

done

echo "Decommissioning Security Hub and GuardDuty completed in all regions."
