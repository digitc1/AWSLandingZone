#!/bin/sh

#   --------------------------------------------------------
#
#		Run in client account to accept pending invitations
#    for SecurityHub and GuardDuty
#
#       Usage
#       $ ./EC-Accept_SecHub-GD-client.sh ACCOUNT_Name SECLOG-Account
#        ex:
#          $ ./EC-Accept_SecHub-GD-client.sh DIGITS3_Drupal1 DIGITS3_SecLog
#
#
#   Version History
#
#   v1.0    J. Vandenbergen   Initial Version
#   --------------------------------------------------------

# --------------------
#	Parameters
#	--------------------
CLIENT=$1
SECLOG=$2
AWS_REGION='eu-west-1'

#   ---------------------
#   The command line help
#   ---------------------
display_help() {
    echo "Usage: $0 ACCOUNT_Name SECLOG_Account_Name" >&2
    echo ""
    echo "   Provide an account name to accept invitation and"
    echo "   and central SecLog account"
    echo ""
    exit 1
}


#   ----------------------------
#   Accept invitations from SecLog account
#   ----------------------------

accept_seclog_invitation() {

  SECLOG_ID=`aws --profile $SECLOG sts get-caller-identity --output text | awk '{print $1}'`

  echo ""
  echo " Utilisation: provide the account name to accept the pending invitations"
  echo ""
  echo "   Following account: $CLIENT"
  echo "   Will now accept invitations from this SecLog account: $SECLOG"
  echo ""


  #   ------------------------------------
  #   Accept Config aggregator invitation
  #   ------------------------------------

  AggregatorInvitation=`aws --profile $CLIENT configservice describe-pending-aggregation-requests --output text | grep $SECLOG_ID | awk '{print $1}'`
  echo "Pending invitation : $AggregatorInvitation"
  if [ -z $AggregatorInvitation ]
  then
    AggregatorInvitation=''
  else
    # There is an invitation from the SecLog account
    for region in $(aws --profile $CLIENT ec2 describe-regions --output text --query 'Regions[*].[RegionName]'); do
      aws --profile $CLIENT configservice put-aggregation-authorization --authorized-account-id $SECLOG_ID --authorized-aws-region $AWS_REGION --region $region
    done
  fi

  #   -----------------------------
  #   Accept GuardDuty invitation
  #   -----------------------------

  echo ""
  echo " GuardDuty"
  echo "------------"
  echo ""
  DetectorId=`aws --profile $CLIENT guardduty list-detectors --query 'DetectorIds' --output text`
  InvitationId=`aws --profile $CLIENT guardduty list-invitations --query 'Invitations[*].InvitationId' --output text`
  echo "  DetectorID client account:    $DetectorId"
  echo "  Client account invitation ID: $InvitationId"
  echo "  SecLog account ID:     $SECLOG_ID"
  echo ""

  # accepting GuardDuty invitation
  aws guardduty accept-invitation \
    --detector-id $DetectorId \
    --master-id $SECLOG_ID \
    --invitation-id $InvitationId \
    --profile $CLIENT

  #   Accepting to SecurityHub
  #   ----------------------

  echo ""
  echo " SecurityHub"
  echo "------------"
  echo ""

  InvitationId=`aws --profile $CLIENT securityhub list-invitations --query 'Invitations[*].InvitationId' --output text`

  # accepting SecurityHub invitation
  aws securityhub accept-invitation \
    --master-id $SECLOG_ID \
    --invitation-id $InvitationId \
    --profile $CLIENT

  # Print acceptance
  aws --profile $CLIENT securityhub describe-hub --output text | awk '{print "SecurityHub: ", $1, "\n - accepted: ", $2}'
}

# ---------------------------------------------
# Check if correct options are given
# on the commandline and send invitation
# ---------------------------------------------

# Simple check if two arguments are provided
if [ -z $2 ]; then
    display_help  # Call your function
    exit 0
fi

#accept seclog invitation
accept_seclog_invitation
