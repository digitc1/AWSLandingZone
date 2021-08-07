import * as cdk from '@aws-cdk/core';
import * as ssm from '@aws-cdk/aws-ssm';
// import { env } from 'process';

interface manifestProps extends cdk.StackProps {
  readonly env : cdk.Environment,
  readonly seclog_cloudtrail_groupname: string,
  readonly cloudtrail_insight_groupname: string,
  readonly config_groupname: string,
  readonly guardduty_groupname : string,
  readonly notification_mail: string,
  readonly seclog_ou : string,
  readonly securityhub_groupname : string,
  readonly alarms_groupname : string,
  readonly slz_version: string,
  readonly seclogid: string,
}
export class SsmParametersStack extends cdk.Stack {
  constructor(scope: cdk.Construct, id: string, props: manifestProps) {
    super(scope, id, props);

    new ssm.StringParameter(this, '/org/member/SecLog_cloudtrail-groupname', {
      parameterName: '/org/member/SecLog_cloudtrail-groupname',
      description: 'The name of the cloudwatch loggroup for cloudtrail logs',
      stringValue: props.seclog_cloudtrail_groupname
    });
    new ssm.StringParameter(this, '/org/member/SecLog_insight-groupname', {
      parameterName: '/org/member/SecLog_insight-groupname',
      description: 'The name of the cloudwatch loggroup for cloudtrail insight logs',
      stringValue: props.cloudtrail_insight_groupname
    });
    new ssm.StringParameter(this, '/org/member/SecLog_config-groupname', {
      parameterName: '/org/member/SecLog_config-groupname',
      description: 'The name of the cloudwatch loggroup for aws config logs',
      stringValue: props.config_groupname
    });
    new ssm.StringParameter(this, '/org/member/SecLog_securityhub-groupname', {
      parameterName: '/org/member/SecLog_securityhub-groupname',
      description: 'The name of the cloudwatch loggroup for aws securityhub',
      stringValue: props.securityhub_groupname
    });
    new ssm.StringParameter(this, '/org/member/SecLog_alarms-groupname', {
      parameterName: '/org/member/SecLog_alarms-groupname',
      description: 'The name of the cloudwatch loggroup for cloudwatch alarms',
      stringValue: props.alarms_groupname
    });
    new ssm.StringParameter(this, '/org/member/SLZVersion', {
      parameterName: '/org/member/SLZVersion',
      description: 'The version of the Landing Zone',
      stringValue: props.slz_version
    });
    new ssm.StringParameter(this, '/org/member/SecLogMasterAccountId', {
      parameterName: '/org/member/SecLogMasterAccountId',
      description: 'The account id of the seclog account',
      stringValue: props.seclogid
    });
    new ssm.StringParameter(this, '/org/member/SecLog_notification-mail', {
      parameterName: '/org/member/SecLog_notification-mail',
      description: 'The email used for the SNS subscription',
      stringValue: props.notification_mail
    });

    new ssm.StringParameter(this, '/org/member/SecLogOU', {
      parameterName: '/org/member/SecLogOU',
      description: 'The OU where the seclog account resides in the AWS organisation',
      stringValue: props.seclog_ou
    });
    

    // TODO : to be created in all AWS regions managed by the LZ ?!?
    new ssm.StringParameter(this, '/org/member/SecLog_guardduty-groupname', {
      parameterName: '/org/member/SecLog_guardduty-groupname',
      description: 'The name of the cloudwatch loggroup for aws guardduty',
      stringValue: props.guardduty_groupname
    });
    
  }
}
