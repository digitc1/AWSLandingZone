import * as cdk from '@aws-cdk/core';
import * as iam from '@aws-cdk/aws-iam';

interface SeclogRoleProps extends cdk.StackProps {
  readonly env : cdk.Environment,
  readonly accounts: string[],
}

export class SeclogRoleStackSet extends cdk.Stack {
  constructor(scope: cdk.Construct, id: string, props: SeclogRoleProps) {
    super(scope, id, props);

    // 👇 Create AWSCloudFormationStackSetAdministrationRole on the Seclog
    const administrationRole = new iam.Role(this, 'AWSCloudFormationStackSetAdministrationRole', {
      roleName: "AWSCloudFormationStackSetAdministrationRole",
      assumedBy: new iam.ServicePrincipal('cloudformation.amazonaws.com'),
      description: 'Creates an IAM Role in the SecLog account to assume a role and give permission to cloudformation to deploy StackSet instances on target accounts. Configure the AWSCloudFormationStackSetAdministrationRole to enable use of AWS CloudFormation StackSets. Create this CloudFormation stack only in the SecLog account',
    });

    // 👇 Create AssumeRole-AWSCloudFormationStackSetExecutionRole Managed Policy and associate it with the role AWSCloudFormationStackSetAdministrationRole
    const ExecutionPolicy = new iam.ManagedPolicy(this, 'AssumeRole-AWSCloudFormationStackSetExecutionRole', {
      description: 'Allows SECLOG to assume the role AWSCloudFormationStackSetExecutionRole on LINKED accounts',
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: ['sts:AssumeRole'],
          resources: ['arn:aws:iam::*:role/AWSCloudFormationStackSetExecutionRole'],
        }),
      ],
      roles: [administrationRole],
    });

    // Stackset used to deploy roles on the SECLOG and the LINKED accounts in eu-west-1
    new cdk.CfnStackSet(this, "SECLZSeclogRoleCreateStackSet", {
        description: "Deploy the IAM roles required by the SECLOG to manage linked accounts",
        stackSetName: "SECLZSeclogManagedStackSet",
        permissionModel: "SELF_MANAGED",
        executionRoleName: "AWSCloudFormationStackSetExecutionRole",
        operationPreferences: {
            maxConcurrentCount: 10,
            failureToleranceCount: 9,
            regionConcurrencyType: "PARALLEL",
        },
        stackInstancesGroup: [
          {
              regions: ["eu-west-1"],
              deploymentTargets: {
                accounts: props.accounts,
              },
          },
        ],
        capabilities: ["CAPABILITY_NAMED_IAM"],
        templateBody: `
        AWSTemplateFormatVersion: 2010-09-09
        Description: deploy roles to allow the seclog to manage linked accounts
        Parameters:      
          SeclogAccountId:
            Type: AWS::SSM::Parameter::Value<String>
            Default: '/org/member/SecLogMasterAccountId'
            Description: SecLog Account ID
        Resources:
          LambdasSeclogAssumeRole:
            Type: AWS::IAM::Role
            Properties:
              RoleName: "SECLZ-SeclogRole"
              Description: Allow lambdas in seclog to assume lambda execution role in this account
              ManagedPolicyArns:
                - arn:aws:iam::aws:policy/AWSSecurityHubFullAccess
                - arn:aws:iam::aws:policy/AmazonGuardDutyFullAccess
              AssumeRolePolicyDocument:
                Version: "2012-10-17"
                Statement:
                  -
                    Effect: "Allow"
                    Principal:
                      AWS: 
                        Fn::Join:
                        - ""
                        - - "arn:aws:iam::"
                          - Ref: SeclogAccountId
                          - ":role/SECLZ-lambdasExecutionRole"
                    Action:
                      - "sts:AssumeRole"
              Path: "/"
      `,
    });
  }
}
