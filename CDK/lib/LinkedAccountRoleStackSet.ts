import * as cdk from '@aws-cdk/core';
import * as iam from '@aws-cdk/aws-iam';

interface LinkedAccountRoleProps extends cdk.StackProps {
  readonly env : cdk.Environment,
}

export class LinkedAccountRoleStackSet extends cdk.Stack {
  constructor(scope: cdk.Construct, id: string, props: LinkedAccountRoleProps) {
    super(scope, id, props);

    // 👇 Create AWSCloudFormationStackSetExecutionRole on the Seclog and Linked accounts
    new iam.Role(this, 'AWSCloudFormationStackSetExecutionRole', {
      roleName: "AWSCloudFormationStackSetExecutionRole",
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AdministratorAccess'),
      ],
      assumedBy: new iam.AccountPrincipal(this.account),
      description: 'Creates an IAM Role in the SecLog and linked accounts to assume a role and give permission to cloudformation to deploy stacks from a StackSet instance on target accounts.',
    });

  }
}
