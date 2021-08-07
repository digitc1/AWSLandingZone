#!/bin/bash

#   --------------------
#       Parameters
#   --------------------
cdk_release=1.117.0

seclog_accountid=${seclog_accountid:-}
linked_accountids=${linked_accountids:-}

# Parameter parsing
while [ $# -gt 0 ]; do

   if [[ $1 == *"--"* ]]; then
        param="${1/--/}"
        declare $param="$2"
   fi

  shift
done

#   ---------------------
#   The command line help
#   ---------------------
display_help() {
    echo "Usage: $0 <params>"
    echo ""
    echo "   Provide "
    echo "   --seclog_accountid     : (mandatory) the AWS account ID of the seclog account"
    echo "   [--linked_accountids]  : (optional) a comma separated list of the AWS linked account IDs of the SECLOG account"
    echo ""
    exit 1
}

# Check to validate number of parameters entered
if  [ -z "$seclog_accountid" ] ; then
    display_help
    exit 0
fi

# Check for local CDK, if not present install local cdk
if [ -d "./node_modules" ]; then
    if [ ! -d "./node_modules/aws-cdk" ]; then
        npm install aws-cdk@${cdk-release}
    fi
fi

./node_modules/aws-cdk/bin/cdk destroy \
    --context seclog_accountid=$seclog_accountid \
    --context linked_accountids=$linked_accountids \
    SECLZ-*

    

