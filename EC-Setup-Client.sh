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
#       $ ./EC-Setup-Client.sh Client_ACCOUNT_NAME SecLog_ACCOUNT_NAME
#
#       ex:
#       $ ./EC-Sanitize-Account.sh newAcc1 newSecLog
#
#
#
#   Version History
#
#   v1.0  Alexandre Levret   Initial Version
#
#   --------------------------------------------------------

#       --------------------
#       Parameters
#       --------------------

export ORG_PROFILE=$1
export CLIENT_PROFILE=$2
export SECLOG_PROFILE=$3
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
        printf "\n\n\tIf you are entirely sure that you want to do it, press enter to continue"
        read -p " or CTRL-C to break"
}

#   ---------------------
#   The command line help
#   ---------------------
display_help() {
    echo "Usage: $0 ORG_PROFILE CLIENT_PROFILE SECLOG_PROFILE" >&2
    echo
    echo "   Provide "
    echo "     - the organization profile"
    echo "     - the client account profile"
    echo "     - the SecLog account profile"
    echo
    exit 1
}

#   -----------------------------
#   Configure the Client account
#   -----------------------------

configure_client(){

        #   -----------------------------
        #   Sanitize the Client account
        #   -----------------------------

    AlreadySanitized=`aws --profile $CLIENT_PROFILE ssm get-parameter --name /org/member/SECLZ-Account_sanitized-or-New_account --query "Parameter.Value" --output text`
    if [ -z $AlreadySanitized ] || [ $AlreadySanitized == "1" ]
          then
            echo ""
                echo "   ---------------------------------------------------------"
                echo "   New Account or account already sanitized... skipping step"
                echo "   ---------------------------------------------------------"
                echo ""
          else
            sh ./SH/EC-Sanitize-Client-Account.sh $CLIENT_PROFILE
          fi

        #   -----------------------------
        #   Configure the Client account
        #   -----------------------------

        sh ./SH/EC-Configure-Client-Account.sh $CLIENT_PROFILE $SECLOG_PROFILE

        #   -----------------------------------------------------------------------------
        #   Send invitations (Config, GuardDuty, Security Hub) from the SecLog account
        #   -----------------------------------------------------------------------------

        sh ./SH/EC-Invite-from-SecLog-Account.sh $ORG_PROFILE $CLIENT_PROFILE $SECLOG_PROFILE
        #   -----------------------------------------------------------------------------
        #   Accept invitations (Config, GuardDuty, Security Hub) from the Client account
        #   -----------------------------------------------------------------------------

        sh ./SH/EC-Accept-from-Client-Account.sh $CLIENT_PROFILE $SECLOG_PROFILE

        #   -----------------------------
        #   Validate the Client account
        #   -----------------------------

        sh ./SH/EC-Validate-Client-Account.sh $CLIENT_PROFILE $SECLOG_PROFILE
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

# Short intro on what is going to happen
intro

# Start the Client account configuration
configure_client

