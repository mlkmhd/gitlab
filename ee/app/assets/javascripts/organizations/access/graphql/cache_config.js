export const cacheConfig = {
  typePolicies: {
    Query: {
      fields: {
        artifactRegistryRoleAssignments: {
          keyArgs: ['resourceIds', 'roles', 'assigneeIds'],
          merge: (existing, incoming, { args }) =>
            args?.after && existing
              ? { ...incoming, nodes: [...existing.nodes, ...incoming.nodes] }
              : incoming,
        },
      },
    },
  },
};
