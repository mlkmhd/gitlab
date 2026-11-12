import apolloProvider from '~/repository/graphql';
import projectPathQuery from '~/repository/queries/project_path.query.graphql';
import projectShortPathQuery from '~/repository/queries/project_short_path.query.graphql';
import refsQuery from '~/repository/queries/ref.query.graphql';
import { initClientQueries } from '~/repository/utils/init_client_queries';

describe('initClientQueries', () => {
  const values = {
    projectPath: 'group/project',
    projectShortPath: 'project',
    ref: 'feature/#123',
    escapedRef: 'feature/%23123',
  };

  const readCache = (query) => apolloProvider.clients.defaultClient.cache.readQuery({ query });

  afterEach(() => {
    apolloProvider.clients.defaultClient.cache.restore({});
  });

  it('seeds the project path, short path and refs', () => {
    initClientQueries(values);

    expect(readCache(projectPathQuery)).toEqual({ projectPath: 'group/project' });
    expect(readCache(projectShortPathQuery)).toEqual({ projectShortPath: 'project' });
    expect(readCache(refsQuery)).toMatchObject({
      ref: 'feature/#123',
      escapedRef: 'feature/%23123',
    });
  });

  it.each`
    description             | missing                        | query
    ${'project path'}       | ${{ projectPath: '' }}         | ${projectPathQuery}
    ${'project short path'} | ${{ projectShortPath: '' }}    | ${projectShortPathQuery}
    ${'refs'}               | ${{ ref: '', escapedRef: '' }} | ${refsQuery}
  `('skips the $description when it is empty', ({ missing, query }) => {
    initClientQueries({ ...values, ...missing });

    expect(readCache(query)).toBe(null);
  });
});
