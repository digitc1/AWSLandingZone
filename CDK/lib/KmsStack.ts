import * as cdk from '@aws-cdk/core';
import * as kms from '@aws-cdk/aws-kms';
import * as ssm from '@aws-cdk/aws-ssm';
import { CfnOutput } from '@aws-cdk/core';
interface kmsProps extends cdk.StackProps {
  readonly env : cdk.Environment,
}

export class KmsStack extends cdk.Stack {
  constructor(scope: cdk.Construct, id: string, props: kmsProps) {
    super(scope, id, props);

    const kmsKey = new kms.Key(this, 'SECLZ-KmsKey', {
      enableKeyRotation: true,
      pendingWindow: cdk.Duration.days(10),
      trustAccountIdentities: true  // delegate key permissions to IAM
      // By setting trustAccountIdentities to true we are able to grant access to the key by only using IAM.
      // If we left this set to false we would need to add permissions to access the key
      // on both the KMS Key policy and on the IAM policy.
    });

    // kmsKey.addAlias('alias/SECLZ-Cloudtrail-encryption-key');

    new ssm.StringParameter(this, '/org/member/SECLZ-KmsKeyArn', {
      parameterName: '/org/member/SECLZ-KmsKeyArn',
      description: 'Contains the KMS key arn of the LandingZone in the seclog account',
      stringValue: kmsKey.keyArn
    });

    new CfnOutput(this, 'kmsarn', {
      value : kmsKey.keyArn,
      exportName : this.stackName+'-KeyId'
    })
  }
}
