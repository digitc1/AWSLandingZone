#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from '@aws-cdk/core';

// import { SlzSeclogRoles } from '../lib/SlzSeclogRoles';
import { CisControlsUpdateStack } from '../lib/CisControlsUpdateStack';
import { LambdaLogShippersStack } from '../lib/LambdaLogShippersStack';
import { SeclogRoleStackSet } from '../lib/SeclogRoleStackSet';

const app = new cdk.App();

const seclog_accountid = app.node.tryGetContext('seclog_accountid') as string;
const linked_accountids = app.node.tryGetContext('linked_accountids').split(',') as string[];
const seclog = { account: seclog_accountid, region: 'eu-west-1' };

var all_accounts = linked_accountids;
all_accounts.push(seclog['account']);

cdk.Tags.of(app).add("Project", "secLZ");
cdk.Tags.of(app).add("Owner", "DIGIT.C.1");
cdk.Tags.of(app).add("Environment", "prod");
cdk.Tags.of(app).add("Criticity", "high");
cdk.Tags.of(app).add("Confidentiality", "confidential");
cdk.Tags.of(app).add("Organization", "EC");
cdk.Tags.of(app).add("ApplicationRole", "security");



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

// const slzSeclogRoles = new SlzSeclogRoles(app, 'SECLZ-RolesStack', {
//   /* If you don't specify 'env', this stack will be environment-agnostic.
//    * Account/Region-dependent features and context lookups will not work,
//    * but a single synthesized template can be deployed anywhere. */

//   /* Uncomment the next line to specialize this stack for the AWS Account
//    * and Region that are implied by the current CLI configuration. */
//   // env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: process.env.CDK_DEFAULT_REGION },

//   /* Uncomment the next line if you know exactly what Account and Region you
//    * want to deploy the stack to. */
//   env: seclog,

//   /* For more information, see https://docs.aws.amazon.com/cdk/latest/guide/environments.html */
//   // tags : tags,
//   lambdaExecutionRole: cisControlsUpdateStack.lambdaExecutionRole,
// });

// const lambdaLogShippersStack = new LambdaLogShippersStack(app, 'SECLZ-LambdaLogShippersStack', {
//   /* If you don't specify 'env', this stack will be environment-agnostic.
//    * Account/Region-dependent features and context lookups will not work,
//    * but a single synthesized template can be deployed anywhere. */

//   /* Uncomment the next line to specialize this stack for the AWS Account
//    * and Region that are implied by the current CLI configuration. */
//   // env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: process.env.CDK_DEFAULT_REGION },

//   /* Uncomment the next line if you know exactly what Account and Region you
//    * want to deploy the stack to. */
//   env: seclog,
//   ConfigBucketName: 'config-bucket-204743045183',
//   CloudtrailBucketName: 'cloudtrail-bucket-204743045183',
//   CloudtrailLogGroup: '/aws/cloudtrail',
//   CloudtrailInsightLogGroup: '/aws/cloudtrail-insight',
//   ConfigLogGroup: '/aws/config',

//   /* For more information, see https://docs.aws.amazon.com/cdk/latest/guide/environments.html */
//   // tags : tags,
// });
