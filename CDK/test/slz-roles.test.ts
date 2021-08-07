import { expect as expectCDK, matchTemplate, MatchStyle } from '@aws-cdk/assert';
import * as cdk from '@aws-cdk/core';
import * as SlzRoles from '../lib/SeclogRoleStackSet';


var all_accounts = [] as string[];
const seclog_accountid = '123456789012';
all_accounts.push(seclog_accountid);
const seclog = { account: seclog_accountid, region: 'eu-west-1' };

test('Empty Stack', () => {
    const app = new cdk.App();
    // WHEN
    const stack = new SlzRoles.SeclogRoleStackSet(app, 'SECLZ-SeclogRoleTestStackSet', {
      env: seclog,
      accounts : all_accounts,
    });
    // THEN
    expectCDK(stack).to(matchTemplate({
      "Resources": {}
    }, MatchStyle.EXACT))
});
 