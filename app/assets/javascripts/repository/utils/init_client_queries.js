import apolloProvider from '../graphql';
import projectPathQuery from '../queries/project_path.query.graphql';
import projectShortPathQuery from '../queries/project_short_path.query.graphql';
import refsQuery from '../queries/ref.query.graphql';

// Seeds the client-only queries the breadcrumbs read, before the app mounts.
export const initClientQueries = ({ projectPath, projectShortPath, ref, escapedRef }) => {
  const { cache } = apolloProvider.clients.defaultClient;

  if (projectPath) cache.writeQuery({ query: projectPathQuery, data: { projectPath } });

  if (projectShortPath) {
    cache.writeQuery({ query: projectShortPathQuery, data: { projectShortPath } });
  }

  if (ref || escapedRef) cache.writeQuery({ query: refsQuery, data: { ref, escapedRef } });
};
