#!/bin/bash

#   --------------------------------------------------------
#   Updates/1.3.1/EC-Update-Client.sh
#   
#   v1.0.0    J. Silva          Initial version.
#   --------------------------------------------------------

#   --------------------
#       Parameters
#   --------------------

clientaccprofile=${clientaccprofile:-}
batch=${batch:-false}

while [ $# -gt 0 ]; do

   if [[ $1 == *"--"* ]]; then
        param="${1/--/}"
        declare $param="$2"
   fi

  shift
done

#   --------------------
#       Templates
#   --------------------

CFN_IAM_PWD_POLICY='../../CFN/EC-lz-iam-setting_password_policy.yml'
CFN_GUARDDUTY_DETECTOR_TEMPLATE='../../CFN/EC-lz-guardDuty-detector.yml'
CFN_LOG_TEMPLATE='../../CFN/EC-lz-config-cloudtrail-logging.yml'

#   ---------------------
#   The command line help
#   ---------------------
display_help() {

    echo "Usage: $0 --clientaccprofile <Client Acc Profile>"
    echo ""
    echo "   Provide "
    echo "   --clientaccprofile        : The account profile of the client account as configured in your AWS profile"
    echo "   --batch                  : Flag to enable or disable batch execution mode. Default: false (optional)"
    echo ""
    exit 1
}

#   ----------------------------
#   Update Client Account
#   ----------------------------
update_client() {


    # Getting SecLog Account Id
    CLIENT_ACCOUNT_ID=`aws --profile $clientaccprofile sts get-caller-identity --query 'Account' --output text`


    echo ""
    echo "- This script will configure a the SecLog account with following settings:"
    echo "   ----------------------------------------------------"
    echo "     Client account to be configured:     $clientaccprofile"
    echo "     Client account Id:                   $CLIENT_ACCOUNT_ID"
    echo "   ----------------------------------------------------"
    echo ""
    
    if [ "$batch" == "false" ] ; then
        echo "   If this is correct press enter to continue"
        read -p "  or CTRL-C to break"
    fi

    #   ------------------------------------
    #   Update password policy for IAM
    #   ------------------------------------


    echo ""
    echo "- Update seclog account event bus permissions ... "
    echo "-----------------------------------------------------------"
    echo ""

    StackName="SECLZ-Iam-Password-Policy"

    aws cloudformation update-stack \
    --stack-name 'SECLZ-Iam-Password-Policy' \
    --template-body file://$CFN_IAM_PWD_POLICY \
    --capabilities CAPABILITY_IAM \
    --profile $clientaccprofile

  
    aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "UPDATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    sleep 5

    #   ------------------------------------
    #   Update config, cloudtrail, SNS notifications
    #   ------------------------------------


    echo ""
    echo "- Update config, cloudtrail, SNS notifications"
    echo "--------------------------------------------------"
    echo ""


    aws cloudformation update-stack \
    --stack-name 'SECLZ-config-cloudtrail-SNS' \
    --template-body file://$CFN_LOG_TEMPLATE \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $clientaccprofile \

    StackName="SECLZ-config-cloudtrail-SNS"
    aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "UPDATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    sleep 5

    #   ------------------------------------
    #   Update  guardduty in seclog account
    #   ------------------------------------

    echo "" 
    echo "- Update guardduty in seclog account"
    echo "--------------------"
    echo ""

    StackName="SECLZ-Guardduty-detector"

    aws cloudformation update-stack \
    --stack-name 'SECLZ-Guardduty-detector' \
    --template-body file://$CFN_GUARDDUTY_DETECTOR_TEMPLATE \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $clientaccprofile \

    aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "UPDATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    sleep 5
    
    echo ""
    echo ""
    echo "---------------------------------------------------------------------------------------------------------"
    echo "|                                         ATTENTION PLEASE:                                             |"
    echo "---------------------------------------------------------------------------------------------------------"
    echo "|                                                                                                       |"
    echo "|  Please check the installation of the stackset instances from the AWS console for the SECLOG account  |"
    echo "|  The moment all instances are deployed, please execute the 2nd stage of the LZ update with the        |"
    echo "|  following command:                                                                                   |"
    echo "|                                                                                                       |"
    echo "|               sh ../../SH/EC-Enable-SecurityHub-Controls-All-Regions.sh $clientaccprofile                |"
    echo "|                                                                                                       |"
    echo "---------------------------------------------------------------------------------------------------------"


}

# ---------------------------------------------
# Check if correct options are given
# on the commandline and start configurations
# ---------------------------------------------



if  [ -z "$clientaccprofile" ] ; then
    display_help
    exit 0
fi



#start account configuration
update_client
