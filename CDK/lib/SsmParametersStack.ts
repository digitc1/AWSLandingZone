import * as cdk from '@aws-cdk/core';
import * as ssm from '@aws-cdk/aws-ssm';
import * as m from  '../conf/manifest.json';

interface SsmParametersProps extends cdk.StackProps {
  readonly env : cdk.Environment,
  readonly accounts: string[],
  readonly manifest: string,
}

export class SsmParametersStack extends cdk.Stack {
  constructor(scope: cdk.Construct, id: string, props: SsmParametersProps) {
    super(scope, id, props);

    let seclog_cloudtrail_groupname = m.ssm.cloudtrail_groupname.value;
    let cloudtrail_insight_groupname = m.ssm.insight_groupname.value;
    let config_groupname = m.ssm.config_groupname.value;

    new ssm.StringParameter(this, '/org/member/SecLog_cloudtrail-groupname', {
      parameterName: '/org/member/SecLog_cloudtrail-groupname',
      description: 'The name of the cloudwatch loggroup for cloudtrail logs',
      stringValue: seclog_cloudtrail_groupname
    });
    new ssm.StringParameter(this, '/org/member/SecLog_insight-groupname', {
      parameterName: '/org/member/SecLog_insight-groupname',
      description: 'The name of the cloudwatch loggroup for cloudtrail insight logs',
      stringValue: cloudtrail_insight_groupname
    });
    new ssm.StringParameter(this, '/org/member/SecLog_config-groupname', {
      parameterName: '/org/member/SecLog_config-groupname',
      description: 'The name of the cloudwatch loggroup for aws config logs',
      stringValue: config_groupname
    });

  }
}
