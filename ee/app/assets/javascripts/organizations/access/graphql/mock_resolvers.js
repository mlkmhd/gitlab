// Local resolvers for the `@client` counts and owners, until
// https://gitlab.com/gitlab-org/gitlab/-/issues/632260 reads the real ones.
import { RESOURCES, RESOURCE_ARTIFACT_REGISTRY } from '../constants';
import { MOCK_ROLE_ASSIGNMENTS } from '../mock_data';

export const createMockResolvers = (assignments = MOCK_ROLE_ASSIGNMENTS) => ({
  Query: {
    artifactRegistryRoleAssignmentCounts: () => ({
      __typename: 'ArtifactRegistryRoleAssignmentCounts',
      total: assignments.length,
      capped: false,
      byRole: RESOURCES[RESOURCE_ARTIFACT_REGISTRY].roles.map(({ value }) => ({
        __typename: 'ArtifactRegistryRoleCount',
        role: value,
        count: assignments.filter(({ role }) => role === value).length,
      })),
    }),
    artifactRegistryRoleAssignments: (_, { roles = [], first }) => {
      const matching = assignments.filter(({ role }) => !roles.length || roles.includes(role));
      const nodes = first == null ? matching : matching.slice(0, first);

      return {
        __typename: 'ArtifactRegistryRoleAssignmentConnection',
        nodes,
        pageInfo: {
          __typename: 'PageInfo',
          hasNextPage: nodes.length < matching.length,
          hasPreviousPage: false,
          startCursor: null,
          endCursor: null,
        },
      };
    },
  },
});

export const mockResolvers = createMockResolvers();
