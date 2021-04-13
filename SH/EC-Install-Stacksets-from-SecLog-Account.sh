#!/bin/sh

#   --------------------------------------------------------
#
#               Create stackset instances on new accounts
#
#               Automates the deployment of the stackset instances from the seclog on multiple accounts:
#               - enabling config and security Hub globally in all regions (except Ireland)
#               - enabling guardduty globally in all regions (except Ireland)
#
#       Usage
#       $ ./EC-Install-Stacksets-from-SecLog-Account.sh ACCOUNT_IDs SECLOG_Account_Name
#        ex:
#          $ ./EC-Install-Stacksets-from-SecLog-Account.sh 0011223344,0055667788 DIGITS3_SecLog
#
#
#   Version History
#
#   v1.0    J. Silva   Initial Version
#   --------------------------------------------------------

# --------------------
#       Parameters
#       --------------------

CLIENT_IDS=$1
SECLOG_PROFILE=$2
ALL_REGIONS_EXCEPT_IRELAND='["ap-northeast-1","ap-northeast-2","ap-south-1","ap-southeast-1","ap-southeast-2","ca-central-1","eu-central-1","eu-north-1","eu-west-2","eu-west-3","sa-east-1","us-east-1","us-east-2","us-west-1","us-west-2"]'

#   ---------------------
#   The command line help
#   ---------------------
display_help() {
    echo "Usage: $0 ACCOUNT_IDS SECLOG_PROFILE " >&2
    echo
    echo "   Provide"
    echo "     - client account ids (comma separated)"
    echo "     - SecLog account profile"
    echo
    exit 1
}

#   ----------------------------
#   Inviting Client Account
#   ----------------------------

create_stackset_instances_client() {
  echo ""
  echo "Create stackset instances on client account from Seclog account"
  echo "========================================="
  echo "Script will create stackset instances on the account ids provided from to SecLog account on multiple AWS regions"

  echo "   Client account id(s): $CLIENT_IDS"
  echo "   SecLog account:       $SECLOG_PROFILE"
  
  SECLOG_ID=`aws --profile $SECLOG_PROFILE sts get-caller-identity --query 'Account' --output text`
  
  #   -------------------------------------------------------------------------
  #   Enabling config and security Hub globally in all regions (except Ireland)
  #   -------------------------------------------------------------------------

  echo "Enabling config and SecurityHub globally in all regions (except Ireland)"
  echo "--------------"
  echo ""
  
  # Create StackInstances (globally except Ireland)
  aws cloudformation create-stack-instances \
  --stack-set-name 'SECLZ-Enable-Config-SecurityHub-Globally' \
  --accounts `echo $CLIENT_IDS | sed 's/,/ /g'` \
  --operation-preferences FailureToleranceCount=3,MaxConcurrentCount=10,RegionConcurrencyType=PARALLEL \
  --parameter-overrides ParameterKey=SecLogMasterAccountId,ParameterValue=$SECLOG_ID \
  --regions $ALL_REGIONS_EXCEPT_IRELAND \
  --profile $SECLOG_PROFILE

  #   -------------------------------------------------------------------------
  #   Enabling guardduty globally in all regions (except Ireland)
  #   -------------------------------------------------------------------------

  echo "Enabling guardduty globally in all regions"
  echo "--------------"
  echo ""

  # Create StackInstances (globally excluding Ireland)
    aws cloudformation create-stack-instances \
    --stack-set-name 'SECLZ-Enable-Guardduty-Globally' \
    --accounts `echo $CLIENT_IDS | sed 's/,/ /g'` \
    --parameter-overrides ParameterKey=SecLogMasterAccountId,ParameterValue=$SECLOG_ID \
    --operation-preferences FailureToleranceCount=3,MaxConcurrentCount=10,RegionConcurrencyType=PARALLEL \
    --regions $ALL_REGIONS_EXCEPT_IRELAND \
    --profile $SECLOG_PROFILEs

}

# ---------------------------------------------
# Check if correct options are given
# on the commandline and send invitation
# ---------------------------------------------

# Simple check if 3 arguments are provided
if [ -z $2 ]; then
    display_help  # Call your function
    exit 0
fi

#invite client to seclog account
create_stackset_instances_client
