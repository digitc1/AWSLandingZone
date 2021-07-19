import * as cdk from '@aws-cdk/core';
interface SeclogRoleProps extends cdk.StackProps {
  readonly env : cdk.Environment,
  readonly accounts: string[],
}

export class SeclogRoleStackSet extends cdk.Stack {
  
    constructor(scope: cdk.Construct, id: string, props: SeclogRoleProps) {
      super(scope, id, props);

    new cdk.CfnStackSet(this, "SECLZSeclogRoleCreateStackSet", {
        description: "Deploy the IAM roles required by the SECLOG to manage linked accounts",
        stackSetName: "SECLZSeclogManagedStackSet",
        permissionModel: "SELF_MANAGED",
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
        Description: deploy role to allow the seclog to manage linked accounts
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
