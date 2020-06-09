#!/bin/sh

#   --------------------------------------------------------
#
#               Run in Master account to invite new accounts
#
#               Automates adding an account to securityHub and Guardduty following:
#               - script creates a member in master account
#               - script invitest new member from master account
#               - script accepts invitation from member account
#
#       Usage
#       $ ./EC-Invite_SecHub-GD-master.sh ACCOUNT_Name SECLOG_Account_Name
#        ex:
#          $ ./EC-Invite_SecHub-GD-master.sh DIGITS3_Drupal1 DIGITS3_SecLog
#
#
#   Version History
#
#   v1.0    J. Vandenbergen   Initial Version
#   v1.1    A. Levret         Update Config aggregator (create, add account to existing aggregator)
#   --------------------------------------------------------

# --------------------
#       Parameters
#       --------------------
ORG_PROFILE=$1
CLIENT_PROFILE=$2
SECLOG_PROFILE=$3
ALL_REGIONS_EXCEPT_IRELAND='["ap-northeast-1","ap-northeast-2","ap-south-1","ap-southeast-1","ap-southeast-2","ca-central-1","eu-central-1","eu-west-2","eu-west-3","sa-east-1","us-east-1","us-east-2","us-west-1","us-west-2"]'

#   ---------------------
#   The command line help
#   ---------------------
display_help() {
    echo "Usage: $0 ORG_PROFILE CLIENT_PROFILE SECLOG_PROFILE" >&2
    echo
    echo "   Provide"
    echo "     - organization profile"
    echo "     - client account profile"
    echo "     - SecLog account profile"
    echo
    exit 1
}

#   ----------------------------
#   Inviting Client Account
#   ----------------------------

invite_client() {
  echo ""
  echo "Invite client account from Seclog account"
  echo "========================================="
  echo "Utilisation: Script will invite account to SecLog account on multiple AWS services (Config aggregator, GuardDuty and Security Hub)"

  echo "   Following account: $CLIENT_PROFILE"
  echo "   Will be invited to this SecLog account: $SECLOG_PROFILE"
  
  echo "  If this is correct press enter to continue"
  read -p "  or CTRL-C to break"

  #   ----------------------
  #   Adding to Config aggregator
  #   ----------------------

  echo ""
  echo " Adding new account to Config aggregator"
  echo "------------"
  echo ""

  SECLOG_ID=`aws --profile $SECLOG_PROFILE sts get-caller-identity --query 'Account' --output text`
  
  AGGREGATOR_NAME=`aws --profile $SECLOG_PROFILE configservice describe-configuration-aggregators --output text | grep CONFIGURATIONAGGREGATORS | awk '{print $3}'`
  
  CLIENT_ID=`aws --profile $CLIENT_PROFILE sts get-caller-identity --query 'Account' --output text`
  
  EMAIL=`aws organizations --profile $ORG_PROFILE list-accounts --query 'Accounts[*].[Id, Name, Email]' --output text | grep $CLIENT_ID | awk '{print $3}'`

  if [ -z "$AGGREGATOR_NAME" ]
  then
    # There is no existing aggregator, so we create one by adding as first account the client account
    aws --profile $SECLOG_PROFILE configservice put-configuration-aggregator --configuration-aggregator-name SecLogAggregator --account-aggregation-sources "[{\"AccountIds\": [\"$CLIENT_ID\"],\"AllAwsRegions\": true}]"
  else
    export ListAccountIds=""
    export delimiter='","'
    for i in `aws --profile $SECLOG_PROFILE configservice describe-configuration-aggregators --output text --query 'ConfigurationAggregators[*].AccountAggregationSources[*].AccountIds'`
      do
        ListAccountIds="${ListAccountIds}$i$delimiter"
      done
    ListAccountIds=`echo $ListAccountIds | sed s/\"\.\"$//g`

    # There is an existing aggregator, so we get the list of linked account IDs and we add the wished account ID to this list
    aws --profile $SECLOG_PROFILE configservice put-configuration-aggregator --configuration-aggregator-name SecLogAggregator --account-aggregation-sources "[{\"AccountIds\": [\"$ListAccountIds\",\"$CLIENT_ID\"],\"AllAwsRegions\": true}]"

    # Old command using 'jq'
    # ListAccountIds=`aws --profile $SECLOG_PROFILE configservice describe-configuration-aggregators | jq --raw-output '.ConfigurationAggregators | map(.AccountAggregationSources[].AccountIds[]) | join ("\",\"")'`
  fi
  #   ----------------------
  #   Adding to GuardDuty
  #   ----------------------

  echo ""
  echo "Adding new account to Guardduty"
  echo "------------"
  echo ""
  DetectorId=`aws --profile $SECLOG_PROFILE guardduty list-detectors --query 'DetectorIds' --output text`
  echo "  DetectorID SecLog account: $DetectorId"
  echo "  Client account ID: $CLIENT_ID"
  echo "  Client account email: $EMAIL"
  echo ""
  
  # adding member account
  aws guardduty create-members \
    --detector-id $DetectorId \
    --account-details AccountId=$CLIENT_ID,Email=$EMAIL \
    --profile $SECLOG_PROFILE

  # inviting member account
  aws guardduty invite-members \
    --detector-id $DetectorId \
    --account-ids $CLIENT_ID \
    --profile $SECLOG_PROFILE

  #   ----------------------
  #   Adding to SecurityHub
  #   ----------------------

  echo ""
  echo "Adding new account to SecurityHub"
  echo "--------------"
  echo ""

  # adding member account
  aws securityhub create-members \
    --account-details AccountId=$CLIENT_ID,Email=$EMAIL \
    --profile $SECLOG_PROFILE

  # inviting member account
  aws securityhub invite-members \
    --account-ids $CLIENT_ID \
    --profile $SECLOG_PROFILE


  #   ----------------------------------------------
  #   Granting the client to use Event-Bus in SecLog
  #   ----------------------------------------------

  echo ""
  echo "Granting new account access to EventBus"
  echo "--------------"
  echo ""

  aws events put-permission \
    --action events:PutEvents \
    --principal $CLIENT_ID \
    --statement-id CLIENT \
    --profile $SECLOG_PROFILE

  #   -------------------------------------------------------------------------
  #   Enabling config and security Hub globally in all regions (except Ireland)
  #   -------------------------------------------------------------------------

  echo "Enabling config and SecurityHub globally in all regions (except Ireland)"
  echo "--------------"
  echo ""
  
  # Create StackInstances (globally except Ireland)
  aws cloudformation create-stack-instances \
  --stack-set-name 'SECLZ-Enable-Config-SecurityHub-Globally' \
  --accounts $CLIENT_ID \
  --parameter-overrides ParameterKey=SecLogMasterAccountId,ParameterValue=$SECLOG_ID \
  --regions $ALL_REGIONS_EXCEPT_IRELAND \
  --profile $SECLOG_PROFILE

}

# ---------------------------------------------
# Check if correct options are given
# on the commandline and send invitation
# ---------------------------------------------

# Simple check if 3 arguments are provided
if [ -z $3 ]; then
    display_help  # Call your function
    exit 0
fi

#invite client to seclog account
invite_client
