if [ $# -lt 2 ]; then
  echo "Usage: $0 AccountId SecLogMasterAccountId"
  exit 1
fi

AccountId="$1"
SecLogMasterAccountId="$2"

REGIONS=("us-east-1" "us-east-2" "us-west-1" "us-west-2" "ap-south-1" "ap-northeast-1" "ap-northeast-2" "ap-northeast-3" "ap-southeast-1" "ap-southeast-2" "ca-central-1" "eu-west-1" "eu-west-2" "eu-west-3" "eu-central-1" "eu-north-1" "sa-east-1")

export $(printf "AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s" \
  $(aws sts assume-role \
  --role-arn arn:aws:iam::$AccountId:role/BrokerAccessAdminRole \
  --role-session-name BrokerAccessAdminRole_kosovo_session \
  --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken]" \
  --output text))

# Create the stack in eu-west-1
aws cloudformation create-stack \
  --region eu-west-1 \
  --stack-name SECLZ-Guardduty-detector \
  --parameters ParameterKey=SecLogMasterAccountId,ParameterValue=$SecLogMasterAccountId \
  --capabilities CAPABILITY_NAMED_IAM \
  --template-body file://<(cat <<'EOF'
AWSTemplateFormatVersion: 2010-09-09

#   --------------------------------------------------------
#   Version History
#
#   v1.0.0  A.Tutunaru   Initial Version
#   --------------------------------------------------------

Description: >-
  v1.0. Script to create the EventBridge rules for Guardduty events

Metadata: 
  AWS::CloudFormation::Interface:
    ParameterGroups:
      -
        Label:
          default: "Guardduty"

Parameters:
  SecLogMasterAccountId:
    Type: String
    Description: "Contains account id of SecLogMaster"

Resources:
  AWSEventsInvokeEventBusSecLogRole:
    Type: AWS::IAM::Role
    Properties: 
      RoleName: AWSEventsInvokeEventBusSecLogRole
      Description: "Service Linked role to send messages to the eu-west-1 event bus of the SecLog account"
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
                    - !Sub "eu-west-1:${SecLogMasterAccountId}:"
                    - 'event-bus/default'

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
  --parameters ParameterKey=SecLogMasterAccountId,ParameterValue=$SecLogMasterAccountId \
  --permission-model SELF_MANAGED \
  --template-body file://<(cat <<'EOF'
AWSTemplateFormatVersion: 2010-09-09

#   --------------------------------------------------------
#   Version History
#
#   v1.0.0  A.Tutunaru   Initial Version
#   --------------------------------------------------------

Description: >-
  v1.0. Script to create the EventBridge rules for Guardduty events

Metadata: 
  AWS::CloudFormation::Interface:
    ParameterGroups:
      -
        Label:
          default: "Guardduty"

Parameters:
  SecLogMasterAccountId:
    Type: String
    Description: "Contains account id of SecLogMaster"

Resources:
  GuardDutyRuleComplianceChangeEvent:
    Type: AWS::Events::Rule
    Properties:
      Name: SECLZ-GuardDuty-Events-CloudWatch-Rule-To-SecLog
      Description: 'Landing Zone rule to send notification on GuardDuty Events to the SecLog event bus in eu-west-1.'
      EventPattern:
        {
          "source": [
            "aws.guardduty"
          ]
        }
      State: ENABLED
      Targets:
      - Id: "AccountTargetId"
        Arn: !Sub "arn:aws:events:eu-west-1:${SecLogMasterAccountId}:event-bus/default"
        RoleArn: !Sub "arn:aws:iam::${AWS::AccountId}:role/AWSEventsInvokeEventBusSecLogRole"
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