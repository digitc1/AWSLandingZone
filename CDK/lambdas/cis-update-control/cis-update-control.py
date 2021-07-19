import json
import boto3
from botocore.exceptions import BotoCoreError, ClientError, ProfileNotFound

# Expected Input parameters
#{
#  "accountid": 199983783985,
#  "disabled" : true,
#  "reason": "Disable recording of global resources in all but one Region",
#  "rule": "aws-foundational-security-best-practices/v/1.0.0",
#  "exclusions": [
#    "eu-west-1",
#    "ap-northeast-3"
#  ],
#  "check": "IAM.1",
#  "region": "ap-northeast-1"
#}
    
    
def lambda_handler(event, context):
    accountid = str(event['accountid'])
    disabled = bool(event['disabled'])
    reason = event['reason']
    rule = event['rule']
    exclusions = event['exclusions']
    check = event['check']
    region = event['region']


    if (disabled is True):
        controlStatus="DISABLED"
    else:
        controlStatus="ENABLED"


    
    if (region in exclusions):
        print(region)
        print(exclusions)
        msg = f"{check} check SKIPPED in region {region} account {accountid}"
        return {
                'statusCode': 200,
                "body": msg
            }
    else:
        sts = boto3.client('sts')
        
        try:
            assumedRole = sts.assume_role(
                RoleArn=f"arn:aws:iam::{accountid}:role/SECLZ-SeclogRole",
                RoleSessionName='SECLZ-StepFunctionsSession'
            )
        except ClientError as err:
            return {
                'statusCode': 500,
                "body": err.response['Error']
            }
            
        credentials = assumedRole['Credentials']
        accessKey = credentials['AccessKeyId']
        secretAccessKey = credentials['SecretAccessKey']
        sessionToken = credentials['SessionToken']
          
        try:
            client = boto3.client('securityhub', 
                                region_name=region,  
                                aws_access_key_id=accessKey,
                                aws_secret_access_key=secretAccessKey, 
                                aws_session_token=sessionToken)
        except Exception as err:
            msg = f"Account {accountid} is not subscribed to AWS Security Hub on region {region}"
            return {
                'statusCode': 500,
                "body": msg
            }


            
        try:
            stds = client.get_enabled_standards()
        except Exception as err:
            msg = f"Account {accountid} is not subscribed to AWS Security Hub on region {region}"
            return {
                'statusCode': 500,
                "body": msg
            }
        
        controls = []

        for std in stds['StandardsSubscriptions']:
            available_controls = get_controls(client, region, std['StandardsSubscriptionArn'])
            controls.extend([d for d in available_controls if f"{rule}/{check}" in d['StandardsControlArn'] ])

        for control in controls:
            try:
                if (disabled is True):
                    response=client.update_standards_control(
                            StandardsControlArn=control['StandardsControlArn'],
                            ControlStatus=controlStatus,
                            DisabledReason=reason,
                        )
                else:
                    response=client.update_standards_control(
                            StandardsControlArn=control['StandardsControlArn'],
                            ControlStatus=controlStatus
                        )                        
                    
                msg = f"{check} check {controlStatus} in account {accountid} region {region}"
                # TODO implement
                return {
                    'statusCode': 200,
                    "body": msg
                }
            except ClientError as err:
                return {
                    'statusCode': 500,
                    "body": err.response['Error']
                }

        
def get_controls(client, region, sub_arn, NextToken=None):

    try:
        controls = client.describe_standards_controls(
            NextToken=NextToken,
            StandardsSubscriptionArn=sub_arn) if NextToken else client.describe_standards_controls(
            StandardsSubscriptionArn=sub_arn)
    except ClientError as err:
        return {
            'statusCode': 500,
            "body": err.response['Error']
        }

    if ('NextToken' in controls):
        return controls['Controls'] + get_controls(client, region, sub_arn, NextToken=controls['NextToken'])
    else:
        return controls['Controls']

