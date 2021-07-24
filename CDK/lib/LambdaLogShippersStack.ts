import * as iam from '@aws-cdk/aws-iam';
import * as cdk from '@aws-cdk/core';
import * as lambda from '@aws-cdk/aws-lambda';
import * as s3 from '@aws-cdk/aws-s3';
import * as logs from '@aws-cdk/aws-logs';
import * as s3n from '@aws-cdk/aws-s3-notifications';
import * as dynamodb from '@aws-cdk/aws-dynamodb';

interface LambdaLogShipperProps extends cdk.StackProps {
  readonly env : cdk.Environment,
  readonly ConfigBucketName: string,
  readonly CloudtrailBucketName: string,
  readonly CloudtrailLogGroup: string,
  readonly CloudtrailInsightLogGroup: string,
  readonly ConfigLogGroup: string,
}

export class LambdaLogShippersStack extends cdk.Stack {
  public readonly lambdaExecutionRole: iam.Role;

  constructor(scope: cdk.Construct, id: string, props: LambdaLogShipperProps) {
    super(scope, id, props);

    const configBucket = s3.Bucket.fromBucketName(
      this,
      "my-config-bucket",
      props.ConfigBucketName,
    );

    const seclzSyncLogs = new dynamodb.Table(this, 'SECLZSyncLogs', {
      tableName : 'SECLZSyncLogs',
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST, 
      partitionKey : {
        name : "LogGroupName",
        type : dynamodb.AttributeType.STRING
        },
      sortKey : {
        name : "LogStreamName",
        type : dynamodb.AttributeType.STRING
        },
      timeToLiveAttribute: 'TTL',
    });
    
    const cloudtrailBucket = s3.Bucket.fromBucketName(
      this,
      "my-cloudtrail-bucket",
      props.CloudtrailBucketName,
    );
    

    // 👇 Create a Role
    this.lambdaExecutionRole = new iam.Role(this, 'SECLZ-LambdaLogShippersExecutionRole', {
      roleName: "SECLZ-LambdaLogShippersExecutionRole",
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaVPCAccessExecutionRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),        
      ],
      description: 'Execution role of the lambda called by the stepfunctions of the SECLZ',
    });

    const cloudtrailLogGroup = logs.LogGroup.fromLogGroupName(this,'cloudtrailLogGroup',props.CloudtrailLogGroup);
    const cloudtrailInsightLogGroup = logs.LogGroup.fromLogGroupName(this,'cloudtrailInsightLogGroup',props.CloudtrailInsightLogGroup);
    const configLogGroup = logs.LogGroup.fromLogGroupName(this,'configLogGroup',props.ConfigLogGroup);

    // 👇 Set various inline policies in lambdaExecutionRole to allow the lambda to update
    // the DynamoDB table (rw)
    // the cloudwatch loggroups (rw)
    // the sources s3 buckets (r)
    configBucket.grantRead(this.lambdaExecutionRole);
    cloudtrailBucket.grantRead(this.lambdaExecutionRole);
    this.lambdaExecutionRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        resources: [
          cloudtrailLogGroup.logGroupArn,
          cloudtrailInsightLogGroup.logGroupArn,
          configLogGroup.logGroupArn,
        ],
        actions: [            
          'logs:CreateLogGroup',
          'logs:CreateLogStream',
          'logs:DescribeLogStreams',
          'logs:PutLogEvents',
        ]
      })
    );

    this.lambdaExecutionRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        resources: [
          seclzSyncLogs.tableArn,
        ],
        actions: [
          'dynamodb:GetItem',
          'dynamodb:PutItem',
          'dynamodb:DeleteItem',
          'dynamodb:DescribeTable',
        ]
      })
    );

    // The code that defines your stack goes here
    const ConfigLogShipperFunction = new lambda.Function(this, "SECLZ-ConfigLogShipperFunction", {
      functionName: "SECLZ-ConfigLogShipperFunction",
      runtime: lambda.Runtime.PYTHON_3_8,
      code: lambda.Code.fromAsset('lambdas/ConfigLogShipper'),
      handler: "ConfigLogShipper.lambda_handler",
      logRetention: logs.RetentionDays.TWO_WEEKS,
      memorySize: 128,
      timeout: cdk.Duration.seconds(900),
      description: `Function generated on: ${new Date().toISOString()}`,
      role: this.lambdaExecutionRole,
      environment: {
          "LOG_LEVEL": "INFO",
          "MAX_TRY": "30",
          "CLOUDTRAIL_LOG_GROUP": props.CloudtrailLogGroup,
          "INSIGHT_LOG_GROUP": props.CloudtrailInsightLogGroup,
      }
    });

    configBucket.addEventNotification(s3.EventType.OBJECT_CREATED_PUT, new s3n.LambdaDestination(ConfigLogShipperFunction));


    // The code that defines your stack goes here
    const CloudtrailLogShipperFunction = new lambda.Function(this, "SECLZ-CloudtrailLogShipperFunction", {
      functionName: "SECLZ-CloudtrailLogShipperFunction",
      runtime: lambda.Runtime.PYTHON_3_8,
      code: lambda.Code.fromAsset('lambdas/CloudtrailLogShipper'),
      handler: "CloudtrailLogShipper.lambda_handler",
      logRetention: logs.RetentionDays.TWO_WEEKS,
      memorySize: 128,
      timeout: cdk.Duration.seconds(900),
      description: `Function generated on: ${new Date().toISOString()}`,
      role: this.lambdaExecutionRole,
      environment: {
          "LOG_LEVEL": "INFO",
          "MAX_TRY": "30",
          "CONFIG_LOG_GROUP": props.ConfigLogGroup,
      }
    });

    cloudtrailBucket.addEventNotification(s3.EventType.OBJECT_CREATED_PUT, new s3n.LambdaDestination(CloudtrailLogShipperFunction));

  }
}