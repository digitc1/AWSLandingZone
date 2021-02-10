#!/bin/bash

#   --------------------------------------------------------
#   Updates/1.3.1/EC-Update-Seclog.sh
#   
#   v1.0.0    J. Silva          Initial version.
#   --------------------------------------------------------

#   --------------------
#       Parameters
#   --------------------

seclogprofile=${seclogprofile:-}
splunkprofile=${splunkprofile:-}
logdestination=${logdestination:-}
guarddutyintegration=${guarddutyintegration:-true}
cloudtrailintegration=${cloudtrailintegration:-true}
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
CFN_GUARDDUTY_TEMPLATE_GLOBAL='../../CFN/EC-lz-Config-Guardduty-all-regions.yml'

ALL_REGIONS_EXCEPT_IRELAND='["ap-northeast-1","ap-northeast-2","ap-south-1","ap-southeast-1","ap-southeast-2","ca-central-1","eu-central-1","eu-north-1","eu-west-2","eu-west-3","sa-east-1","us-east-1","us-east-2","us-west-1","us-west-2"]'

#   ---------------------
#   The command line help
#   ---------------------
display_help() {

    echo "Usage: $0 --seclogprofile <Seclog Acc Profile> --splunkprofile <Splunk Acc Profile> --logdestination <Log Destination DG name>  [--cloudtrailintegration <true|false] [--guarddutyintegration <true|false>]"
    echo ""
    echo "   Provide "
    echo "   --seclogprofile           : The account profile of the central SecLog account as configured in your AWS profile"
    echo "   --splunkprofile           : The Splunk account profile as configured in your AWS profile"
    echo "   --logdestination          : The name of the DG of the firehose log destination"
    echo "   --guarddutyintegration    : Flag to enable or disable GuardDuty seclog integration. Default: true (optional)"
    echo "   --cloudtrailintegration  : Flag to enable or disable CloudTrail seclog integration. Default: true (optional)"
    echo "   --batch                  : Flag to enable or disable batch execution mode. Default: false (optional)"
    echo ""
    exit 1
}

#   ----------------------------
#   Configure Seclog Account
#   ----------------------------
update_seclog() {


    # Getting SecLog Account Id
    SECLOG_ACCOUNT_ID=`aws --profile $seclogprofile sts get-caller-identity --query 'Account' --output text`

    if  [[ "$guarddutyintegration" == "true" || "$cloudtrailintegration" == "true" ]]; then
        # Getting C2 Splunk Account Id
        SPLUNK_ACCOUNT_ID=`aws --profile $splunkprofile sts get-caller-identity --query 'Account' --output text`

        # Getting available log destinations from
        DESCRIBE_DESTINATIONS=`aws --profile $splunkprofile  logs describe-destinations`

        # Extract select Log destination details
        FIREHOSE_ARN=`echo $DESCRIBE_DESTINATIONS | jq -r '.destinations[]| select (.destinationName | contains("'$logdestination'")) .arn'`
        FIREHOSE_DESTINATION_NAME=`echo $DESCRIBE_DESTINATIONS | jq -r '.destinations[]| select (.destinationName | contains("'$logdestination'")) .destinationName'`
        FIREHOSE_ACCESS_POLICY=`echo $DESCRIBE_DESTINATIONS | jq -r '.destinations[]| select (.destinationName | contains("'$logdestination'")) .accessPolicy'`
    fi


    echo ""
    echo "- This script will configure a the SecLog account with following settings:"
    echo "   ----------------------------------------------------"
    echo "     SecLog Account to be configured:     $seclogprofile"
    echo "     SecLog Account Id:                   $SECLOG_ACCOUNT_ID"
    echo "     GuardDuty integration with Splunk:   $guarddutyintegration"
    if [[ "$guarddutyintegration" == "true" || "$cloudtrailintegration" == "true" ]]; then
      echo "     Splunk Account Id:                   $SPLUNK_ACCOUNT_ID"
      echo "     Log Destination Name:                $FIREHOSE_DESTINATION_NAME"
      echo "     Log Destination ARN:                 $FIREHOSE_ARN"
    fi
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

    # Delete existing stack

    aws cloudformation update-termination-protection \
    --stack-name 'SECLZ-Iam-Password-Policy'  \
    --no-enable-termination-protection \
    --profile $seclogprofile

    sleep 5

    aws cloudformation delete-stack \
    --stack-name 'SECLZ-Iam-Password-Policy' 
    --profile $seclogprofile

    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "DELETE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    # Create new stack
    aws cloudformation create-stack \
    --stack-name 'SECLZ-Iam-Password-Policy' \
    --template-body file://$CFN_IAM_PWD_POLICY \
    --capabilities CAPABILITY_IAM \
    --enable-termination-protection \
    --profile $seclogprofile

  
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "UPDATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    sleep 5

    #   ------------------------------------
    #   Update config, cloudtrail, SNS notifications
    #   ------------------------------------


    echo ""
    echo "- Update config, cloudtrail, SNS notifications"
    echo "--------------------------------------------------"
    echo ""

    cloudtrailparams="ParameterKey=EnableSecLogForCloudTrailParam,ParameterValue=$cloudtrailintegration"
    if [ "$cloudtrailintegration" == "true" ]; then
        cloudtrailparams="ParameterKey=FirehoseDestinationArn,ParameterValue=$FIREHOSE_ARN"
    fi


    aws cloudformation create-stack \
    --stack-name 'SECLZ-config-cloudtrail-SNS' \
    --template-body file://$CFN_LOG_TEMPLATE \
    --enable-termination-protection \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $seclogprofile \
    --parameters $cloudtrailparams

    StackName="SECLZ-config-cloudtrail-SNS"
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "UPDATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    sleep 5

    #   ------------------------------------
    #   Update  guardduty in seclog account
    #   ------------------------------------

    echo "" 
    echo "- Update guardduty in seclog account"
    echo "--------------------"
    echo ""

    StackName="SECLZ-Guardduty-detector"

    guarddutyparams="ParameterKey=EnableSecLogIntegrationFoGuardDutyParam,ParameterValue=$guarddutyintegration"
    if [ "$guarddutyintegration" == "true" ]; then
        guarddutyparams="ParameterKey=FirehoseDestinationArn,ParameterValue=$FIREHOSE_ARN"
    fi

    aws cloudformation update-stack \
    --stack-name 'SECLZ-Guardduty-detector' \
    --template-body file://$CFN_GUARDDUTY_DETECTOR_TEMPLATE \
    --capabilities CAPABILITY_IAM \
    --profile $seclogprofile \
    --parameters $guarddutyparams

    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "UPDATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName


   sleep 5

    #   ------------------------------------
    #    Update cloudtrail globally using stacksets
    #   ------------------------------------


    echo ""
    echo "-  update cloudtrail globally"
    echo "--------------------------------------------------"
    echo ""

    # Create StackSet (Enable Guardduty globally)
    aws cloudformation  update-stack-set \
    --stack-set-name 'SECLZ-Enable-Guardduty-Globally' \
    --parameters ParameterKey=SecLogMasterAccountId,ParameterValue=$SECLOG_ACCOUNT_ID ParameterKey=EnableSecLogIntegrationFoGuardDutyParam,ParameterValue=$guarddutyintegration \
    --template-body file://$CFN_GUARDDUTY_TEMPLATE_GLOBAL \
    --capabilities CAPABILITY_IAM \
    --profile $seclogprofile

    sleep 5

    #   ------------------------------------
    #   Update seclog account event bus permissions
    #   ------------------------------------

    echo ""
    echo "- Update seclog account event bus permissions ... "
    echo "-----------------------------------------------------------"
    echo ""

    echo "Remove personalised event bus permission policy for Ireland... " 

    DESCRIBE_EVENTBUS=`aws --profile $seclogprofile events describe-event-bus`
    POLICY=`echo $DESCRIBE_EVENTBUS | jq -r '.Policy'`
    SID=`echo $POLICY | jq  -r '.Statement[] | select (.Principal | select (.AWS? | contains("root"))).Sid'`
    CLIENTARN=`echo $POLICY | jq -r '.Statement[] | select (.Principal | select (.AWS? | contains("root")))'.Principal.AWS`

    for i in ${SID}; 
    do
      aws --profile $seclogprofile events remove-permission --statement-id $i
    done

    echo "\bDone." 
    sleep 1
    echo ""
    echo "Remove event bus permission policies for all regions... " 
    echo ""
    ALL_REGIONS_EXCEPT_IRELAND_ARRAY=`echo $ALL_REGIONS_EXCEPT_IRELAND | sed -e 's/\[//g;s/\]//g;s/,/ /g;s/\"//g'`
	  for r in ${ALL_REGIONS_EXCEPT_IRELAND_ARRAY[@]}; 
      do
        echo "Remove personalised event bus permission policy for $r... " 

        DESCRIBE_EVENTBUS=`aws --profile $seclogprofile --region $r events describe-event-bus`
        POLICY=`echo $DESCRIBE_EVENTBUS | jq -r '.Policy'`
        SID=`echo $POLICY | jq  -r '.Statement[] | select (.Principal | select (.AWS? | contains("root"))).Sid'`
        CLIENTARN=`echo $POLICY | jq -r '.Statement[] | select (.Principal | select (.AWS? | contains("root")))'.Principal.AWS`

        for i in ${SID}; 
        do
          aws --profile $seclogprofile events remove-permission --statement-id $i
        done
        echo "\bDone."
      done
    

    sleep 5

    echo "---------------------------------------------------------------------------------------------------------"
    echo "|                                         ATTENTION PLEASE:                                             |"
    echo "---------------------------------------------------------------------------------------------------------"
    echo "|                                                                                                       |"
    echo "|  Please check the installation of the stackset instances from the AWS console for the SECLOG account  |"
    echo "|  The moment all instances are deployed, please execute the 2nd stage of the LZ update with the        |"
    echo "|  following command:                                                                                   |"
    echo "|                                                                                                       |"
    echo "|               sh ../../SH/EC-Enable-SecurityHub-Controls-All-Regions.sh $seclogprofile                |"
    echo "|                                                                                                       |"
    echo "---------------------------------------------------------------------------------------------------------"


}

# ---------------------------------------------
# Check if correct options are given
# on the commandline and start configurations
# ---------------------------------------------



if  [ -z "$seclogprofile" ] ; then
    display_help
    exit 0
fi

if [[ ( -z "$logdestination" || -z "$splunkprofile" ) && ( "$cloudtrailintegration" == "true" ||  "$guarddutyintegration" == "true"  ) ]]; then
    display_help
    exit 0
fi


#start account configuration
update_seclog
