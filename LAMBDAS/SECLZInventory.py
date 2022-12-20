import json
import boto3
import botocore
import logging
import time
import sys
import os 
 
from datetime import datetime, timedelta
from botocore.exceptions import ClientError 

regions = ["ap-northeast-1","ap-northeast-2","ap-south-1","ap-southeast-1","ap-southeast-2","ca-central-1","eu-central-1","eu-north-1","eu-west-1","eu-west-2","eu-west-3","sa-east-1","us-east-1","us-east-2","us-west-1","us-west-2"]
 
LOGGER = logging.getLogger()

def lambda_handler(event, context):
    
    LOGGER.setLevel(check_log_level())
    LOGGER.debug('Lambda invoked')
    LOGGER.debug('Event: %s', event)
    
    aws_account_id = context.invoked_function_arn.split(":")[4]
     
    output = {
        'type' : 'AWS',
        'id'   : aws_account_id,
        'aws'  : { 
            'contacts' : [],
            'iam' : {},
            'lz' : {
                'guardduty' : {},
                'securityhub' : {},
                'config' : {},
                'cloudtrail' : {},
                's3' : {},
                'cloudformation' : {}
            }
        }
    }
   
    output['aws']['contacts'] = get_contact_info()
    output['aws']['iam'] = get_iam_summary()
    output['aws']['lz'] = get_lz_summary(aws_account_id)
    output['aws']['lz']['guardduty'] = get_lz_guardduty_status(output['aws']['lz']['IsSeclog'])
    output['aws']['lz']['securityhub']  = get_lz_securityhub_status(aws_account_id, output['aws']['lz']['IsSeclog'])
    output['aws']['lz']['config']  = get_lz_config_status(output['aws']['lz']['IsSeclog'])
    output['aws']['lz']['cloudtrail']  = get_lz_cloudtrail_summary()
    output['aws']['lz']['s3']  = get_lz_s3_summary()
    output['aws']['lz']['cloudformation']  = get_lz_cloudformation_status(output['aws']['lz']['IsSeclog'])
    
    return {
        'statusCode': 200,
        'body': json.dumps(output)
    }
   
def check_log_level():
    """
    This function tests the log level which has been set.
    """
    log_level = get_log_level()
    if log_level not in ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]:
        log_level = "INFO"
    return log_level

def get_log_level():
    """
    This function gets the LogLevel from the environment variables table.
    """
    return os.environ.get('LOG_LEVEL', 'INFO')

def get_iam_summary():
    """
    This function gets the iam summary.
    """
    client = boto3.client('iam')
    response = client.get_account_summary()
    data = {
        'Users' : response['SummaryMap']['Users'],
        'Groups' : response['SummaryMap']['Groups'],
        'Roles' : response['SummaryMap']['Roles'],
        'Policies' : response['SummaryMap']['Policies'],
        'PoliciesInUse' : response['SummaryMap']['PolicyVersionsInUse'],
        'MFADevices': response['SummaryMap']['MFADevices'],
        'MFADevicesInUse': response['SummaryMap']['MFADevicesInUse']
    }
    return data
    
def get_contact_info():
    """
    This function gets contact information.
    """
    client = boto3.client('account')
    data = []
   
    response = client.get_alternate_contact(
        AlternateContactType='OPERATIONS'
    )
    data.append(response['AlternateContact'])
    response = client.get_alternate_contact(
        AlternateContactType='SECURITY'
    )
    data.append(response['AlternateContact'])

    return data
	
def get_lz_summary(aws_account_id):
    """
    This function gets LZ summary.
    """
    client = boto3.client('ssm')
    data = {}
    
    response = client.get_parameter(Name='/org/member/SLZVersion')
    data['version'] = response['Parameter']['Value']
    response = client.get_parameter(Name='/org/member/SecLogMasterAccountId')
    is_seclog = response['Parameter']['Value'] == aws_account_id
    data['IsSeclog'] = is_seclog
    if not is_seclog:
        data['seclog'] = response['Parameter']['Value']
    return data
    
def get_lz_guardduty_status(is_seclog):
    """
    This function gets LZ guarduty status.
    """
    global regions 
    
    data = { 'detectors' : [] }
    
    for region in regions:
        reg_data = {}
        client = boto3.client('guardduty', region_name = region)
        response = client.list_detectors()
        if len( response['DetectorIds'] ):
            response = client.get_detector(DetectorId=response['DetectorIds'][0])
            reg_data['Region'] = region
            reg_data['Status'] = response['Status']
            reg_data['DataSources'] = response['DataSources']
        else:
            reg_data['Region'] = region
            reg_data['Status'] = 'NOTFOUND'
        data['detectors'].append(reg_data)
        
    if is_seclog:
        data['aggregator'] = { 
            'Region': 'eu-west-1',
            'Members' : [] 
        }
        client = boto3.client('guardduty')
        response = client.list_detectors()
        if len( response['DetectorIds'] ):
            response = client.list_members(DetectorId=response['DetectorIds'][0])
            for member in response['Members']:
                agg_data = {}
                agg_data['AccountId'] = member['AccountId']
                agg_data['Email'] = member['Email']
                agg_data['RelationshipStatus'] = member['RelationshipStatus']
                data['aggregator']['Members'].append(agg_data)
            
                
    return data
    
def get_lz_securityhub_status(account_id, is_seclog):
    """
    This function gets LZ security status.
    """ 
    global regions 
    client = boto3.client('securityhub')
    data = { 'instances' : [] }
    for region in regions:
        reg_data = {}
        client = boto3.client('securityhub', region_name = region)
        response = client.describe_hub()
        
        reg_data['Region'] = region
        reg_data['Scores'] = generateScore(get_standards_status(client, account_id))
        reg_data['AutoEnableControls'] = response['AutoEnableControls']
        data['instances'].append(reg_data)
    
    if is_seclog:
        data['aggregator'] = { 'Members' : [] }
        client = boto3.client('securityhub')
        response = client.list_members()
        if len( response['Members'] ):
            for member in response['Members']:
                agg_data = {}
                agg_data['AccountId'] = member['AccountId']
                agg_data['Email'] = member['Email']
                agg_data['MemberStatus'] = member['MemberStatus']
                data['aggregator']['Members'].append(agg_data)
    return data
    
def get_standards_status(clientSh, accountId):
    filters = {'AwsAccountId': [{'Value': accountId, 'Comparison': 'EQUALS'}],
               'ProductName': [{'Value': 'Security Hub', 'Comparison': 'EQUALS'}],
               'RecordState': [{'Value': 'ACTIVE', 'Comparison': 'EQUALS'}]}

    pages = clientSh.get_paginator('get_findings').paginate(Filters=filters, MaxResults=100)
    standardsDict = {}

    for page in pages:
        for finding in page['Findings']:
            standardsDict = build_standards_dict(finding, standardsDict)
    return standardsDict

def build_standards_dict(finding, standardsDict):
    if any(x in json.dumps(finding) for x in ['Compliance', 'ProductFields']):
        if 'Compliance' in finding:
            status = finding['Compliance']['Status']
            prodField = finding['ProductFields']
            if (finding['RecordState'] == 'ACTIVE' and finding['Workflow']['Status'] != 'SUPPRESSED'):  # ignore disabled controls and suppressed findings
                control = None
                # get values, json differnt for controls...
                if 'StandardsArn' in prodField:  # for aws fun
                    control = prodField['StandardsArn']
                    rule = prodField['ControlId']
                elif 'StandardsGuideArn' in prodField:  # for cis fun
                    control = prodField['StandardsGuideArn']
                    rule = prodField['RuleId']
                #ignore custom findings
                if control is not None:
                    controlName = control.split('/')[1]  # get readable name from arn
                    if controlName not in standardsDict:
                        standardsDict[controlName] = {rule: status} # add new in
                    elif not (rule in standardsDict[controlName] and (status == 'PASSED')):  # no need to update if passed
                        standardsDict[controlName][rule] = status
    return standardsDict

def generateScore(standardsDict):
    resultDict = {}
    for control in standardsDict:
        passCheck = 0
        totalControls = len(standardsDict[control])
        passCheck = len({test for test in standardsDict[control] if standardsDict[control][test] == 'PASSED'})

        # generate score
        score = round(passCheck/totalControls * 100)  # generate score
        resultDict[control] = {"Score": score} #build dictionary
    return resultDict
    
def get_lz_config_status(is_seclog):
    """
    This function gets LZ security status.
    """ 
    global regions 
    
    data = { 'recorders' : [] }
    for region in regions:
        reg_data = {}
        client = boto3.client('config', region_name = region)
        response = client.describe_configuration_recorders()
       
        reg_data['Region'] = region
        reg_data['Configuration'] = []
        for recorder in response['ConfigurationRecorders']:
            agg_data = {}
            agg_data['name'] = recorder['name']
            agg_data['recordingGroup'] = recorder['recordingGroup']
            reg_data['Configuration'].append(agg_data)
            _delivery = client.describe_delivery_channels()
            reg_data['DeliveryChannels'] = _delivery['DeliveryChannels']
        data['recorders'].append(reg_data)
    
    return data
    
def get_lz_cloudtrail_summary():
    data = { 'Trails': [] }
    client = boto3.client('cloudtrail')
    response = client.describe_trails()
    for trail in response['trailList']:
        agg_data = {}
        agg_data['Name'] = trail['Name']
        if 'S3BucketName' in trail:
            agg_data['S3BucketName'] = trail['S3BucketName']
        if 'SnsTopicName' in trail:
            agg_data['SnsTopicName'] = trail['SnsTopicName']
        agg_data['IsMultiRegionTrail'] = trail['IsMultiRegionTrail']
        agg_data['HasInsightSelectors'] = trail['HasInsightSelectors']
        data['Trails'].append(agg_data)
            
    return data
    
def get_lz_s3_summary():
    data = { 'Buckets': [] } 
    client = boto3.client('s3')
    cw = boto3.client('cloudwatch')
    
    response = client.list_buckets()
    for bucket in response['Buckets']:
        try:
            _tags = client.get_bucket_tagging(Bucket=bucket['Name'])
            if 'TagSet' in _tags:
                list_of_all_values = [value for elem in _tags['TagSet'] for value in elem.values()]
                if 'secLZ' in list_of_all_values:
                    agg_data = {}
                    agg_data['Name'] = bucket['Name']
                    _encryption = client.get_bucket_encryption(Bucket=agg_data['Name'])
                    if 'Rules' in _encryption['ServerSideEncryptionConfiguration'] and len(_encryption['ServerSideEncryptionConfiguration']['Rules']) > 0 :
                        agg_data['Encryption'] = _encryption['ServerSideEncryptionConfiguration']['Rules'][0]['ApplyServerSideEncryptionByDefault']['SSEAlgorithm']
                    
                    _size = cw.get_metric_statistics(Namespace='AWS/S3',
                                        MetricName='BucketSizeBytes',
                                        Dimensions=[
                                            {'Name': 'BucketName', 'Value': bucket['Name']},
                                            {'Name': 'StorageType', 'Value': 'StandardStorage'}
                                        ],
                                        Statistics=['Average'],
                                        Period=86400,
                                        StartTime=datetime.utcnow() - timedelta(days=2) ,
                                        EndTime=datetime.utcnow()
                                        )
                                        
                    _count = cw.get_metric_statistics(Namespace='AWS/S3',
                                        MetricName='NumberOfObjects',
                                        Dimensions=[
                                            {'Name': 'BucketName', 'Value': bucket['Name']},
                                            {'Name': 'StorageType', 'Value': 'AllStorageTypes'}
                                        ],
                                        Statistics=['Average'],
                                        Period=3600,
                                        StartTime=datetime.utcnow() - timedelta(days=5) ,
                                        EndTime=datetime.utcnow()
                                        )
                                     
                    LOGGER.debug(_size)
                    LOGGER.debug(_count)
                    
                    for item in _size['Datapoints']:
                        agg_data['Size'] = format_size(item['Average'])
                        break
                    
                    for item in _count['Datapoints']:
                        agg_data['Objects'] = '{:.0f}'.format(item['Average'])
                        break
                        
                    data['Buckets'].append(agg_data)
        except botocore.exceptions.ClientError as error:
            LOGGER.debug(error)
     
    return data
    
def format_size(size):

    total = size + 0
    if total < 1024:
        return '{:.0f} B'.format(total)
    if total < pow(2, 20):
        return '{:.2f} KB'.format(total / pow(2,10))
    if total < pow(2, 30):
        return '{:.2f} MB'.format(total / pow(2,20))
    if total < pow(2,40):
        return '{:.2f} GB'.format(total / pow(2,30))
    return '{:.2f} TB'.format(total / pow(2,40))
    

def get_lz_cloudformation_status(is_seclog):
    data = { 'Stacks': [] }
    global regions 
    
    for region in regions:
        reg_data = {}
        reg_data['Region'] = region
        reg_data['Configuration'] = []
        client = boto3.client('cloudformation', region_name = region)
        response = client.list_stacks()
        for stack in response['StackSummaries']:
            if 'SECLZ' in stack['StackName']:
                agg_data = {}
                agg_data['Name'] = stack['StackName']
                agg_data['CreationTime'] = str(stack['CreationTime'])
                if 'LastUpdatedTime' in stack:
                    agg_data['LastUpdatedTime'] = str(stack['LastUpdatedTime'])
                agg_data['StackStatus'] = stack['StackStatus']
                if 'ParentId' in stack:
                    agg_data['ParentId'] = stack['ParentId']
                reg_data['Configuration'].append(agg_data)
        data['Stacks'].append(reg_data)   
    
    if is_seclog:
        data['stacksets'] = []
        client = boto3.client('cloudformation')
        response = client.list_stack_sets()
        for summary in response['Summaries']:
            reg_data = {}
            reg_data['Name'] = summary['StackSetName']
            reg_data['Status'] = summary['Status']
            reg_data['Instances'] = []
            response = client.list_stack_instances(StackSetName=summary['StackSetName'])
            for instance in response['Summaries']:
                agg_data = {}
                agg_data['Region'] = instance['Region']
                agg_data['Account'] = instance['Account']
                agg_data['Status'] = instance['Status']
                if 'StatusReason' in instance:
                    agg_data['StatusReason'] = instance['StatusReason']
                if 'StackInstanceStatus' in instance:
                    agg_data['StackInstanceStatus'] = instance['StackInstanceStatus']['DetailedStatus']
                reg_data['Instances'].append(agg_data)
            data['stacksets'].append(reg_data)
            
    return data 