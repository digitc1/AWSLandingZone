# Instructions Secure Landing Zone

Detailed instruction on how to setup a Secure Landing Zone solution can be found on following confluence page:
- https://webgate.ec.europa.eu/fpfis/wikis/pages/viewpage.action?spaceKey=CVTF&title=AWS+Secure+Landing+Zone


## Before you begin

- Make sure you have an Administrator Access (including Programmatic Access) to the organizations root account
- Have AWS CLI configured with credentials to the organization in default profile
- The following command should work and provide an overview of accounts:
```
$ aws organizations list-accounts
```
- Execute the script from the folder "AWSLandingZone"
```
$ cd AWSLandingZone
```

### Create the SecLog account (if it doesn't exist)

Follow the instructions given on the following page: https://webgate.ec.europa.eu/fpfis/wikis/display/CVTF/%5BAWS%5D+Account+creation+broker+procedure

### Configure the SecLog account

To configure the SecLog account that you just created, we'll need to run the *EC-Setup-SecLog.sh* script by adding following parameters:

* --organisation           : The orgnisation account as configured in your AWS profile (optional)
* --seclogprofile          : The account profile of the central SecLog account as configured in your AWS profile
* --splunkprofile          : The Splunk account profile as configured in your AWS profile
* --notificationemail      : The notification email to where logs are to be sent
* --logdestination         : The name of the DG of the firehose log destination
* --cloudtrailintegration  : Flag to enable or disable CloudTrail seclog integration. Default: true (optional)
* --guarddutyintegration   : Flag to enable or disable GuardDuty seclog integration. Default: true (optional)
* --securityhubintegration : Flag to enable or disable SecurityHub seclog integration. Default: true (optional)
* --cloudtrailgroupname          : The custom name for CloudTrail Cloudwatch loggroup name (optional)
* --insightgroupname             : The custom name for CloudTrail Insight Cloudwatch loggroup name (optional)
* --guarddutygroupname           : The custom name for GuardDuty Cloudwatch loggroup name (optional)
* --securityhubgroupname         : The custom name for SecurityHub Cloudwatch loggroup name (optional)
* --configgroupname              : The custom name for AWSConfig Cloudwatch loggroup name (optional)
* --alarmsgroupname              : The custom name for Cloudwatch alarms loggroup name (optional)
* --batch                  : Flag to enable or disable batch execution mode. Default: false (optional)

Run the script
```
$ ./EC-Setup-SecLog.sh  --organisation DIGIT_ORG_ACC --seclogprofile D3_seclog --splunkprofile EC_DIGIT_C2-SPLUNK --notificationemail D3-SecNotif@ec.europa.eu --logdestination dgtest 
```
Wait for the execution of the installation script to finish. When done, the user will see a message with the following instructions:
```
---------------------------------------------------------------------------------------------------------
|                                         ATTENTION PLEASE:                                             |
---------------------------------------------------------------------------------------------------------
|                                                                                                       |
|  Please check the installation of the stackset instances from the AWS console for the SECLOG account  |
|  The moment all instances are deployed, please execute the 2nd stage of the LZ installation with the  |
|  following command:                                                                                   |
|                                                                                                       |
|               sh ./SH/EC-Enable-SecurityHub-Controls-All-Regions.sh {seclogprofile}                   |
|                                                                                                       |
---------------------------------------------------------------------------------------------------------
```
Check in the SECLOG account if all stackset instances have been deployed, and when all is done, copy and paste the command as shown to execute it.

#### Disable SOC integration

If you wish to disable any of the default SOC log integrations, use the appropriate flags (can be combined on a single script call)

**Disable CloudTrail integration**
```
$ ./EC-Setup-SecLog.sh  --organisation DIGIT_ORG_ACC --seclogprofile D3_seclog --splunkprofile EC_DIGIT_C2-SPLUNK --notificationemail D3-SecNotif@ec.europa.eu --logdestination dgtest --cloudtrailintegration false
```
**Disable GuardDuty integration**
```
$ ./EC-Setup-SecLog.sh  --organisation DIGIT_ORG_ACC --seclogprofile D3_seclog --splunkprofile EC_DIGIT_C2-SPLUNK --notificationemail D3-SecNotif@ec.europa.eu --logdestination dgtest --guarddutyintegration false
```
**Disable SecurityHub integration**
```
$ ./EC-Setup-SecLog.sh  --organisation DIGIT_ORG_ACC --seclogprofile D3_seclog --splunkprofile EC_DIGIT_C2-SPLUNK --notificationemail D3-SecNotif@ec.europa.eu --logdestination dgtest --securityhubintegration false
```
**Run script in batch mode - no confirmation asked from user**
```
$ ./EC-Setup-SecLog.sh--seclogprofile D3_seclog --splunkprofile EC_DIGIT_C2-SPLUNK --notificationemail D3-SecNotif@ec.europa.eu --logdestination dgtest --batch true
```


### Create a client account (only for new account)

Follow the instructions given on the following page: https://webgate.ec.europa.eu/fpfis/wikis/display/CVTF/%5BAWS%5D+Account+creation+broker+procedure

### Configure the client account (run this script on a new or existing account you whish to add)

This script will add a new (or existing) client account to the secure landing zone environment.

For existing accounts, make sure the SECLZ-CreateCloudBrokerRole exists in the client account, otherwise execute this script in the client account first: "https://webgate.ec.europa.eu/CITnet/stash/projects/CLOUDLZ/repos/aws-secure-landing-zone/raw/EC-landingzone-v2/CFN/EC-lz-CloudBroker-Role.yml?at=refs%2Fheads%2Fmaster"

This script will:
- setup the client account
- invite the account from master and accept the invitations from the client

To configure the Client  account that you just created, we'll need to run the *EC-Setup-Client.sh* script by adding the following parameters:

* --organisation       : The orgnisation account as configured in your AWS profile (optional)
* --ou                 : The parent orgnisational unit (optional)
* --clientaccprofile   : The client account as configured in your AWS profile
* --seclogprofile      : The account profile of the central SecLog account as configured in your AWS profile
* --clientaccountemail : The root email address used to create the client account (optional, only required if organisation is not provided)
* --batch              : Flag to enable or disable batch execution mode. Default: false (optional)

Run the script

```
$ ./EC-Setup-Client.sh --organisation EC_BROKER_ADM --clientaccprofile D3_Acc1 --seclogprofile D3_seclog
```

Or if you're provided with an norganisational unit ID, use the following:

```
$ ./EC-Setup-Client.sh --organisation EC_BROKER_ADM --ou ou-jh16-abcdefgh --clientaccprofile D3_Acc1 --seclogprofile D3_seclog
```

Or, if thte organisation account is not available, use the following:

```
$ ./EC-Setup-Client.sh --clientaccountemail digit-cloud-tech-account-aXXX@ec.europa.eu --clientaccprofile D3_Acc1 --seclogprofile D3_seclog
```


Wait for the execution of the installation script to finish. When done, the user will see a message with the following instructions:
```
---------------------------------------------------------------------------------------------------------
|                                         ATTENTION PLEASE:                                             |
---------------------------------------------------------------------------------------------------------
|                                                                                                       |
|  Please check the installation of the stackset instances from the AWS console for the SECLOG account  |
|  The moment all instances are deployed, please execute the 2nd stage of the LZ installation with the  |
|  following command:                                                                                   |
|                                                                                                       |
|               sh ./SH/EC-Enable-SecurityHub-Controls-All-Regions.sh {clientaccprofile}                |
|                                                                                                       |
---------------------------------------------------------------------------------------------------------
```
Check in the SECLOG account if all stackset instances have been deployed, and when all is done, copy and paste the command as shown to execute it.

**Run script in batch mode - no confirmation asked from user**

This is a 3 stage process. First execute the setup script to deploy the base components of the LZ on the  client account by issuing the following command:

```
$ ./EC-Setup-Client.sh --organisation EC_BROKER_ADM  --clientaccprofile D3_Acc1 --seclogprofile D3_seclog --batch true
```

Or, if thte organisation account is not available, use the following:

```
$ ./EC-Setup-Client.sh --clientaccountemail digit-cloud-tech-account-aXXX@ec.europa.eu --clientaccprofile D3_Acc1 --seclogprofile D3_seclog --batch true
```

Wait for the execution of the installation script to finish. When done, the user will see a message with the following instructions:

```
--------------------------------------------------------------------------------------------------------------------
|                                         ATTENTION PLEASE:                                                        |
--------------------------------------------------------------------------------------------------------------------
|                                                                                                                  |
|                                                                                                                  |
|  Batch mode has been selected. You'll be required to execute an intermediary step to create instances from       |
|  two stacksets provisioned on the seclog account. When the batch installation of the LZ script finishes,         |
|  please execute the following command:                                                                           |
|                                                                                                                  |
|               sh ./SH/EC-Install-Stacksets-from-SecLog-Account.sh 001111111111,002222222222,...  $seclogprofile  |
|                                                                                                                  |
|  where the first parameter (comma separated) are the client account IDs where the LZ has been installed and      |
|  the second parameter is the SECLOG account profile.                                                             |
|                                                                                                                  |
|  Please check the installation of the stackset instances from the AWS console for the SECLOG account. As soon    |
|  all the instances are deployed, please execute the 2nd stage of the LZ installation with the following command  |
|                                                                                                                  |
|               sh ./SH/EC-Enable-SecurityHub-Controls-All-Regions.sh $clientaccprofile                            |
|                                                                                                                  |
--------------------------------------------------------------------------------------------------------------------
```

The second stage is to deploy the stackset instances on all regions for all accounts that were installed as part of the batch execution. The *EC-Install-Stacksets-from-SecLog-Account.sh* will require 2 parameters:

* CLIENT ACCOUNT IDs       : Comma separated list of all accounts where the stackset instances are to be installed
* SECLOG PROFILE          : The SECLOG account from where to pull the stacksets

For the 3rd stage, first check in the SECLOG account if all stackset instances have been deployed. When it's all is done, execute the last command from the message above for "all" client accounts..

### Update Landing Zone  

Updates are now based a new approach that combines all steps in a single stage for the SECLOG account as well all the linked associated accounts. This script can be run as usual on the DEVOPS management account, or if required can also be executed directly on the SECLOG account via AWS CloudShell.

*Note: This options gives the ability to the customer to update the Secure Landing Zone themselves if required.*

This script will:
- Update the SECLOG landing zone including SSM parameters, Stacks, StackSets and CIS controls
- Update linked accounts associated with the SECLOG account including SSM parameters, Stacks and CIS controls

The SLZ is highly configurable and it is based on a manifest file (json format) that is provided as a default template for each release. Users are welcomed to review the manifest and update it as per own needs.

To execute the update script execute the following command (location of the manifest and seclog profile are given as an example; please adapt accordingly):

```
$ sh ./EC-Update-LZ.sh --manifest ./Update/1.5.0/manifest.json  --seclog EC_DIGIT_C1-LZ-SECLOG
```

In the case the script is to be executed on the SECLOG account directly using AWS Cloudshell, run the following command (no --seclog parameter is required):

```
$ sh ./EC-Update-LZ.sh --manifest ./Update/1.5.0/manifest.json 
```

The script runs unattended and does not require intervention by the user (perhaps only exception would be entering the MFA token if required by the profile). 

The shell script will perform a number of actions to prepare the execution environment for the SLZ update script. After that, the update script will perform a number of validations and begin the process of updating the SECLOG account, acording to the pre-defined settings from the manifest file. When done, the script cycles through all the linked accounts associated with the SECLOG and will perform the required updates as mentioned previously.

#### Manifest

The manifest file is bound to each release and defines what actions are to be performed by the SLZ update script. A sample can be seen below:

```
{   "version" : "1.5.0",
    "regions" : ["ap-northeast-1","ap-northeast-2","ap-northeast-3","ap-south-1","ap-southeast-1","ap-southeast-2","ca-central-1","eu-central-1","eu-north-1","eu-west-1", "eu-west-2","eu-west-3","sa-east-1","us-east-1","us-east-2","us-west-1","us-west-2"],
    "ssm" : {
        "seclog-ou" : {
            "value" : "",
            "update" : false
        },
        "notification-mail" : {
            "value" : "",
            "update" : false
        },
        "cloudtrail-groupname" : {
            "value" : "",
            "update" : false
        },
        "insight-groupname" : {
            "value" : "",
            "update" : false
        },
        "guardduty-groupname" : {
            "value" : "",
            "update" : false
        },
        "securityhub-groupname" : {
            "value" : "",
            "update" : false
        },
        "config-groupname" : {
            "value" : "/aws/events/config",
            "update" : false
        },
        "alarms-groupname" : {
            "value" : "/aws/events/cloudwatch-alarms",
            "update" : true
        }
    },
    "stacks" : {
        "SECLZ-Cloudtrail-KMS" : {
            "update" : true
        },
        "SECLZ-LogShipper-Lambdas-Bucket" : {
            "update" : true
        },
        "SECLZ-LogShipper-Lambdas" : {
            "update" : true
        },
        "SECLZ-Central-Buckets" : {
            "update" : true
        },
        "SECLZ-Iam-Password-Policy" : {
            "update" : true
        },
        "SECLZ-config-cloudtrail-SNS" : {
            "update" : true
        },
        "SECLZ-Guardduty-detector" : {
            "update" : true
        },
        "SECLZ-SecurityHub" : {
            "update" : true
         },
        "SECLZ-Notifications-Cloudtrail" : {
            "update" : true,
            "params" : [
                {"ParameterKey": "LogGroupName", "ParameterValue": "/org/member/SecLog_cloudtrail-groupname"}
            ]
        },
        "SECLZ-CloudwatchLogs-SecurityHub" : {
            "update" : true
        } 
    },
    "stacksets" : {
        "SECLZ-Enable-Config-SecurityHub-Globally" : {
            "update" : true
        },
        "SECLZ-Enable-Guardduty-Globally" : {
            "update" : true
        }
    },
    "cis" :  { 
            "cis-aws-foundations-benchmark/v/1.2.0":  {
                "checks" : ["3.1", "3.2", "3.3", "3.4", "3.5", "3.6", "3.7", "3.8", "3.9", "3.10", "3.11", "3.12", "3.13", "3.14"],
                "disabled" : true,
                "disabled-reason" : "Alarm action unmanaged by SNS but cloudwatch event",
                "regions": [],
                "exclusions" : ["ap-northeast-3"]
            },
            "aws-foundational-security-best-practices/v/1.0.0": { 
                "checks" : ["IAM.1", "IAM.2", "IAM.3", "IAM.4", "IAM.6", "IAM.7", "Config.1"],
                "disabled" : true,
                "disabled-reason" : "Disable recording of global resources in all but one Region",
                "regions": [],
                "exclusions" : ["eu-west-1", "ap-northeast-3"]
            },
            "cis-aws-foundations-benchmark/v/1.2.0/1.14":  { 
                "disabled" : true,
                "disabled-reason" : "Managed by Cloud Broker Team",
                "regions": ["eu-west-1"],
                "exclusions" : []
            },
            "aws-foundational-security-best-practices/v/1.0.0/IAM.6":  { 
                "disabled" : true,
                "disabled-reason" : "Managed by Cloud Broker Team",
                "regions": ["eu-west-1"],
                "exclusions" : []
            }
    },
    "tags" : [
        { "Key": "Organization","Value": "EC" },
        { "Key": "Owner","Value": "DIGIT.C.1" },
        { "Key": "Environment","Value": "prod" },
        { "Key": "Criticity","Value": "high" },
        { "Key": "Project","Value": "secLZ" },
        { "Key": "Confidentiality","Value": "confidential" },
        { "Key": "ApplicationRole","Value": "security" }
    ],
    "accounts" : {
        "exclude" : [],
        "include" : []
    }
    
}

```

Attributes are as follows:

* version (mandatory) - it defines the version of the SLZ
* regions (mandatory) - default set of regions where the LZ is installed
* ssm (optional) - list of SSM parameters for update
   * seclog-ou (optional) - sets the seclog-ou
      * value (mandatory) - the value to be stored
      * update (mandatory) - enable or disable the update
   * notification-mail (optional) - sets the seclog-ou
      * value (mandatory) - the value to be stored
      * update (mandatory) - enable or disable the update
   * cloudtrail-groupname (optional) - cloudtrail log group name to be used
      * value (mandatory) - the value to be stored
      * update (mandatory) - enable or disable the update
   * insight-groupname (optional) -  cloudtrail insight log group name to be used
      * value (mandatory) - the value to be stored
      * update (mandatory) - enable or disable the update
   * guardduty-groupname (optional) - guardduty log group name to be used
      * value (mandatory) - the value to be stored
      * update (mandatory) - enable or disable the update
   * securityhub-groupname (optional) - securityhub log group name to be used
      * value (mandatory) - the value to be stored
      * update (mandatory) - enable or disable the update
   * config-groupname (optional) - config log group name to be used
      * value (mandatory) - the value to be stored
      * update (mandatory) - enable or disable the update
   * alatms-groupname (optional) - cloudwatch alarms log group name to be used
      * value (mandatory) - the value to be stored
      * update (mandatory) - enable or disable the update
* stacks (optional) - stacks for update
   * SECLZ-Cloudtrail-KMS (optional) - KMS key stack
      * params (optional) - parameters to be passed to the stack
      * update (mandatory) - enable or disable the update
   * SECLZ-LogShipper-Lambdas-Bucket (optional) - S3 bucket for logshipper lambdas stack
      * params (optional) - parameters to be passed to the stack
      * update (mandatory) - enable or disable the update
   * SECLZ-Central-Buckets (optional) - Central S3 buckets stack
      * params (optional) - parameters to be passed to the stack
      * update (mandatory) - enable or disable the update
   * SECLZ-LogShipper-Lambdas (optional) - Logshipper lambdas stack
      * params (optional) - parameters to be passed to the stack
      * update (mandatory) - enable or disable the update
   * SECLZ-Iam-Password-Policy (optional) - Password policy stack
      * params (optional) - parameters to be passed to the stack
      * update (mandatory) - enable or disable the update
   * SECLZ-config-cloudtrail-SNS (optional) - Config SNS and cloudtrail stack
      * params (optional) - parameters to be passed to the stack
      * update (mandatory) - enable or disable the update
   * SECLZ-Guardduty-detector (optional) - Guardduty detector stack
      * params (optional) - parameters to be passed to the stack
      * update (mandatory) - enable or disable the update
   * SECLZ-SecurityHub (optional) - Securityhub stack
      * params (optional) - parameters to be passed to the stack
      * update (mandatory) - enable or disable the update
   * SECLZ-Notifications-Cloudtrail (optional) - Securityhub cloudtrail notifications stack
      * params (optional) - parameters to be passed to the stack
      * update (mandatory) - enable or disable the update
   * SECLZ-CloudwatchLogs-SecurityHub (optional) - Cloudwatch logs stack
      * params (optional) - parameters to be passed to the stack
      * update (mandatory) - enable or disable the update
* stacks (optional) - stacksets for update
   * SECLZ-Enable-Config-SecurityHub-Globally (optional) - Global securityhub stackset
      * params (optional) - parameters to be passed to the stack
      * update (mandatory) - enable or disable the update
   * SECLZ-Enable-Guardduty-Globally (optional) - Global guardduy stackset
      * params (optional) - parameters to be passed to the stack
      * update (mandatory) - enable or disable the update
* cis (optional) - cis controls to be updated. the configuration object is variable (currently two controls are used *cis-aws-foundations-benchmark/v/1.2.0* and *aws-foundational-security-best-practices/v/1.0.0*) and their configuration can be done in two ways:
   * adding the check on the control (like *cis-aws-foundations-benchmark/v/1.2.0**/1.14***)
      * disabled (mandatory) - true or false depending on the need for disabling or enabling the check
      * disabled-reason (optional) - when set *disabled* attribute to true, to set the reason
      * regions (optional) - region where to apply the check change. If none is included, all regions defined in the regions section will be used
      * exclusions (optional) - region to exclude the check change update.
   * not adding the check on the control (like *cis-aws-foundations-benchmark/v/1.2.0*)
      * checks (mandatory) - an array of checks to be updated on this control
      * disabled (mandatory) - true or false depending on the need for disabling or enabling the check
      * disabled-reason (optional) - when set *disabled* attribute to true, to set the reason
      * regions (optional) - region where to apply the check change. If none is included, all regions defined in the regions section will be used
      * exclusions (optional) - region to exclude the check change update.
* tags (mandatory) - an array of tags to be applied to every resource updated by the script. Each object inside the array must contain:
   * Key (mandatory) - the name of the tag
   * Value (mandatory) - the value for the tag
* accounts (optional) - list of account ids for the script orchestration
   * include (optional) - accounts to be updated (will replace the list of accounts bound to the seclog. Useful to just update a limited set of linked accounts)
   * excloude (optionsl) - accounts to be excluded from the update (can include the seclog account id).


