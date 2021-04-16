#!/bin/bash

#   --------------------------------------------------------
#   Updates/1.4.0/EC-Update-Client.sh
#   
#   v1.0.0    J. Silva          Initial version.
#   --------------------------------------------------------

#   --------------------
#       Parameters
#   --------------------

clientaccprofile=${clientaccprofile:-}
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

CFN_GUARDDUTY_DETECTOR_TEMPLATE='../../CFN/EC-lz-guardDuty-detector.yml'
CFN_NOTIFICATIONS_CT_TEMPLATE='../../CFN/EC-lz-notifications.yml'
CFN_LOG_TEMPLATE='../../CFN/EC-lz-config-cloudtrail-logging.yml'


#   ---------------------
#   The command line help
#   ---------------------
display_help() {

    echo "Usage: $0 <params>"
    echo ""
    echo "   Provide "
    echo "   --clientaccprofile        : The profile of the client account as configured in your AWS profile"
    echo "   --seclogprofile           : The account profile of the central SecLog account as configured in your AWS profile"
    echo ""
    exit 1
}

#   ----------------------------
#   Update Client Account
#   ----------------------------
update_client() {

    LZ_VERSION=`cat ../../EC-SLZ-Version.txt | xargs`
    CUR_LZ_VERSION=`aws --profile $clientaccprofile ssm get-parameter --name /org/member/SLZVersion --query "Parameter.Value" --output text`


    #   ------------------------------------
    # Store notification-E-mail, OrgID, SecAccountID in SSM parameters
    #   ------------------------------------

    echo ""
    echo "- Storing SSM parameters for Seclog account"
    echo "--------------------------------------------------"
    echo ""
    echo "  populating: "
    echo "    - /org/member/SLZVersion"
    echo "    - /org/member/SecLog_cloudtrail-groupname"
    echo "    - /org/member/SecLog_insight-groupname"
    echo "    - /org/member/SecLog_guardduty-groupname"
    echo "    - /org/member/SecLog_securityhub-groupname"
    echo "    - /org/member/SecLog_config-groupname"
    
    aws --profile $clientaccprofile ssm put-parameter --name /org/member/SLZVersion --type String --value $LZ_VERSION --overwrite

    cloudtrailgroupname=`aws --profile $seclogprofile ssm get-parameter --name "/org/member/SecLog_cloudtrail-groupname" --output text --query 'Parameter.Value'`
    insightgroupname=`aws --profile $seclogprofile ssm get-parameter --name "/org/member/SecLog_insight-groupname" --output text --query 'Parameter.Value'`
    guarddutygroupname=`aws --profile $seclogprofile ssm get-parameter --name "/org/member/SecLog_guardduty-groupname" --output text --query 'Parameter.Value'`
    securityhubgroupname=`aws --profile $seclogprofile ssm get-parameter --name "/org/member/SecLog_securityhub-groupname" --output text --query 'Parameter.Value'`
    configgroupname=`aws --profile $seclogprofile ssm get-parameter --name "/org/member/SecLog_config-groupname" --output text --query 'Parameter.Value'`
    
    

    if  [ ! -z "$cloudtrailgroupname" ] ; then
        aws --profile $clientaccprofile ssm put-parameter --name /org/member/SecLog_cloudtrail-groupname --type String --value $cloudtrailgroupname --overwrite
    else
        aws --profile $clientaccprofile ssm put-parameter --name /org/member/SecLog_cloudtrail-groupname --type String --value "/aws/cloudtrail" --overwrite
    fi
    
    if  [ ! -z "$insightgroupname" ] ; then
        aws --profile $clientaccprofile ssm put-parameter --name /org/member/SecLog_insight-groupname --type String --value $insightgroupname --overwrite
    else
        aws --profile $clientaccprofile ssm put-parameter --name /org/member/SecLog_cloudtrail-groupname --type String --value "/aws/cloudtrail/insight" --overwrite
    fi
    
    for region in $(aws --profile $clientaccprofile ec2 describe-regions --output text --query "Regions[?RegionName!='ap-northeast-3'].[RegionName]"); do
        if  [ ! -z "$guarddutygroupname" ] ; then
            aws --profile $clientaccprofile --region $region ssm put-parameter --name /org/member/SecLog_guardduty-groupname --type String --value $guarddutygroupname --overwrite
        else
            aws --profile $clientaccprofile --region $region ssm put-parameter --name /org/member/SecLog_cloudtrail-groupname --type String --value "/aws/events/guardduty" --overwrite
        fi
    done
    
    if  [ ! -z "$securityhubgroupname" ] ; then
        aws --profile $clientaccprofile ssm put-parameter --name /org/member/SecLog_securityhub-groupname --type String --value $securityhubgroupname --overwrite
    else
        aws --profile $clientaccprofile ssm put-parameter --name /org/member/SecLog_cloudtrail-groupname --type String --value "/aws/events/securityhub" --overwrite
    fi

    if  [ ! -z "$configgroupname" ] ; then
        aws --profile $clientaccprofile ssm put-parameter --name /org/member/SecLog_config-groupname --type String --value $configgroupname --overwrite
    else
        aws --profile $clientaccprofile ssm put-parameter --name /org/member/SecLog_cloudtrail-groupname --type String --value "/aws/events/config" --overwrite
    fi


    #   ------------------------------------
    #   Update guardduty in client account ...
    #   ------------------------------------

    echo ""
    echo "- Update guardduty in new client account"
    echo "----------------------------------------"
    echo ""

    StackName=SECLZ-Guardduty-detector
    aws cloudformation update-stack \
    --stack-name $StackName \
    --template-body file://$CFN_GUARDDUTY_DETECTOR_TEMPLATE \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $clientaccprofile

    aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "UPDATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName


    #   ------------------------------------
    #   Updating config, cloudtrail, SNS notifications
    #   ------------------------------------


    echo ""
    echo "- Updating config, cloudtrail, SNS notifications"
    echo "--------------------------------------------------"
    echo ""


    aws cloudformation update-stack \
    --stack-name 'SECLZ-config-cloudtrail-SNS' \
    --template-body file://$CFN_LOG_TEMPLATE \
    --capabilities CAPABILITY_NAMED_IAM \
    --profile $clientaccprofile 

    StackName="SECLZ-config-cloudtrail-SNS"
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "UPDATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $seclogprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName



    echo ""
    echo "- Update Enabling Notifications for cloudtrail"
    echo "-------------------------------------"
    echo ""

    StackName=SECLZ-Notifications-Cloudtrail
    aws cloudformation update-stack \
    --stack-name $StackName \
    --template-body file://$CFN_NOTIFICATIONS_CT_TEMPLATE \
    --profile $clientaccprofile

    aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName
    while [ `aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName | awk '{print$2}'` == "UPDATE_IN_PROGRESS" ]; do printf "\b${sp:i++%${#sp}:1}"; sleep 1; done
    aws --profile $clientaccprofile cloudformation describe-stacks --query 'Stacks[*][StackName, StackStatus]' --output text | grep $StackName


}


# ---------------------------------------------
# Check if correct options are given
# on the commandline and start configurations
# ---------------------------------------------



if  [ -z "$clientaccprofile" ] ; then
    display_help
    exit 0
fi



#start account configuration
update_client
