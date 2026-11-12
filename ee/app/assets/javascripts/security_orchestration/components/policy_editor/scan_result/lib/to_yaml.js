import { stringifyPolicyYaml } from 'ee/security_orchestration/policy_yaml';
import { removeIdsFromPolicy } from '../../utils';

/*
 Return yaml representation of a policy.
*/
export const policyToYaml = (policy) => {
  return stringifyPolicyYaml(removeIdsFromPolicy(policy));
};
