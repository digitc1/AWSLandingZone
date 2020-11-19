#!/bin/bash

#   --------------------------------------------------------
#   Adds eu-north-1 to the stackset instances for SecurityHub-all-regions
#   
#   v1.0.0    J. Silva          Initial version.
#   --------------------------------------------------------

#   --------------------
#       Parameters
#   --------------------

seclogprofile=${seclogprofile:-}
cloudtrailintegration=${cloudtrailintegration:-true}

while [ $# -gt 0 ]; do

   if [[ $1 == *"--"* ]]; then
        param="${1/--/}"
        declare $param="$2"
        # echo $1 $2 // Optional to see the parameter:value result
   fi

  shift
done




# Script Spinner waiting for cloudformation completion
export i=1
export sp="/-\|"

ALL_REGIONS_EXCEPT_IRELAND='["ap-northeast-1","ap-northeast-2","ap-south-1","ap-southeast-1","ap-southeast-2","ca-central-1","eu-central-1","eu-north-1","eu-west-2","eu-west-3","sa-east-1","us-east-1","us-east-2","us-west-1","us-west-2"]'

# parameters for scripts
CFN_LOG_TEMPLATE='../../CFN/EC-lz-config-cloudtrail-logging.yml'
CFN_BUCKETS_TEMPLATE='../../CFN/EC-lz-s3-buckets.yml'
CFN_TAGS_PARAMS_FILE='../../CFN/EC-lz-TAGS-params.json'

#   ---------------------
#   The command line help
#   ---------------------
display_help() {

    echo "Usage: $0 --seclogprofile <Seclog Acc Profile> [--cloudtrailintegration <true|false>] [--splunkprofile <Splunk Acc Profile>] [--logdestination <Log Destination DG name>]"
    echo ""
    echo "   Provide "
    echo "   --seclogprofile           : The account profile of the central SecLog account as configured in your AWS profile"
    echo "   --cloudtrailintegration   : Flag to enable or disable GuardDuty seclog integration. Default: true (optional)"
    echo "   --logdestination          : The name of the DG of the firehose log destination (optional is cloudtrailintegration = false)"
    echo "   --splunkprofile           : The Splunk account profile as configured in your AWS profile (optional is cloudtrailintegration = false)"
    echo ""
    exit 1
}

#   ----------------------------
#   Configure Seclog Account
#   ----------------------------
update_seclog() {

  
    # Getting SecLog Account Id
    SECLOG_ACCOUNT_ID=`aws --profile $seclogprofile sts get-caller-identity --query 'Account' --output text`


     #   ------------------------------------
    #   Creating config, cloudtrail, SNS notifications
    #   ------------------------------------


    echo ""
    echo "- Creating config, cloudtrail, SNS notifications"
    echo "--------------------------------------------------"
    echo ""



    cloudtrailparams="ParameterKey=EnableSecLogForCloudTrailParam,ParameterValue=$cloudtrailintegration"
    if [ "$cloudtrailintegration" == "true" ]; then
        # Getting C2 Splunk Account Id
        SPLUNK_ACCOUNT_ID=`aws --profile $splunkprofile sts get-caller-identity --query 'Account' --output text`

        # Getting available log destinations from
        DESCRIBE_DESTINATIONS=`aws --profile $splunkprofile  logs describe-destinations`

        # Extract select Log destination details
        FIREHOSE_ARN=`echo $DESCRIBE_DESTINATIONS | jq -r '.destinations[]| select (.destinationName | contains("'$logdestination'")) .arn'`

        cloudtrailparams="ParameterKey=FirehoseDestinationArn,ParameterValue=$FIREHOSE_ARN"
    fi

    aws cloudformation update-stack \
    --stack-name 'SECLZ-config-cloudtrail-SNS' \
    --template-body file://$CFN_LOG_TEMPLATE \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $seclogprofile \
    --parameters $cloudtrailparams

    StackName="SECLZ-config-cloudtrail-SNS"
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "UPDATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    
    #   ------------------------------------
    #   Set Resource Policy to send Events to LogGroups
    #   ------------------------------------


    echo ""
    echo "-  Set Resource Policy to send Events to LogGroups"
    echo "--------------------------------------------------"
    echo ""

    for region in $(echo $ALL_REGIONS_EXCEPT_IRELAND | sed -e "s/\"//g; s/\[//g; s/\]//g; s/,/ /g")
    do
        aws --profile $seclogprofile  \
            logs put-resource-policy  \
            --policy-name SLZ-EventsToLogGroup-Policy \
            --policy-document '{ "Version": "2012-10-17", "Statement": [{ "Sid": "TrustEventsToStoreLogEvent", "Effect": "Allow", "Principal": { "Service": "events.amazonaws.com"}, "Action":[ "logs:PutLogEvents", "logs:CreateLogStream"],"Resource": "arn:aws:logs:$region:$SECLOG_ACCOUNT_ID:log-group:/aws/events/*:*"}]}'
    done
    sleep 5

    #   ------------------------------------
    #   Enable cloudtrail insights in seclog master account
    #   ------------------------------------


    echo ""
    echo "-  Enable cloudtrail insights in seclog master account"
    echo "--------------------------------------------------"
    echo ""

    aws --profile $seclogprofile cloudtrail put-insight-selectors --trail-name lz-cloudtrail-logging --insight-selectors '[{"InsightType": "ApiCallRateInsight"}]'


}

# ---------------------------------------------
# Check if correct options are given
# on the commandline and start configurations
# ---------------------------------------------

# Check to validate number of parameters entered
if [[ ( -z "$logdestination" || -z "$splunkprofile" ) && ( "$cloudtrailintegration" == "true" ) ]]; then display_help
    exit 0
fi

if  [ -z "$seclogprofile" ] ; then
    display_help
    exit 0
fi


#start account configuration
update_seclog
