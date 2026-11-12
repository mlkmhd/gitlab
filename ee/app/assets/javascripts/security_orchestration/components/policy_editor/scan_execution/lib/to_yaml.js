import { stringifyPolicyYaml } from 'ee/security_orchestration/policy_yaml';

export const toYaml = (yaml) => {
  return stringifyPolicyYaml(yaml);
};
