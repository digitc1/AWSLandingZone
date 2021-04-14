#!/bin/bash

#   --------------------------------------------------------
#   Updates/1.3.4/EC-Update-SecLog.sh
#   
#   v1.0.0    J. Silva          Initial version.
#   --------------------------------------------------------

#   --------------------
#       Parameters
#   --------------------

seclogprofile=${seclogprofile:-}
splunkprofile=${splunkprofile:-}
logdestination=${logdestination:-}
cloudtrailintegration=${cloudtrailintegration:-true}
securityhubintegration=${securityhubintegration:-true}
guarddutyintegration=${guarddutyintegration:-true}
batch=${batch:-false}
cloudtrailgroupname=${cloudtrailgroupname:-}
insightgroupname=${insightgroupname:-}
guarddutygroupname=${guarddutygroupname:-}
securityhubgroupname=${securityhubgroupname:-}
configgroupname=${configgroupname:-}

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


AWS_REGION='eu-west-1'

#   --------------------
#       Templates
#   --------------------

CFN_BUCKETS_TEMPLATE='../../CFN/EC-lz-s3-buckets.yml'
CFN_TAGS_PARAMS_FILE='../../CFN/EC-lz-TAGS-params.json'
CFN_GUARDDUTY_DETECTOR_TEMPLATE='../../CFN/EC-lz-guardDuty-detector.yml'
CFN_SECURITYHUB_LOG_TEMPLATE='../../CFN/EC-lz-config-securityhub-logging.yml'
CFN_LOG_TEMPLATE='../../CFN/EC-lz-config-cloudtrail-logging.yml'
CFN_GUARDDUTY_TEMPLATE_GLOBAL='../../CFN/EC-lz-Config-Guardduty-all-regions.yml'

CFN_LAMBDAS_BUCKET_TEMPLATE='../../CFN/EC-lz-s3-bucket-lambda-code.yml'
CFN_LAMBDAS_TEMPLATE='../../CFN/EC-lz-logshipper-lambdas.yml'


CFN_NOTIFICATIONS_CT_TEMPLATE='../../CFN/EC-lz-notifications.yml'

#   ---------------------
#   The command line help
#   ---------------------
display_help() {

    echo "Usage: $0 <params>"
    echo ""
    echo "   Provide "
    echo "   --seclogprofile            : The account profile of the central SecLog account as configured in your AWS profile"
    echo "   --splunkprofile            : The Splunk account profile as configured in your AWS profile"
    echo "   --logdestination           : The name of the DG of the firehose log destination"
    echo "   --cloudtrailintegration    : Flag to enable or disable CloudTrail seclog integration. Default: true (optional)"
    echo "   --guarddutyintegration     : Flag to enable or disable GuardDuty seclog integration. Default: true (optional)"
    echo "   --securityhubintegration   : Flag to enable or disable SecurityHub seclog integration. Default: true (optional)"
    echo "   --cloudtrailgroupname      : The custom name for CloudTrail Cloudwatch loggroup name (optional)"
    echo "   --insightgroupname         : The custom name for CloudTrail Insight Cloudwatch loggroup name (optional)"
    echo "   --guarddutygroupname       : The custom name for GuardDuty Cloudwatch loggroup name (optional)"
    echo "   --securityhubgroupname     : The custom name for SecurityHub Cloudwatch loggroup name (optional)"
    echo "   --configgroupname          : The custom name for AWSConfig Cloudwatch loggroup name (optional)"
    echo "   --batch                    : Flag to enable or disable batch execution mode. Default: false (optional)"
    echo ""
    exit 1
}

#   ----------------------------
#   Update Seclog Account
#   ----------------------------
update_seclog() {


    LZ_VERSION=`cat ../../EC-SLZ-Version.txt | xargs`
    CUR_LZ_VERSION=`aws --profile $seclogprofile ssm get-parameter --name /org/member/SLZVersion --query "Parameter.Value" --output text`


    # Getting SecLog Account Id
    SECLOG_ACCOUNT_ID=`aws --profile $seclogprofile sts get-caller-identity --query 'Account' --output text`

    if [ "$cloudtrailintegration" == "true" ] || [ "$securityhubintegration" == "true" ]; then
        # Getting C2 Splunk Account Id
        SPLUNK_ACCOUNT_ID=`aws --profile $splunkprofile sts get-caller-identity --query 'Account' --output text`

        # Getting available log destinations from
        DESCRIBE_DESTINATIONS=`aws --profile $splunkprofile  logs describe-destinations`

        # Extract select Log destination details
        FIREHOSE_ARN=`echo $DESCRIBE_DESTINATIONS | jq -r '.destinations[]| select (.destinationName | contains("'$logdestination'")) .arn'`
    fi



    echo ""
    echo "- This script will update a the SecLog account to version $LZ_VERSION with following settings:"
    echo "   ----------------------------------------------------"
    echo "     SecLog Account to be configured:  $seclogprofile"
    echo "     SecLog Account Id:                $SECLOG_ACCOUNT_ID"
    echo "     CloudTrail integration with Splunk:  $cloudtrailintegration"
    echo "     GuardDuty integration with Splunk:   $guarddutyintegration"
    echo "     SecurityHub integration with Splunk: $securityhubintegration"
    if [[ ("$cloudtrailintegration" == "true" || "$guarddutyintegration" == "true" || "$securityhubintegration" == "true" ) ]]; then
      echo "     Splunk Account Id:                   $SPLUNK_ACCOUNT_ID"
      echo "     Log Destination ARN:                 $FIREHOSE_ARN"
    fi
    
    if  [ ! -z "$insightgroupname" ] ; then
        echo "     CloudTrail Insight loggroup name:            $insightgroupname"
    fi

    if  [ ! -z "$cloudtrailgroupname" ] ; then
        echo "     CloudTrail loggroup name:             $cloudtrailgroupname"
    fi
    
    if  [ ! -z "$guarddutygroupname" ] ; then
         echo "     Guardduty loggroup name:   $guarddutygroupname"
    fi
    
    if  [ ! -z "$securityhubgroupname" ] ; then
        echo "     SecurityHub loggroup name:           $securityhubgroupname"
    fi
    
    if  [ ! -z "$configgroupname" ] ; then
        echo "     AWSConfig loggroup name:           $configgroupname"
    fi
    echo "     in AWS Region:                    $AWS_REGION"
    echo "   ----------------------------------------------------"
    echo ""
    
    if [ "$batch" == "false" ] ; then
        echo "   If this is correct press enter to continue"
        read -p "  or CTRL-C to break"
    fi

    #   ------------------------------------
    # Store notification-E-mail, OrgID, SecAccountID in SSM parameters
    #   ------------------------------------

    echo ""
    echo "- Storing SSM parameters for Seclog account"
    echo "--------------------------------------------------"
    echo ""
    echo "  populating: "
    echo "    - /org/member/SLZVersion"

    
    
    aws --profile $seclogprofile ssm put-parameter --name /org/member/SLZVersion --type String --value $LZ_VERSION --overwrite

    if  [ ! -z "$cloudtrailgroupname" ] ; then
        aws --profile $seclogprofile ssm put-parameter --name /org/member/SecLog_cloudtrail-groupname --type String --value $cloudtrailgroupname --overwrite
    else
        $cloudtrailgroupname=`aws --profile $seclogprofile ssm get-parameter --name "/org/member/SecLog_cloudtrail-groupname" --output text --query 'Parameter.Value'`
    fi
    
    if  [ ! -z "$insightgroupname" ] ; then
        aws --profile $seclogprofile ssm put-parameter --name /org/member/SecLog_insight-groupname --type String --value $insightgroupname --overwrite
    else
        $insightgroupname=`aws --profile $seclogprofile ssm get-parameter --name "/org/member/SecLog_insight-groupname" --output text --query 'Parameter.Value'`
    fi
    
    if  [ ! -z "$guarddutygroupname" ] ; then
        aws --profile $seclogprofile ssm put-parameter --name /org/member/SecLog_guardduty-groupname --type String --value $guarddutygroupname --overwrite
    else
        $guarddutygroupname=`aws --profile $seclogprofile ssm get-parameter --name "/org/member/SecLog_guardduty-groupname" --output text --query 'Parameter.Value'`
    fi
    
    if  [ ! -z "$securityhubgroupname" ] ; then
        aws --profile $seclogprofile ssm put-parameter --name /org/member/SecLog_securityhub-groupname --type String --value $securityhubgroupname --overwrite
    else
        $securityhubgroupname=`aws --profile $seclogprofile ssm get-parameter --name "/org/member/SecLog_securityhub-groupname" --output text --query 'Parameter.Value'`
    fi

    if  [ ! -z "$configgroupname" ] ; then
        aws --profile $seclogprofile ssm put-parameter --name /org/member/SecLog_config-groupname --type String --value $configgroupname --overwrite
    else
        $configgroupname=`aws --profile $seclogprofile ssm get-parameter --name "/org/member/SecLog_config-groupname" --output text --query 'Parameter.Value'`
    fi

    #   ------------------------------------
    #   Cloudtrail bucket / Config bucket / Access_log bucket ...
    #   ------------------------------------

    echo ""
    echo "- Cloudtrail bucket / Config bucket / Access_log bucket ... "
    echo "-----------------------------------------------------------"
    echo ""

    StackName=SECLZ-Central-Buckets
    aws cloudformation update-stack \
    --stack-name $StackName \
    --template-body file://$CFN_BUCKETS_TEMPLATE \
    --parameters file://$CFN_TAGS_PARAMS_FILE \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $seclogprofile

    
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "UPDATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName


    #   ------------------------------------
    #   Update guardduty in seclog account ...
    #   ------------------------------------

    echo ""
    echo "- Update guardduty in seclog account"
    echo "----------------------------------------"
    echo ""

    StackName=SECLZ-Guardduty-detector
    aws cloudformation update-stack \
    --stack-name $StackName \
    --template-body file://$CFN_GUARDDUTY_DETECTOR_TEMPLATE \
    --capabilities CAPABILITY_IAM \
    --profile $seclogprofile

    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "UPDATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName


    #   ------------------------------------
	#   Update Cloudwatch Event Rules to Cloudwatch logs for Security Hub
	#   ------------------------------------

    if  [ "$securityhubintegration" == "true" ]; then

        echo ""
        echo "- Update Cloudwatch Event Rules to Cloudwatch logs for Security Hub"
        echo "---------------------------------------"
        echo ""

        aws cloudformation update-stack \
        --stack-name 'SECLZ-CloudwatchLogs-SecurityHub' \
        --template-body file://$CFN_SECURITYHUB_LOG_TEMPLATE \
        --capabilities CAPABILITY_IAM \
        --profile $seclogprofile \
        --parameters ParameterKey=FirehoseDestinationArn,ParameterValue=$FIREHOSE_ARN 

        StackName="SECLZ-CloudwatchLogs-SecurityHub"
        aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
        while [ `aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` = "UPDATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
        aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName

        sleep 5

    fi

    #   ------------------------------------
    #   Updating config, cloudtrail, SNS notifications
    #   ------------------------------------


    echo ""
    echo "- Updating config, cloudtrail, SNS notifications"
    echo "--------------------------------------------------"
    echo ""

    cloudtrailparams="ParameterKey=EnableSecLogForCloudTrailParam,ParameterValue=$cloudtrailintegration"
    if [ "$cloudtrailintegration" == "true" ]; then
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


    #   ------------------------------------
    #   Set Resource Policy to send Events to LogGroups
    #   ------------------------------------

    echo ""
    echo "-  Set Resource Policy to send Events to LogGroups"
    echo "--------------------------------------------------"
    echo ""

    resources='["arn:aws:logs:*:'$SECLOG_ACCOUNT_ID':log-group:/aws/events/*:*"'
     
    if  [ ! -z "$guarddutygroupname" ] ; then
        resources+=',"arn:aws:logs:*:'$SECLOG_ACCOUNT_ID':log-group:'$guarddutygroupname':*"'
    fi
    if  [ ! -z "$securityhubgroupname" ] ; then
        resources+=',"arn:aws:logs:*:'$SECLOG_ACCOUNT_ID':log-group:'$securityhubgroupname':*"'
    fi
    if  [ ! -z "$configgroupname" ] ; then
        resources+=',"arn:aws:logs:*:'$SECLOG_ACCOUNT_ID':log-group:'$configgroupname':*"'
    fi
    resources+=']'

    cat > ./policy.json << EOM
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TrustEventsToStoreLogEvent",
      "Effect": "Allow",
      "Principal": {
        "Service": ["events.amazonaws.com","delivery.logs.amazonaws.com"]
      },
      "Action": [
        "logs:PutLogEvents",
        "logs:CreateLogStream"
      ],
      "Resource": ${resources}
    }
  ]
}
EOM

    aws --profile $seclogprofile logs put-resource-policy --policy-name TrustEventsToStoreLogEvents --policy-document file://./policy.json
    rm ./policy.json


    #   ------------------------------------
    #   Logshipper lambdas for CloudTrail and AWSConfig ...
    #   ------------------------------------

    echo ""
    echo "- Logshipper lambdas for CloudTrail and AWSConfig ... "
    echo "-----------------------------------------------------------"
    echo ""

    SECLOG_ACCOUNT_ID=`aws --profile $seclogprofile sts get-caller-identity --query 'Account' --output text`
    REPO="lambda-artefacts-$SECLOG_ACCOUNT_ID"

    
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
    #   Enable Notifications for CIS cloudtrail metrics filters
    #   ------------------------------------


    echo ""
    echo "- Enable Notifications for CIS cloudtrail metrics filters"
    echo "---------------------------------------"
    echo ""

    aws cloudformation update-stack \
    --stack-name 'SECLZ-Notifications-Cloudtrail' \
    --template-body file://$CFN_NOTIFICATIONS_CT_TEMPLATE \
    --profile $seclogprofile

    StackName="SECLZ-Notifications-Cloudtrail"
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "UPDATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName


}

function version { echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'; }

# ---------------------------------------------
# Check if correct options are given
# on the commandline and start configurations
# ---------------------------------------------



if  [ -z "$seclogprofile" ] ; then
    display_help
    exit 0
fi

if [[ ( -z "$logdestination" || -z "$splunkprofile" ) && ( "$cloudtrailintegration" == "true" ||  "$guarddutyintegration" == "true"  ||  "$securityhubintegration" == "true" ) ]]; then
    display_help
    exit 0
fi



#start account configuration
update_seclog
