#!/bin/bash

#   --------------------------------------------------------
#   Updates/1.3.1/EC-Update-Seclog.sh
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


ALL_REGIONS_EXCEPT_IRELAND='["ap-northeast-1","ap-northeast-2","ap-south-1","ap-southeast-1","ap-southeast-2","ca-central-1","eu-central-1","eu-north-1","eu-west-2","eu-west-3","sa-east-1","us-east-1","us-east-2","us-west-1","us-west-2"]'

# parameters for scripts


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
#   Configure Seclog Account
#   ----------------------------
update_seclog() {

  
    # Getting SecLog Account Id
    SECLOG_ACCOUNT_ID=`aws --profile $seclogprofile sts get-caller-identity --query 'Account' --output text`


    echo ""
    echo "- Update seclog account event bus permissions ... "
    echo "-----------------------------------------------------------"
    echo ""

    echo "Remove personalised event bus permission policy for Ireland... " 

    DESCRIBE_EVENTBUS=`aws --profile $seclogprofile events describe-event-bus`
    POLICY=`echo $DESCRIBE_EVENTBUS | jq -r '.Policy'`
    SID=`echo $POLICY | jq  -r '.Statement[] | select (.Principal | select (.AWS? | contains("root"))).Sid'`
    CLIENTARN=`echo $POLICY | jq -r '.Statement[] | select (.Principal | select (.AWS? | contains("root")))'.Principal.AWS`

    for i in ${SID}; 
    do
      aws --profile $seclogprofile events remove-permission --statement-id $i
    done

    NEWCLIENTARN=`echo $CLIENTARN | sed 's/^\|$/\"/g'|paste -sd, - | sed 's/ /\",\"/g'`
    STATEMENT='{"Sid": "SECLOG", "Effect": "Allow", "Action": ["events:PutEvents"], "Resource": "arn:aws:events:eu-west-1:$SECLOG_ACCOUNT_ID:event-bus/default", "Principal": {"AWS" : []}}'
    STATEMENT=`echo $STATEMENT | jq -c '.Principal.AWS = ['$NEWCLIENTARN']'`

    DESCRIBE_EVENTBUS=`aws --profile $seclogprofile  events describe-event-bus`
    CLEAREDPOLICY=`echo $DESCRIBE_EVENTBUS | jq -r '.Policy'`

    NEWPOLICY=`echo $CLEAREDPOLICY | jq '.Statement[.Statement| length] |= . + '$STATEMENT`
    aws --profile $seclogprofile events put-permission --policy "$NEWPOLICY"

    echo "\bDone." 
    sleep 1
    echo ""
    echo "Remove event bus permission policies for all other regions... " 
    echo ""
    ALL_REGIONS_EXCEPT_IRELAND_ARRAY=`echo $ALL_REGIONS_EXCEPT_IRELAND | sed -e 's/\[//g;s/\]//g;s/,/ /g;s/\"//g'`
	  for r in ${ALL_REGIONS_EXCEPT_IRELAND_ARRAY[@]}; 
      do
        echo "Remove personalised event bus permission policy for $r... " 

        DESCRIBE_EVENTBUS=`aws --profile $seclogprofile --region $r events describe-event-bus`
        POLICY=`echo $DESCRIBE_EVENTBUS | jq -r '.Policy'`
        SID=`echo $POLICY | jq  -r '.Statement[] | select (.Principal | select (.AWS? | contains("root"))).Sid'`
        CLIENTARN=`echo $POLICY | jq -r '.Statement[] | select (.Principal | select (.AWS? | contains("root")))'.Principal.AWS`

        for i in ${SID}; 
        do
          aws --profile $seclogprofile events remove-permission --statement-id $i
        done

        NEWCLIENTARN=`echo $CLIENTARN | sed 's/^\|$/\"/g'|paste -sd, - | sed 's/ /\",\"/g'`
        STATEMENT='{"Sid": "SECLOG", "Effect": "Allow", "Action": ["events:PutEvents"], "Resource": "arn:aws:events:$r:$SECLOG_ACCOUNT_ID:event-bus/default", "Principal": {"AWS" : []}}'
        STATEMENT=`echo $STATEMENT | jq -c '.Principal.AWS = ['$NEWCLIENTARN']'`

        DESCRIBE_EVENTBUS=`aws --profile $seclogprofile --region $r events describe-event-bus`
        CLEAREDPOLICY=`echo $DESCRIBE_EVENTBUS | jq -r '.Policy'`

        NEWPOLICY=`echo $CLEAREDPOLICY | jq '.Statement[.Statement| length] |= . + '$STATEMENT`
        aws --profile $seclogprofile --region $r events put-permission --policy "$NEWPOLICY"
        echo "\bDone." 

      done
    echo "" 
    echo "Finished." 
    sleep 5


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
