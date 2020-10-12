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
accountid=${accountid:-}

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

AWS_REGION='eu-west-1'
REGIONS_EXCEPT_IRELAND='["eu-north-1"]'
#REGIONS_EXCEPT_IRELAND='["ap-northeast-1","ap-northeast-2","ap-south-1","ap-southeast-1","ap-southeast-2","ca-central-1","eu-central-1","eu-north-1","eu-west-2","eu-west-3","sa-east-1","us-east-1","us-east-2","us-west-1","us-west-2"]'


# parameters for scripts
CFN_STACKSET_CONFIG_SECHUB_GLOBAL='CFN/EC-lz-Config-SecurityHub-all-regions.yml'


#   ---------------------
#   The command line help
#   ---------------------
display_help() {

    echo "Usage: $0--seclogprofile <Seclog Acc Profile> --accountid <target account id>"
    echo ""
    echo "   Provide "
    echo "   --seclogprofile     : The account profile of the central SecLog account as configured in your AWS profile"
    echo "   --accountid         : The account id to apply the stackset into"
    echo ""
    exit 1
}

#   ----------------------------
#   Configure Seclog Account
#   ----------------------------
update_stackset() {
    
    # Getting SecLog Account Id
    SECLOG_ID=`aws --profile $seclogprofile sts get-caller-identity --query 'Account' --output text`
    
  # Create StackInstances (globally except Ireland)
  aws cloudformation create-stack-instances \
  --stack-set-name 'SECLZ-Enable-Config-SecurityHub-Globally' \
  --accounts $accountid \
  --operation-preferences FailureToleranceCount=3,MaxConcurrentCount=5 \
  --parameter-overrides ParameterKey=SecLogMasterAccountId,ParameterValue=$SECLOG_ID \
  --regions $REGIONS_EXCEPT_IRELAND \
  --profile $seclogprofile

}

# ---------------------------------------------
# Check if correct options are given
# on the commandline and start configurations
# ---------------------------------------------

# Check to validate number of parameters entered
if  [ -z "$seclogprofile" ] || [ -z "$accountid" ] ; then
    display_help
    exit 0
fi


#start account configuration
update_stackset
