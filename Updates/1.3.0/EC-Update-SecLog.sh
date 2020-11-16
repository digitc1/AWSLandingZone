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


#   ---------------------
#   The command line help
#   ---------------------
display_help() {

    echo "Usage: $0 --seclogprofile <Seclog Acc Profile> --guarddutyintegration <true|false>"
    echo ""
    echo "   Provide "
    echo "   --seclogprofile     : The account profile of the central SecLog account as configured in your AWS profile"
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
    #   Set Resource Policy to send Events to LogGroups
    #   ------------------------------------

    for region in $(echo $ALL_REGIONS_EXCEPT_IRELAND | sed -e "s/\"//g; s/\[//g; s/\]//g; s/,/ /g")
    do
        aws --profile $seclogprofile  \
            logs put-resource-policy  \
            --policy-name SLZ-EventsToLogGroup-Policy \
            --policy-document '{ "Version": "2012-10-17", "Statement": [{ "Sid": "TrustEventsToStoreLogEvent", "Effect": "Allow", "Principal": { "Service": "events.amazonaws.com"}, "Action":[ "logs:PutLogEvents", "logs:CreateLogStream"],"Resource": "arn:aws:logs:$region:$SECLOG_ACCOUNT_ID:log-group:/aws/events/*:*"}]}'
    done
    sleep 5


}

# ---------------------------------------------
# Check if correct options are given
# on the commandline and start configurations
# ---------------------------------------------

# Check to validate number of parameters entered
if  [ -z "$seclogprofile" ] ; then
    display_help
    exit 0
fi


#start account configuration
update_seclog
