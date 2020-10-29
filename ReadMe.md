# Instructions Secure Landing Zone

Detailed instruction on how to setup a Secure Landing Zone solution can be found on following confluence page:
- https://webgate.ec.europa.eu/CITnet/confluence/display/CLOUDLZ/AWS


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

To create the SecLog, we'll need to run the "EC-Create-Account.sh" script by adding two parameters:
- The name of the SecLog account you wish (for example 'D3_seclog')
- The email address of the SecLog account you wish (for example 'D3_seclog@ec.europa.eu')

Run the script
```
$ ./EC-Create-Account.sh D3_seclog D3_seclog@ec.europa.eu
```


### Configure the SecLog account

To configure the SecLog account that you just created, we'll need to run the "EC-Setup-SecLog.sh" script by adding following parameters:

* --organisation           : The orgnisation account as configured in your AWS profile (optional)
* --seclogprofile          : The account profile of the central SecLog account as configured in your AWS profile
* --splunkprofile          : The Splunk account profile as configured in your AWS profile
* --notificationemail      : The notification email to where logs are to be sent
* --logdestination         : The name of the DG of the firehose log destination
* --cloudtrailintegration  : Flag to enable or disable CloudTrail seclog integration. Default: true (optional)
* --guarddutyintegration   : Flag to enable or disable GuardDuty seclog integration. Default: true (optional)
* --securityhubintegration : Flag to enable or disable SecurityHub seclog integration. Default: true (optional)
* --batch                  : Flag to enable or disable batch execution mode. Default: false (optional)

Run the script
```
$ ./EC-Setup-SecLog.sh  --organisation DIGIT_ORG_ACC --seclogprofile D3_seclog --splunkprofile EC_DIGIT_C2-SPLUNK --notificationemail D3-SecNotif@ec.europa.eu --logdestination dgtest 
```
Wait for the execution of the installation script to finish. When done, the user will see a message with the following instructions:

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

Check in the SECLOG account if all stackset instances have been deployed, and when all is done, execute the command as shown.


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

### Update SECLOG account 

This script will update the existing stacks (where applicable) of the secure landing zone in the seclog account to the latest version. 

Run the script
```
$ ./EC-Update-SecLog.sh --organisation DIGIT_ORG_ACC --seclogprofile D3_seclog --splunkprofile EC_DIGIT_C2  --notificationemail D3-SecNotif@ec.europa.eu --logdestination dgtest
```

Depending on the version being updated, the user may be required to execute a 2nd stage of the LZ update script. Check if there is a folder under ./Updates that corresponds to the current version of the LZ being deployed. If so, execute the corresponding EC-Update-Client.sh script from that folder. The script of each update version may have specific script parameters, please check first before executing.

Example: Upgrading the LZ on the seclog account to version 1.2.6:
```
$ sh ./Updates/1.2.6/EC-Update-SecLog.sh --seclogprofile D3_seclog --guarddutyintegration true
```

**Run script in batch mode - no confirmation asked from user**
```
$ ./EC-Update-SecLog.sh --seclogprofile D3_seclog --splunkprofile EC_DIGIT_C2  --notificationemail D3-SecNotif@ec.europa.eu --logdestination dgtest --batch true
```

### Create a client account (only for new account)

To create a new project account, we'll need to run the "EC-Create-Account.sh" script by adding two parameters:
- The name of the project account you wish (for example 'D3_Acc1' --> this will be stored in your profile and in AWS organizations)
- The email address of this account you wish (for example 'D3_Acc1@ec.europa.eu')

Run the script
```
$ ./EC-Create-Account.sh D3_Acc1 D3_Acc1@ec.europa.eu
```

Run this script for every new project accounts you wish to create.

### Configure the client account (run this script on a new or existing account you whish to add)

This script will add a new (or existing) client account to the secure landing zone environment.
For existing accounts, make sure the SECLZ-CreateCloudBrokerRole exists in the client account, otherwise execute this script in the client account first: "https://webgate.ec.europa.eu/CITnet/stash/projects/CLOUDLZ/repos/aws-secure-landing-zone/raw/EC-landingzone-v2/CFN/EC-lz-CloudBroker-Role.yml?at=refs%2Fheads%2Fmaster"

This script will:
- setup the client account
- invite the account from master and accept the invitations from the client

To configure the Client  account that you just created, we'll need to run the "EC-Setup-Client.sh" script by adding the following parameters:

* --organisation       : The orgnisation account as configured in your AWS profile (optional)
* --clientaccprofile   : The client account as configured in your AWS profile
* --seclogprofile      : The account profile of the central SecLog account as configured in your AWS profile
* --clientaccountemail : The root email address used to create the client account (optional, only required if organisation is not provided)
* --batch              : Flag to enable or disable batch execution mode. Default: false (optional)

Run the script
```
$ ./EC-Setup-Client.sh  --oganisation DIGIT_ORG_ACC --clientaccprofile D3_Acc1 --seclogprofile D3_seclog
```

Wait for the execution of the installation script to finish. When done, the user will see a message with the following instructions:

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

Check in the SECLOG account if all stackset instances have been deployed, and when all is done, execute the command as shown.


**Run script in batch mode - no confirmation asked from user**
```
$ ./EC-Setup-Client.sh  --clientaccprofile D3_Acc1 --seclogprofile D3_seclog --batch true
```

### Update  client account  

This script will update the existing stacks (where applicable) of secure landing zone on the client account to the latest version. 

Run the script
```
$ ./EC-Update-Client.sh  --oganisation DIGIT_ORG_ACC --clientaccprofile D3_Acc1 
```

Depending on the version being updated, the user may be required to execute a 2nd stage of the LZ update script. Check if there is a folder under ./Updates that corresponds to the current version of the LZ being deployed. If so, execute the corresponding EC-Update-Client.sh script from that folder. The script of each update version may have specific script parameters, please check first before executing.

Example: Upgrading the LZ on the client account to version 1.2.6:
```
$ sh ./Updates/1.2.6/EC-Update-Client.sh --clientaccprofile D3_Acc1 --seclogprofile D3_seclog --guarddutyintegration true
```

**Run script in batch mode - no confirmation asked from user**
```
$ ./EC-Update-Client.sh  --clientaccprofile D3_Acc1  --batch true
```

### Downgrade Secure Landing zone - disable SECLOG to SOC integration

This script will disable the existing SOC integration on an upgraded secure landing zone environment. 
Only run this script if the current SECLOG account has been installed/upgraded with the LZ 1.1.x

This script will:
- Update log groups to push to remove link to a log destination for Cloudtrail, cloudwatch and config logs

Run the script
```
$ ./EC-Disable-SecLog-Splunk.sh --seclogprofile D3_seclog --notificationemail D3-SecNotif@ec.europa.eu
```
