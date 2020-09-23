#!/bin/bash

#   --------------------------------------------------------
#
#       Automates the following:
#       - Sanitize an AWS account (Config, GuardDuty, Security Hub)
#       - Configure an AWS account
#       - Validate (? - not yet - empty function)
#       - Invite from the SecLog account
#       - Accept from the Client account
#
#       Prerequesites:
#       - We are assuming that the account is part of the AWS Organizations
#       - We are assuming that the account has already a CloudBrokerAccountAccess role created
#
#       Usage:
#       $ ./EC-Setup-Client.sh  --organisation [Org. Acc. Profile] --clientaccprofile [Client Acc. Profile] --seclogprofile [Seclog. Acc. Profile] --batch [true|false]
#
#
#   Version History
#
#   v1.0.0  Alexandre Levret   Initial Version
#   v1.1.0  J. Silva           Updated parameter handling
#
#   --------------------------------------------------------

#       --------------------
#       Parameters
#       --------------------

# export organisation=$1
# export clientaccprofile=$2
# export seclogprofile=$3

organisation=${organisation:-}
seclogprofile=${seclogprofile:-}
clientaccprofile=${clientaccprofile:-}
batch=${batch:-false}


while [ $# -gt 0 ]; do

   if [[ $1 == *"--"* ]]; then
        param="${1/--/}"
        declare $param="$2"
        # echo $1 $2 // Optional to see the parameter:value result
   fi

  shift
done


AWS_REGION='eu-west-1'

#       --------------------
#   Functions
#
#   1. intro()    -> Short brief on what's going to happen by running this script
#
#   Scripts
#
#       1. SH/EC-Sanitize-Client-Account.sh             -> Sanitize the Client account by desabling / resetting multiple AWS services (Config, GuardDuty, Security Hub)
#       2. SH/EC-Configure-Client-Account.sh            -> Configure the Client account
#       3. SH/EC-Validate-Client-Account.sh             -> Validate the Client account by desabling / resetting multiple AWS services (Config, GuardDuty, Security Hub)
#       4. SH/EC-Invite-from-SecLog-Account.sh  -> Send invitations from the SecLog account on Config aggregator, GuardDuty, and Security Hub
#       5. SH/EC-Accept-from-Client-Account.sh  -> Accept invitations from the Client account on Config aggregator, GuardDuty, and Security Hub
#       --------------------

intro() {
        printf "\n- Before running this script, be aware of the following: \n"
        echo "   ----------------------------------------------------"
        echo "     1. This first script is part of an AWS Secure Landing Zone Solution process"
        echo "     2. You need to know that this end-to-end process will start by disabling multiple AWS services (Config, GuardDuty, Security Hub)"
        echo "   ----------------------------------------------------"
        if ["$batch" == "true"]
          printf "\n\n\tIf you are entirely sure that you want to do it, press enter to continue"
          read -p "  or CTRL-C to break"
        fi
}

#   ---------------------
#   The command line help
#   ---------------------
display_help() {
    echo "Usage: $0 --organisation [Org. Acc. Profile] --clientaccprofile [Client Acc. Profile] --seclogprofile [Seclog. Acc. Profile]  --batch [true|false]" >&2
    echo ""
    echo "   Provide "
    echo "   --organisation      : The orgnisation account as configured in your AWS profile "
    echo "   --clientaccprofile  : The client account as configured in your AWS profile"
    echo "   --seclogprofile     : The account profile of the central SecLog account as configured in your AWS profile"
    echo "   --batch             : Flag to enable or disable batch execution mode. Default: false"
    echo ""
    exit 1
}

#   -----------------------------
#   Configure the Client account
#   -----------------------------

configure_client(){

        #   -----------------------------
        #   Sanitize the Client account
        #   -----------------------------

    AlreadySanitized=`aws --profile $clientaccprofile ssm get-parameter --name /org/member/SECLZ-Account_sanitized-or-New_account --query "Parameter.Value" --output text`
    if [ -z $AlreadySanitized ] || [ $AlreadySanitized == "1" ]
          then
            echo ""
                echo "   ---------------------------------------------------------"
                echo "   New Account or account already sanitized... skipping step"
                echo "   ---------------------------------------------------------"
                echo ""
          else
            sh ./SH/EC-Sanitize-Client-Account.sh $clientaccprofile
          fi

        #   -----------------------------
        #   Configure the Client account
        #   -----------------------------

        sh ./SH/EC-Configure-Client-Account.sh $clientaccprofile $seclogprofile

        #   -----------------------------------------------------------------------------
        #   Send invitations (Config, GuardDuty, Security Hub) from the SecLog account
        #   -----------------------------------------------------------------------------

        sh ./SH/EC-Invite-from-SecLog-Account.sh $organisation $clientaccprofile $seclogprofile
        #   -----------------------------------------------------------------------------
        #   Accept invitations (Config, GuardDuty, Security Hub) from the Client account
        #   -----------------------------------------------------------------------------

        sh ./SH/EC-Accept-from-Client-Account.sh $clientaccprofile $seclogprofile

        #   -----------------------------
        #   Validate the Client account
        #   -----------------------------

        sh ./SH/EC-Validate-Client-Account.sh $clientaccprofile $seclogprofile
}

# ---------------------------------------------
# Check if correct options are given
# on the commandline and send invitation
# ---------------------------------------------

# Simple check if 3 arguments are provided
if [ -z "$clientaccprofile" ] || [ -z "$seclogprofile" ] || [ -z "$organisation" ] ; then
    display_help
    exit 0
fi

# Short intro on what is going to happen
intro

# Start the Client account configuration
configure_client

