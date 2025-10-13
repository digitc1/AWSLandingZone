if [ $# -lt 2 ]; then
  echo "Usage: $0 AccountId FirehoseDestinationSuffix"
  exit 1
fi

AccountId="$1"
FirehoseDestinationSuffix="$2"

REGIONS=("us-east-1" "us-east-2" "us-west-1" "us-west-2" "ap-south-1" "ap-northeast-1" "ap-northeast-2" "ap-northeast-3" "ap-southeast-1" "ap-southeast-2" "ca-central-1" "eu-west-2" "eu-west-3" "eu-central-1" "eu-north-1" "sa-east-1")

export AWS_ACCESS_KEY_ID_DEVOPS=$AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY_DEVOPS=$AWS_SECRET_ACCESS_KEY
export AWS_SESSION_TOKEN_DEVOPS=$AWS_SESSION_TOKEN

export $(printf "AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s" \
  $(aws sts assume-role \
  --role-arn arn:aws:iam::189111522208:role/BrokerAccessAdminRole \
  --role-session-name BrokerAccessAdminRole_Splunk_session \
  --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" \
  --output text))

logdestination=$FirehoseDestinationSuffix
SECLOG_ACCOUNT_ID=$AccountId
ORG_ACCOUNT_ID=246933597933
DESCRIBE_DESTINATIONS=`aws logs describe-destinations`
FIREHOSE_ARN=`echo $DESCRIBE_DESTINATIONS | jq -r '.destinations[]| select (.destinationName | contains("'$logdestination'")) .arn'`
FIREHOSE_DESTINATION_NAME=`echo $DESCRIBE_DESTINATIONS | jq -r '.destinations[]| select (.destinationName | contains("'$logdestination'")) .destinationName'`
FIREHOSE_ACCESS_POLICY=`echo $DESCRIBE_DESTINATIONS | jq -r '.destinations[]| select (.destinationName | contains("'$logdestination'")) .accessPolicy'`
echo $FIREHOSE_ACCESS_POLICY | jq '.Statement[0].Principal.AWS = (.Statement[0].Principal.AWS | if type == "array" then . += ["'$SECLOG_ACCOUNT_ID'", "'$ORG_ACCOUNT_ID'"] else [.,"'$SECLOG_ACCOUNT_ID'", "'$ORG_ACCOUNT_ID'"] end)' > ./SecLogAccessPolicy.json

export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID_DEVOPS
export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY_DEVOPS
export AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN_DEVOPS

export $(printf "AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s" \
  $(aws sts assume-role \
  --role-arn arn:aws:iam::$AccountId:role/BrokerAccessAdminRole \
  --role-session-name BrokerAccessAdminRole_client_session \
  --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" \
  --output text))

# Create the stack in eu-west-1
aws cloudformation create-stack \
  --region eu-west-1 \
  --stack-name SECLZ-Guardduty-detector \
  --parameters ParameterKey=FirehoseDestinationArn,ParameterValue=$FIREHOSE_ARN \
  --capabilities CAPABILITY_NAMED_IAM \
  --template-body file://<(cat <<'EOF'
AWSTemplateFormatVersion: 2010-09-09

#   --------------------------------------------------------
#   Version History
#
#   v1.0.0  A.Tutunaru   Initial Version
#   --------------------------------------------------------

Description: >-
  v1.0. Script to create Guardduty detector

Metadata: 
  AWS::CloudFormation::Interface:
    ParameterGroups:
      -
        Label:
          default: "Guardduty"
        Parameters:
          - FirehoseDestinationArn

Parameters:
  FirehoseDestinationArn:
    Type: String
    Description: The ARN of the firehose stream aggregating the logs in the DIGIT C2 Log Aggregation Central Account
      
Resources:
  GuardDutyLogGroup:
    Type: AWS::Logs::LogGroup
    UpdateReplacePolicy: Retain
    Properties:
      LogGroupName: /aws/events/guardduty
      RetentionInDays: 60

  AwsGuardDutySubscriptionFilter:
    Type: AWS::Logs::SubscriptionFilter
    DependsOn: GuardDutyLogGroup
    Properties:
      DestinationArn: !Ref 'FirehoseDestinationArn'
      FilterPattern: ''
      LogGroupName: !Ref 'GuardDutyLogGroup'

  AWSEventsInvokeEventBusRole:
    Type: AWS::IAM::Role
    Properties: 
      RoleName: AWSEventsInvokeEventBusRole
      Description: "Service Linked role to send messages to event bus"
      AssumeRolePolicyDocument:
        Version: 2012-10-17
        Statement:
          - Effect: Allow
            Principal:
              Service:
                - events.amazonaws.com
            Action:
              - 'sts:AssumeRole'
      Policies:
        - PolicyName: AWSEventsInvokeEventBusSecLog
          PolicyDocument:
            Version: 2012-10-17
            Statement:
              - Effect: Allow
                Action: "events:PutEvents"
                Resource: !Join 
                  - ''
                  - - 'arn:aws:events:'
                    - !Sub "eu-west-1:${AWS::AccountId}:"
                    - 'event-bus/default'
 
  CloudWatchEventsLogGroupRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service:
                - events.amazonaws.com
            Action:
              - sts:AssumeRole
      Policies:
        - PolicyName: SECLZ-CloudWatchEvents-policy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
            - Effect: Allow
              Action: logs:CreateLogStream
              Resource:
              - !GetAtt GuardDutyLogGroup.Arn
            - Effect: Allow
              Action: logs:PutLogEvents
              Resource:
              - !GetAtt GuardDutyLogGroup.Arn
            

  # GuardDuty CloudWatch Event - For GuardDuty
  GuardDutyEvents: 
    Type: AWS::Events::Rule
    DependsOn: GuardDutyLogGroup
    Properties: 
      Name: SECLZ-GuardDuty-Event
      RoleArn: 
        Fn::GetAtt: 
        - "CloudWatchEventsLogGroupRole"
        - "Arn"
      Description: "GuardDuty Event Handler"
      EventPattern: 
        source:
        - aws.guardduty
      State: ENABLED
      Targets:
        -
          Arn: !Sub "arn:aws:logs:eu-west-1:${AWS::AccountId}:log-group:${GuardDutyLogGroup}"
          Id: "AwsGuardDutyCloudWatch"
 
  AWSCloudFormationStackSetAdministrationRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: AWSCloudFormationStackSetAdministrationRole
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: cloudformation.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AdministratorAccess

  AWSCloudFormationStackSetExecutionRole:
    Type: AWS::IAM::Role
    DependsOn: AWSCloudFormationStackSetAdministrationRole
    Properties:
      RoleName: AWSCloudFormationStackSetExecutionRole
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              AWS: !Sub "arn:aws:iam::${AWS::AccountId}:role/AWSCloudFormationStackSetAdministrationRole"
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AdministratorAccess

  TrustEventsToStoreLogEventsPolicy:
    Type: AWS::Logs::ResourcePolicy
    Properties:
      PolicyDocument: !Sub "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"TrustEventsToStoreLogEvent\",\"Effect\":\"Allow\",\"Principal\":{\"Service\":[\"delivery.logs.amazonaws.com\",\"events.amazonaws.com\"]},\"Action\":[\"logs:PutLogEvents\",\"logs:CreateLogStream\"],\"Resource\":\"arn:aws:logs:*:${AWS::AccountId}:log-group:/aws/events/*:*\"}]}"
      PolicyName: TrustEventsToStoreLogEvents
EOF
)

# Check if stack creation command succeeded
if [ $? -ne 0 ]; then
  echo "Failed to start stack creation in region eu-west-1."
  exit 1
fi

echo "Waiting for stack creation in region eu-west-1 to complete..."

# Wait for stack creation to complete
aws cloudformation wait stack-create-complete --region eu-west-1 --stack-name SECLZ-Guardduty-detector

# Check the wait command result
if [ $? -eq 0 ]; then
  echo "Stack SECLZ-Guardduty-detector created successfully in region eu-west-1."
else
  echo "Stack creation in region eu-west-1 failed or timed out."
  exit 1
fi

# Create the stack set

echo "Creating StackSet SECLZ-Guardduty-detector..."

aws cloudformation create-stack-set \
  --region eu-west-1 \
  --stack-set-name SECLZ-Guardduty-detector \
  --permission-model SELF_MANAGED \
  --template-body file://<(cat <<'EOF'
AWSTemplateFormatVersion: 2010-09-09

#   --------------------------------------------------------
#   Version History
#
#   v1.0.0  A.Tutunaru   Initial Version
#   --------------------------------------------------------

Description: >-
  v1.0. Script to create Guardduty detector

Metadata: 
  AWS::CloudFormation::Interface:
    ParameterGroups:
      -
        Label:
          default: "Guardduty"

Resources:
  # Enable notifications for AWS GuardDuty Rule compliance changes to the event bus in region eu-west-1
  GuardDutyRuleComplianceChangeEvent:
    Type: AWS::Events::Rule
    Properties:
      Name: SECLZ-GuardDuty-Events-CloudWatch-Rule
      Description: 'Landing Zone rule to send notification on GuardDuty Events to the event bus in eu-west-1.'
      EventPattern:
        {
          "source": [
            "aws.guardduty"
          ]
        }
      State: ENABLED
      Targets:
      - Id: "AccountTargetId"
        Arn: !Sub "arn:aws:events:eu-west-1:${AWS::AccountId}:event-bus/default"
        RoleArn: !Sub "arn:aws:iam::${AWS::AccountId}:role/AWSEventsInvokeEventBusRole"
EOF
)

if [ $? -ne 0 ]; then
  echo "Failed to create StackSet."
  exit 1
fi

echo "StackSet created successfully."

echo "Creating StackSet instances in regions: ${REGIONS[*]}..."

OPERATION_ID=$(aws cloudformation create-stack-instances \
  --stack-set-name SECLZ-Guardduty-detector \
  --region eu-west-1 \
  --regions "${REGIONS[@]}" \
  --accounts "$(aws sts get-caller-identity --query Account --output text)" \
  --operation-preferences RegionConcurrencyType=PARALLEL \
  --query "OperationId" --output text)

if [ -z "$OPERATION_ID" ]; then
  echo "Failed to start stack set instance creation."
  exit 1
fi

echo "StackSet instance creation started with OperationId: $OPERATION_ID"

# Polling the stack set operation status until it finishes
while true; do
  STATUS=$(aws cloudformation describe-stack-set-operation \
    --stack-set-name SECLZ-Guardduty-detector \
    --region eu-west-1 \
    --operation-id "$OPERATION_ID" \
    --query "StackSetOperation.Status" --output text)

  echo "Current operation status: $STATUS"

  case "$STATUS" in
    FAILED|STOPPED)
      echo "StackSet operation failed or stopped."
      exit 1
      ;;
    SUCCEEDED)
      echo "StackSet operation completed successfully."
      break
      ;;
    RUNNING|STOPPING)
      echo "Waiting for operation to complete..."
      sleep 15
      ;;
    *)
      echo "Unknown operation status: $STATUS"
      exit 1
      ;;
  esac
done

echo "All done!"