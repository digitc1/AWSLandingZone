#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from '@aws-cdk/core';

import * as m from  '../conf/manifest.json';

import { LambdaLogShippersStack } from '../lib/LambdaLogShippersStack';
import { CisControlsUpdateStack } from '../lib/CisControlsUpdateStack';
import { SeclogRoleStackSet } from '../lib/SeclogRoleStackSet';
import { SsmParametersStack } from '../lib/SsmParametersStack';


const app = new cdk.App();

var all_accounts = [] as string[];
const seclog_accountid = app.node.tryGetContext('seclog_accountid') as string;
const seclog = { account: seclog_accountid, region: 'eu-west-1' };
const linked_accountids = app.node.tryGetContext('linked_accountids') as string;
const manifest = app.node.tryGetContext('manifest') as string;

if (linked_accountids) {
  all_accounts = linked_accountids.split(',');
}
all_accounts.push(seclog_accountid);

cdk.Tags.of(app).add("Project", "secLZ");
cdk.Tags.of(app).add("Owner", "DIGIT.C.1");
cdk.Tags.of(app).add("Environment", "prod");
cdk.Tags.of(app).add("Criticity", "high");
cdk.Tags.of(app).add("Confidentiality", "confidential");
cdk.Tags.of(app).add("Organization", "EC");
cdk.Tags.of(app).add("ApplicationRole", "security");

const ssmParametersStack = new SsmParametersStack(app, 'SECLZ-SsmParametersStack', {
  /* If you don't specify 'env', this stack will be environment-agnostic.
   * Account/Region-dependent features and context lookups will not work,
   * but a single synthesized template can be deployed anywhere. */

  /* Uncomment the next line to specialize this stack for the AWS Account
   * and Region that are implied by the current CLI configuration. */
  // env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: process.env.CDK_DEFAULT_REGION },

  /* Uncomment the next line if you know exactly what Account and Region you
   * want to deploy the stack to. */
  env: seclog,
  seclog_cloudtrail_groupname: m.ssm.cloudtrail_groupname.value,
  cloudtrail_insight_groupname: m.ssm.insight_groupname.value,
  config_groupname: m.ssm.config_groupname.value,
  notification_mail : m.ssm.notification_mail.value,
  seclog_ou : m.ssm.seclog_ou.value,
  guardduty_groupname : m.ssm.guardduty_groupname.value,
  securityhub_groupname : m.ssm.securityhub_groupname.value,
  alarms_groupname : m.ssm.alarms_groupname.value,
  slz_version: m.version,
  seclogid : seclog_accountid,

  /* For more information, see https://docs.aws.amazon.com/cdk/latest/guide/environments.html */
  // tags : tags,
});

const seclogRoleStackSet = new SeclogRoleStackSet(app, 'SECLZ-SeclogRoleStackSet', {
  /* If you don't specify 'env', this stack will be environment-agnostic.
   * Account/Region-dependent features and context lookups will not work,
   * but a single synthesized template can be deployed anywhere. */

  /* Uncomment the next line to specialize this stack for the AWS Account
   * and Region that are implied by the current CLI configuration. */
  // env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: process.env.CDK_DEFAULT_REGION },

  /* Uncomment the next line if you know exactly what Account and Region you
   * want to deploy the stack to. */
  env: seclog,
  accounts : all_accounts,

  /* For more information, see https://docs.aws.amazon.com/cdk/latest/guide/environments.html */
  // tags : tags,
});


const cisControlsUpdateStack = new CisControlsUpdateStack(app, 'SECLZ-CisControlsUpdateStack', {
  /* If you don't specify 'env', this stack will be environment-agnostic.
   * Account/Region-dependent features and context lookups will not work,
   * but a single synthesized template can be deployed anywhere. */

  /* Uncomment the next line to specialize this stack for the AWS Account
   * and Region that are implied by the current CLI configuration. */
  // env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: process.env.CDK_DEFAULT_REGION },

  /* Uncomment the next line if you know exactly what Account and Region you
   * want to deploy the stack to. */
  env: seclog,

  /* For more information, see https://docs.aws.amazon.com/cdk/latest/guide/environments.html */
  // tags : tags,
});




// Get latest version at synth time 
// const CloudtrailLogGroup = ssm.StringParameter.valueFromLookup(this, '/org/member/SecLog_cloudtrail-groupname');
// const CloudtrailInsightLogGroup = ssm.StringParameter.valueFromLookup(this, '/org/member/SecLog_insight-groupname');
// const ConfigLogGroup = ssm.StringParameter.valueFromLookup(this, '/org/member/SecLog_config-groupname');

const lambdaLogShippersStack = new LambdaLogShippersStack(app, 'SECLZ-LambdaLogShippersStack', {
  /* If you don't specify 'env', this stack will be environment-agnostic.
   * Account/Region-dependent features and context lookups will not work,
   * but a single synthesized template can be deployed anywhere. */

  /* Uncomment the next line to specialize this stack for the AWS Account
   * and Region that are implied by the current CLI configuration. */
  // env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: process.env.CDK_DEFAULT_REGION },

  /* Uncomment the next line if you know exactly what Account and Region you
   * want to deploy the stack to. */
  env: seclog,
  // ConfigBucketName: "config-logs-" + seclog_accountid + "-do-not-delete",
  // CloudtrailBucketName: "cloudtrail-logs-" + seclog_accountid + "-do-not-delete",
  ConfigBucketName: "config-bucket-" + seclog_accountid ,
  CloudtrailBucketName: "cloudtrail-bucket-" + seclog_accountid

  /* For more information, see https://docs.aws.amazon.com/cdk/latest/guide/environments.html */
  // tags : tags,
});

