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
- Execute the script from the folder "EC-landingzone-v2"
```
$ cd EC-landingzone-v2
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

To configure the SecLog account that you just created, we'll need to run the "EC-Configure-SecLog-Account.sh" script by adding two parameters:
- The name of the **SecLog account** as used in the profile in ".aws/config" (for example 'D3_seclog')
- The name of the **organisation account** as used in the profile in ".aws/config" (for example 'D3_Acc1')
- The name of the **C2 Splunk account** as used in the profile in ".aws/config" (for example 'EC_DIGIT_C2-SPLUNK')
- The **email address** used for security notifications (for example 'D3-SecNotif@ec.europa.eu')
- **Log destination name** It should be the name of the DG of the firehose log destination (i.e. 'dgtest'). Note that this value requires resource provisioning for Splunk so please take into account that C2 may need to be contacted to check if the log destination needs to be created.

Run the script
```
$ ./EC-Setup-SecLog.sh D3_Acc1 D3_seclog EC_DIGIT_C2-SPLUNK D3-SecNotif@ec.europa.eu dgtest
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

Run the script
```
$ ./EC-Setup-Client.sh D3_Acc1 D3_seclog
```
