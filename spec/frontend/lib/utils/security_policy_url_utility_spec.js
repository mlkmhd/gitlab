import { getSecurityPolicyListUrl } from '~/lib/utils/security_policy_url_utility';
import { TEST_HOST } from 'helpers/test_constants';

describe('getSecurityPolicyListUrl', () => {
  it.each`
    namespacePath          | namespaceType | expectedPath
    ${'parent/child'}      | ${undefined}  | ${'/groups/parent/child/-/security/policies'}
    ${'parent/child'}      | ${'group'}    | ${'/groups/parent/child/-/security/policies'}
    ${'parent/repository'} | ${'project'}  | ${'/parent/repository/-/security/policies'}
    ${'test'}              | ${'group'}    | ${'/groups/test/-/security/policies'}
    ${'test'}              | ${'project'}  | ${'/test/-/security/policies'}
    ${''}                  | ${undefined}  | ${'/groups/-/security/policies'}
    ${''}                  | ${'group'}    | ${'/groups/-/security/policies'}
    ${''}                  | ${'project'}  | ${'/-/security/policies'}
    ${undefined}           | ${'group'}    | ${'/groups/-/security/policies'}
    ${undefined}           | ${'project'}  | ${'/-/security/policies'}
    ${null}                | ${'group'}    | ${'/groups/-/security/policies'}
    ${null}                | ${'project'}  | ${'/-/security/policies'}
  `(
    'returns $expectedPath for $namespaceType $namespacePath',
    ({ namespacePath, namespaceType, expectedPath }) => {
      expect(getSecurityPolicyListUrl({ namespacePath, namespaceType })).toBe(
        `${TEST_HOST}${expectedPath}`,
      );
    },
  );
});
