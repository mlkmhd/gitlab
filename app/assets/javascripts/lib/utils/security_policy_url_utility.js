import { getBaseURL, joinPaths } from './url_utility';

export const getSecurityPolicyListUrl = ({ namespacePath, namespaceType = 'group' }) => {
  const isGroup = namespaceType === 'group';
  return joinPaths(
    getBaseURL(),
    isGroup ? 'groups' : '',
    namespacePath,
    '-',
    'security',
    'policies',
  );
};
