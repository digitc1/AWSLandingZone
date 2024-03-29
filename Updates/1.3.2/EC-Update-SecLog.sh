#!/bin/bash

#   --------------------------------------------------------
#   Updates/1.3.2/EC-Update-Seclog.sh
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
   fi

  shift
done

# Script Spinner waiting for cloudformation completion
export i=1
export sp="/-\|"

#   --------------------
#       Templates
#   --------------------

CFN_BUCKETS_TEMPLATE='../../CFN/EC-lz-s3-buckets.yml'
CFN_BUCKETS_TEMPLATE_CLEANUP='./EC-lz-s3-buckets.yml'
CFN_TAGS_PARAMS_FILE='../../CFN/EC-lz-TAGS-params.json'
CFN_LAMBDAS_BUCKET_TEMPLATE='../../CFN/EC-lz-s3-bucket-lambda-code.yml'
CFN_LAMBDAS_TEMPLATE='../../CFN/EC-lz-logshipper-lambdas.yml'

#   ---------------------
#   The command line help
#   ---------------------
display_help() {

    echo "Usage: $0 --seclogprofile <Seclog Acc Profile>"
    echo ""
    echo "   Provide "
    echo "   --seclogprofile           : The account profile of the central SecLog account as configured in your AWS profile"
    echo ""
    exit 1
}

#   ----------------------------
#   Update Seclog Account
#   ----------------------------
update_seclog() {

    #   ------------------------------------
    # Store notification-E-mail, OrgID, SecAccountID in SSM parameters
    #   ------------------------------------

    echo ""
    echo "- Storing SSM parameters for Seclog account"
    echo "--------------------------------------------------"
    echo ""
    echo "  populating: "
    echo "    - /org/member/SLZVersion"

    LZ_VERSION=`cat ../../EC-SLZ-Version.txt | xargs`

    aws --profile $seclogprofile ssm put-parameter --name /org/member/SLZVersion --type String --value $LZ_VERSION --overwrite

    #   ------------------------------------
    #   S3 Bucket Template cleanup ...
    #   ------------------------------------

    echo ""
    echo "- S3 Bucket Template cleanup ... "
    echo "-----------------------------------------------------------"
    echo ""

    aws cloudformation update-stack \
    --stack-name 'SECLZ-Central-Buckets' \
    --template-body file://$CFN_BUCKETS_TEMPLATE_CLEANUP \
    --parameters file://$CFN_TAGS_PARAMS_FILE \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $seclogprofile

    StackName=SECLZ-Central-Buckets
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "UPDATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName


    #   ------------------------------------
    #   Logshipper lambdas for CloudTrail and AWSConfig ...
    #   ------------------------------------

    echo ""
    echo "- Logshipper lambdas for CloudTrail and AWSConfig ... "
    echo "-----------------------------------------------------------"
    echo ""

    SECLOG_ACCOUNT_ID=`aws --profile $seclogprofile sts get-caller-identity --query 'Account' --output text`
    REPO="lambda-artefacts-$SECLOG_ACCOUNT_ID"

    aws cloudformation create-stack \
    --stack-name 'SECLZ-LogShipper-Lambdas-Bucket' \
    --template-body file://$CFN_LAMBDAS_BUCKET_TEMPLATE \
    --capabilities CAPABILITY_NAMED_IAM \
    --enable-termination-protection \
    --profile $seclogprofile
    
    StackName=SECLZ-LogShipper-Lambdas-Bucket
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "CREATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName


    NOW=`date +"%d%m%Y"`
    LOGSHIPPER_TEMPLATE="EC-lz-logshipper-lambdas-packaged.yml"
    LOGSHIPPER_TEMPLATE_WITH_CODE="EC-lz-logshipper-lambdas.yml"
    CLOUDTRAIL_LAMBDA_CODE="CloudtrailLogShipper-$NOW.zip"
    CONFIG_LAMBDA_CODE="ConfigLogShipper-$NOW.zip"

    zip -j $CLOUDTRAIL_LAMBDA_CODE ../../LAMBDAS/CloudtrailLogShipper.py
    zip -j $CONFIG_LAMBDA_CODE ../../LAMBDAS/ConfigLogShipper.py

    
    awk -v cl=$CLOUDTRAIL_LAMBDA_CODE -v co=$CONFIG_LAMBDA_CODE '{ sub(/##cloudtrailCodeURI##/,cl);gsub(/##configCodeURI##/,co);print }' $CFN_LAMBDAS_TEMPLATE > $LOGSHIPPER_TEMPLATE_WITH_CODE

    aws cloudformation package --template $LOGSHIPPER_TEMPLATE_WITH_CODE --s3-bucket $REPO --output-template-file $LOGSHIPPER_TEMPLATE --profile $seclogprofile

    aws cloudformation deploy --stack-name  'SECLZ-LogShipper-Lambdas' \
    --template-file $LOGSHIPPER_TEMPLATE \
    --capabilities CAPABILITY_IAM \
    --profile $seclogprofile

    StackName=SECLZ-LogShipper-Lambdas
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

    aws cloudformation update-termination-protection \
        --enable-termination-protection \
        --stack-name $StackName \
        --profile $seclogprofile
   
    rm -rf $LOGSHIPPER_TEMPLATE
    rm -rf $LOGSHIPPER_TEMPLATE_WITH_CODE
    rm -rf $CLOUDTRAIL_LAMBDA_CODE
    rm -rf $CONFIG_LAMBDA_CODE


    #   ------------------------------------
    #   Cloudtrail bucket / Config bucket / Access_log bucket ...
    #   ------------------------------------

    echo ""
    echo "- Cloudtrail bucket / Config bucket / Access_log bucket ... "
    echo "-----------------------------------------------------------"
    echo ""

    aws cloudformation update-stack \
    --stack-name 'SECLZ-Central-Buckets' \
    --template-body file://$CFN_BUCKETS_TEMPLATE \
    --parameters file://$CFN_TAGS_PARAMS_FILE \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $seclogprofile

    StackName=SECLZ-Central-Buckets
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "UPDATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName



}

# ---------------------------------------------
# Check if correct options are given
# on the commandline and start configurations
# ---------------------------------------------



if  [ -z "$seclogprofile" ] ; then
    display_help
    exit 0
fi



#start account configuration
update_seclog
