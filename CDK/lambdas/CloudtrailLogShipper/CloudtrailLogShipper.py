import boto3
import gzip
import re
import json
import os
import re
import logging
import time
from random import randint
from io import BytesIO
from json import dumps
from datetime import datetime
from botocore.exceptions import ClientError
import sys

# initialise logger
LOGGER = logging.getLogger()
DYNAMODB_TABLE_NAME = 'SECLZSyncLogs'
SEVEN_DAYS_IN_SECONDS = 604800
MAX_ITEMS_PER_BATCH = 10000
ITEM_BYTES_OVERHEAD = 26
MAX_BATCH_SISE = 1048576
MAX_TRY = 30

def lambda_handler(event, context):
  cloudwatch = boto3.client('logs')
  sts = boto3.client('sts')
  s3 = boto3.client('s3')
  MAX_TRY = get_max_try()
  LOGGER.setLevel(check_log_level())
  LOGGER.debug('Lambda invoked')
  LOGGER.debug('Event: %s', event)
  LOGGER.debug("Log stream name: %s", context.log_stream_name)
  LOGGER.debug("Log group name: %s", context.log_group_name)
  LOGGER.debug("Request ID: %s", context.aws_request_id)
  LOGGER.debug("Mem. limits(MB): %s", context.memory_limit_in_mb)
  LOGGER.debug("Function name: %s", context.function_name)
  LOGGER.debug("Function version: %s", context.function_version)
  region = os.environ['AWS_REGION']
  loggroup = get_cloudtrail_logggroup()
  account = sts.get_caller_identity()
  for record in event['Records']:
    filename = record['s3']['object']['key']
    pattern1 = 'AWSLogs/\d+/CloudTrail/'
    pattern2 = 'AWSLogs/\d+/CloudTrail-Insight/'
    isCloudTrail = re.match(pattern1, filename)
    isCloudTrailInsight = re.match(pattern2, filename)
    if not account['Account'] in filename and (isCloudTrail or isCloudTrailInsight):
        LOGGER.info('S3 object matching regexp detected: ' + filename)
        if isCloudTrailInsight:
            loggroup = get_insight_logggroup()
        bucketname = record['s3']['bucket']['name']
        LOGGER.debug('S3 bucket: ' + bucketname)
        l = re.split(r'/',filename)
        logstreamname = l[1] + '_CloudTrail_' + l[3]
        LOGGER.debug('logstreamname: : ' + logstreamname)
        LOGGER.debug('Linked account: : ' + l[1])

        # Create the logstream if needed
        create_log_stream(loggroup, logstreamname)

        # get the object
        obj = s3.get_object(Bucket=bucketname, Key=filename)
        LOGGER.debug('Retrieve S3 object')
        # get the content as text
        n = obj['Body'].read()
        gzipfile = BytesIO(n)
        gzipfile = gzip.GzipFile(fileobj=gzipfile)
        content = gzipfile.read()
        json_content = json.loads(content.decode('utf-8'))

        # Write a batch of records into cloudwatch log stream:
        # The maximum batch size is 1,048,576 bytes.
        # This size is calculated as the sum of all event messages in UTF-8,
        # plus 26 bytes for each log event.
        # The maximum number of log events in a batch is 10,000.
        # items in the batch must be in a chronological order
        total_counter = 0
        log_events = []
        batch_size_bytes = 0
        batch_item_counter = 0
        batch_counter = 1

        for record in json_content['Records']:
            total_counter += 1
            # get eventTime from record and use it to set the timestamp of the log
            dt_obj = datetime.strptime(record['eventTime'],'%Y-%m-%dT%H:%M:%SZ')
            ts = int(float(dt_obj.timestamp()) * 1000)

            record_size = sys.getsizeof(json.dumps(record)) + ITEM_BYTES_OVERHEAD

            if (batch_item_counter < MAX_ITEMS_PER_BATCH and batch_size_bytes+record_size < MAX_BATCH_SISE ):
                batch_size_bytes += record_size
                batch_item_counter +=1
                log_events.append({'timestamp': ts,'message': json.dumps(record)})
            else:
                log_events.sort(key=lambda x:x['timestamp'])
                sequence_token = get_sequence_token(loggroup, logstreamname)
                put_log_events(logstreamname, loggroup, sequence_token, log_events, 1)
                batch_counter += 1
                batch_size_bytes = record_size
                batch_item_counter = 1
                batch_size = record_size
                log_events = []
                log_events.append({'timestamp': ts,'message': json.dumps(record)})

        # if the batch contains items, write it into cloudwatch log stream
        if ( batch_item_counter > 0 ):
            log_events.sort(key=lambda x:x['timestamp'])
            sequence_token = get_sequence_token(loggroup, logstreamname)
            put_log_events(logstreamname, loggroup, sequence_token, log_events, 1)

        LOGGER.info(str(total_counter) + ' log entries from S3 object created in ' + str(batch_counter) + ' batch')
    else:
        LOGGER.info("S3 object Skipped: "+ account['Account']+" is in "+filename)


def delete_sequence_token(log_group_name, log_stream):
    """
    This function delete the log stream's sequence token if there is one.

        :param log_group_name: The name of the log group with the correct pattern.
        :param log_stream: The name of the log stream.
    """
    client = boto3.client('dynamodb')
    try:
        response = client.delete_item(
            TableName=DYNAMODB_TABLE_NAME,
            Key={
                'LogGroupName': {
                    'S': log_group_name
                },
                'LogStreamName': {
                    'S': log_stream
                }
            }
        )
        LOGGER.debug("PreExisting item deleted in DynamoDB Key: "+log_group_name+" "+log_stream)
    except Exception:
        LOGGER.debug("Item not present in DynamoDB Key: "+log_group_name+" "+log_stream)

def get_sequence_token(log_group_name, log_stream):
    """
    This function gets the log stream's sequence token if there is one.

        :param log_group_name: The name of the log group with the correct pattern.
        :param log_stream: The name of the log stream.
    """
    client = boto3.client('dynamodb')
    response = client.get_item(
        TableName=DYNAMODB_TABLE_NAME,
        Key={
            'LogGroupName': {
                'S': log_group_name
            },
            'LogStreamName': {
                'S': log_stream
            }
        },
        ConsistentRead=True
    )
    nextToken = response.get('Item', {}).get('NextSequenceToken', {}).get('S', None)

    # if token not in DynamoDB, get token from logstream and save it to DynamoDB
    if (nextToken is None):
        LOGGER.debug("Token not found in DynamoDB for loggroup: "+log_group_name+" and stream: "+log_stream)
        cloudwatch = boto3.client('logs')
        response = cloudwatch.describe_log_streams(logGroupName=log_group_name,logStreamNamePrefix=log_stream)
        li = list(filter(lambda ls: ls['logStreamName'] == log_stream, response['logStreams']))
        if 'uploadSequenceToken' in li[0]:
            nextToken = li[0]['uploadSequenceToken']
        if (nextToken is not None):
            save_next_sequence_token(log_group_name, log_stream, nextToken)
        return nextToken
    else:
        return nextToken

def create_log_stream(log_group_name, log_stream):
    """
    This function creates the log stream if it is necessary.

        :param log_group_name: The name of the log group with the correct pattern.
        :param log_stream: The name of the log stream that should be created.
    """
 # Create the logstream if needed
    if ( logstream_exists(log_group_name,log_stream) is False):
        try:
            client = boto3.client('logs')
            client.create_log_stream(logStreamName=log_stream, logGroupName=log_group_name)
            delete_sequence_token(log_stream=log_stream, log_group_name=log_group_name)
            LOGGER.info("Log Stream created")
        except ClientError as client_error:
            if client_error.response['Error']['Code'] == 'ResourceAlreadyExistsException':
                LOGGER.debug("Log Stream already exists")
        except Exception:
            LOGGER.exception("Unexpected error while creating the log stream.")
            raise

def logstream_exists(log_group_name,log_stream):
    """
    This function check if the log stream already exists in the DynamoDB table

        :param log_group_name: The name of the log group with the correct pattern.
        :param log_stream: The name of the log stream.
    """
    client = boto3.client('dynamodb')
    response = client.get_item(
        TableName=DYNAMODB_TABLE_NAME,
        Key={
            'LogGroupName': {
                'S': log_group_name
            },
            'LogStreamName': {
                'S': log_stream
            }
        },
        ConsistentRead=True
    )
    logstream_inDB = response.get('Item', {}).get('LogStreamName', {}).get('S', None)

    # if logstream not in DynamoDB return False otherwise return True
    if (logstream_inDB is None):
        LOGGER.debug("Log Stream not found in DynamoDB for loggroup: "+log_group_name+" and stream: "+log_stream)
        return False
    else:
        return True

def save_next_sequence_token(log_group_name, log_stream, sequence_token):
    """
    This function saves the next sequence token to be used for the specified
    log group and log stream.

        :param log_group_name: The name of the log group with the correct pattern.
        :param log_stream: The name of the log stream.
        :param sequence_token: The next sequence token to save.
    """
    client = boto3.client('dynamodb')
    LOGGER.debug('Saving next sequence token: [%s - %s - %s]',
                log_group_name, log_stream, sequence_token)
    client.put_item(
        TableName=DYNAMODB_TABLE_NAME,
        Item={
            'LogGroupName': {'S': log_group_name},
            'LogStreamName': {'S': log_stream},
            'NextSequenceToken': {'S': sequence_token},
            'TTL': {'N': str(int(time.time()) + SEVEN_DAYS_IN_SECONDS)},
        }
    )

def internal_put_log_events(client, log_stream, log_group_name, sequence_token, log_events):
    """
    This function is responsible to send the log events to CloudWatch at the logging account.

        :param log_stream: The name of the log stream.
        :param log_group_name: The name of the log_group.
        :param sequence_token: The sequence token to use if it is necessary.
        :param log_events: The dict containing all the log events to be added.
        :param client: the AWS logs client
    """
    if (sequence_token == "null" or sequence_token is None):
        response = client.put_log_events(logStreamName=log_stream,
                                         logGroupName=log_group_name,
                                         logEvents=log_events)
    else:
        response = client.put_log_events(logStreamName=log_stream,
                                         logGroupName=log_group_name,
                                         sequenceToken=sequence_token,
                                         logEvents=log_events)

    if ('nextSequenceToken' in response):
        nextSequenceToken = response['nextSequenceToken']
        if (sequence_token != nextSequenceToken):
            LOGGER.debug("nextSequenceToken: "+str(nextSequenceToken))
            save_next_sequence_token(log_group_name, log_stream, nextSequenceToken)
    else:
        LOGGER.debug("nextSequenceToken key not found in put_log_events response: "+str(type(response)))
        for key in response:
            LOGGER.debug('key:'+str(key)+' value:'+str(response[key]))

def put_log_events(log_stream, log_group_name, sequence_token, log_events, loop):
    """
    This function is responsible to send the log events to CloudWatch at the logging account.

        :param log_stream: The name of the log stream.
        :param log_group_name: The name of the log_group.
        :param sequence_token: The sequence token to use if it is necessary.
        :param log_events: The dict containing all the log events to be added.
        :param loop: counter to avoid infinite recursion.
    """
    try:
        try:
            client = boto3.client('logs')
            internal_put_log_events(client, log_stream, log_group_name, sequence_token, log_events)
        except client.exceptions.ResourceNotFoundException as exception:
            LOGGER.info('%s', json.dumps(exception.response))
            if loop > MAX_TRY:
                raise Exception("Too many ResourceNotFoundException to write log")
            else:
                put_log_events(log_stream, log_group_name, sequence_token, log_events, loop+1)
        except (client.exceptions.InvalidSequenceTokenException,client.exceptions.DataAlreadyAcceptedException) as exception:
            LOGGER.info('%s', json.dumps(exception.response))
            seconds = randint(1, 5)
            LOGGER.info('Throttling '+str(seconds)+'s in loop '+str(loop))
            time.sleep(seconds)
            if loop > MAX_TRY:
                raise Exception("Too many InvalidSequenceTokenException or DataAlreadyAcceptedException to write log")
            else:
                # Extract nextToken from DynamoDB
                nextToken = get_sequence_token(log_group_name, log_stream)
                if (nextToken == sequence_token):
                    # Token in DynamoDB is wrong, replace it with token found in exception
                    # Extract nextToken from exception.response.expectedSequenceToken
                    nextToken = exception.response['expectedSequenceToken']
                    LOGGER.info('Retrying with sequence_token found in exception: '+str(nextToken))
                else:
                    LOGGER.info('Retrying with sequence_token from DynamoDB: '+str(nextToken))

                put_log_events(log_stream, log_group_name, nextToken, log_events, loop+1)
    except ClientError:
        LOGGER.exception("Unexpected error while putting events.")
        raise
    finally:
        return loop

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


def get_max_try():
    """
    This function gets the LogLevel from the environment variables table.
    """
    return os.environ.get('MAX_TRY', 30)

def get_cloudtrail_logggroup():
    """
    This function gets the cloudtrail log group from the environment variables table.
    """
    return os.environ.get('CLOUDTRAIL_LOG_GROUP', '/aws/cloudtrail')

def get_insight_logggroup():
    """
    This function gets the cloudtrail insight log group from the environment variables table.
    """
    return os.environ.get('INSIGHT_LOG_GROUP', '/aws/cloudtrail/insight')