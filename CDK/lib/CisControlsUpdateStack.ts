import * as iam from '@aws-cdk/aws-iam';
import * as cdk from '@aws-cdk/core';
import * as lambda from '@aws-cdk/aws-lambda';
import * as sfn from '@aws-cdk/aws-stepfunctions';
import * as tasks from '@aws-cdk/aws-stepfunctions-tasks';


export class CisControlsUpdateStack extends cdk.Stack {
  public readonly lambdaExecutionRole: iam.Role;

  constructor(scope: cdk.Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);


// export class SlzRolesStack extends cdk.Stack {
//   constructor(scope: cdk.App, id: string, props?: cdk.StackProps) {
//     super(scope, id, props);

    // 👇 Create a Role
    this.lambdaExecutionRole = new iam.Role(this, 'SECLZ-lambdasExecutionRole', {
      roleName: "SECLZ-lambdasExecutionRole",
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaVPCAccessExecutionRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),        
      ],
      description: 'Execution role of the lambda called by the stepfunctions of the SECLZ',
    });


    // 👇 Create a Managed Policy and associate it with the role
    const lambdaManagedPolicy = new iam.ManagedPolicy(this, 'SECLZ-lambdasManagedPolicy', {
      description: 'Allows lambdas on SECLOG to assume the role SECLZ-SeclogRole on LINKED accounts',
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: ['sts:AssumeRole'],
          resources: ['arn:aws:iam::*:role/SECLZ-SeclogRole'],
        }),
      ],
      roles: [this.lambdaExecutionRole],
    });

    // The code that defines your stack goes here
    const CisControlUpdateLambda = new lambda.Function(this, "SECLZ-CisControlUpdateLambda", {
      functionName: "SECLZ-CisControlUpdateLambda",
      runtime: lambda.Runtime.PYTHON_3_8,
      code: lambda.Code.fromAsset('lambdas/cis-update-control'),
      handler: "cis-update-control.lambda_handler",
      memorySize: 128,
      timeout: cdk.Duration.seconds(10),
      description: `Function generated on: ${new Date().toISOString()}`,
      role: this.lambdaExecutionRole,
    });


    // this.exportValue(this.lambdaExecutionRole);

    const initialState = new sfn.Pass(this, 'Initial State', {
      comment: "Entry point"
    });

    const catchAllState = new sfn.Pass(this, 'Catch All State', {
      comment: "Catch all Errors"
    });

    const finalState = new sfn.Pass(this, 'Final State', {
      comment: "Exit point"
    });

    const lambdaState = new tasks.LambdaInvoke(this,'Lambda Invoke', {
      lambdaFunction : CisControlUpdateLambda,
      timeout: cdk.Duration.seconds(10),
      payloadResponseOnly: true,
      // resultSelector: { "statusCode.$": "$.Payload.statusCode", "body.$": "$.Payload.body" },
      outputPath : '$.body'
    }).addCatch(catchAllState);

    const cisChecks = new sfn.Map(this,'CIS Checks', {
      maxConcurrency: 2,
      itemsPath: '$.checks',
      parameters: { 
        "accountid.$": "$.accountid", 
        "disabled.$": "$.disabled", 
        "rule.$": "$.rule", 
        "reason.$": "$.reason", 
        "exclusions.$": "$.exclusions", 
        "region.$": "$.region", 
        "check.$": "$$.Map.Item.Value"
      }
    }).iterator(lambdaState);

    const slzRegions = new sfn.Map(this,'slz-regions', {
      maxConcurrency: 20,
      itemsPath: '$.regions',
      parameters: {
        "accountid.$": "$.accountid",
        "disabled.$": "$.disabled",
        "rule.$": "$.rule",
        "reason.$": "$.reason",
        "exclusions.$": "$.exclusions",
        "checks.$": "$.checks",
        "region.$": "$$.Map.Item.Value"
      }
    }).iterator(cisChecks);

    const definition = initialState
    .next(slzRegions)
    .next(finalState);

    new sfn.StateMachine(this, 'SECLZ-CISControlsUpdate', {
        stateMachineName : 'SECLZ-CISControlsUpdate',
        definition,
        timeout: cdk.Duration.minutes(5)
    });

  }
}