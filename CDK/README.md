# Welcome to the CDK TypeScript project for the AWS Landing Zone!

The `cdk.json` file tells the CDK Toolkit how to execute your app.

This CDK project deploys in the SECLOG account:

 * A lambda function configured to DISABLE/ENABLE one single CIS control
 * A stepfunctions workflow configured to update multiple CIS controls in multiple AWS regions of one single AWS account
 * A cloudformation stackset on the seclog account to deploy the IAM role SECLZ-SeclogRole in all accounts (seclog+linked). This role will allow the lambda function called by the stepfunction to enable or disable a CIS control in the SECLOG and its linkeds accounts

## Useful CDK commands

 * `npm run build`   compile typescript to js
 * `npm run watch`   watch for changes and compile
 * `npm run test`    perform the jest unit tests
 * `cdk deploy`      deploy this stack to your default AWS account/region
 * `cdk diff`        compare deployed stack with current state
 * `cdk synth`       emits the synthesized CloudFormation template

## Shell wrappers to deploy or undeploy the CDK stacks

 * `sh bin/cdk-deploy --seclog_accountid <123456789012> --linked_accountids 12345678902,123456789012,....`
 * `sh bin/cdk-destroy --seclog_accountid <123456789012> --linked_accountids 12345678902,123456789012,....`

## execution of the workflow defined in AWSstepfunctions

To reproduce the CIS updates implemented in the release 1.5.0

 * `aws stepfunctions start-execution --state-machine-arn <workflow arn> --input file://run1.json`
 * `aws stepfunctions start-execution --state-machine-arn <workflow arn> --input file://run2.json`
 * `aws stepfunctions start-execution --state-machine-arn <workflow arn> --input file://run3.json`
 * `aws stepfunctions start-execution --state-machine-arn <workflow arn> --input file://run4.json`


### run1.json

{   
  "accountid" : 12345678902,
  "regions" : ["ap-northeast-1","ap-northeast-2","ap-northeast-3","ap-south-1","ap-southeast-1","ap-southeast-2","ca-central-1","eu-central-1","eu-north-1","eu-west-1", "eu-west-2","eu-west-3","sa-east-1","us-east-1","us-east-2","us-west-1","us-west-2"],
  "rule": "cis-aws-foundations-benchmark/v/1.2.0",
  "checks" : ["3.1", "3.2", "3.3", "3.4", "3.5", "3.6", "3.7", "3.8", "3.9", "3.10", "3.11", "3.12", "3.13", "3.14"],
  "disabled" : true,
  "reason" : "Alarm action unmanaged by SNS but cloudwatch event",
  "exclusions" : ["ap-northeast-3"]
}

### run2.json

{   
  "accountid" : 12345678902,
  "regions" : ["ap-northeast-1","ap-northeast-2","ap-northeast-3","ap-south-1","ap-southeast-1","ap-southeast-2","ca-central-1","eu-central-1","eu-north-1","eu-west-1", "eu-west-2","eu-west-3","sa-east-1","us-east-1","us-east-2","us-west-1","us-west-2"],
  "rule": "aws-foundational-security-best-practices/v/1.0.0",
  "checks" : ["IAM.1", "IAM.2", "IAM.3", "IAM.4", "IAM.6", "IAM.7", "Config.1"],
  "disabled" : true,
  "reason" : "Disable recording of global resources in all but one Region",
  "exclusions" : ["eu-west-1", "ap-northeast-3"]
}

### run3.json

{   
  "accountid" : 12345678902,
  "regions" : ["eu-west-1"],
  "rule": "cis-aws-foundations-benchmark/v/1.2.0",
  "checks" : ["1.14"],
  "disabled" : true,
  "reason" : "Managed by Cloud Broker Team",
  "exclusions" : []
}

### run4.json

{   
  "accountid" : 12345678902,
  "regions" : ["eu-west-1"],
  "rule": "aws-foundational-security-best-practices/v/1.0.0",
  "checks" : ["IAM.6"],
  "disabled" : true,
  "reason" : "Managed by Cloud Broker Team",
  "exclusions" : []
}
