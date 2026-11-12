import { join } from 'node:path';
import { loadFixturesMap } from 'ee_jest/integration/core/fixture_utils';

const FIXTURES_PATH = join('tmp/tests/frontend/fixtures-ee/ref_selector/integration/');

const { branches, tags } = loadFixturesMap(FIXTURES_PATH);

// The shared ref selector searches branches and tags as soon as it mounts, on any page.
export const refSelectorRestEndpoints = [
  {
    method: 'get',
    path: /\/projects\/[^/]+\/repository\/branches/,
    name: 'refSelectorBranches',
    response: branches,
    headers: { 'x-total': String(branches.length) },
  },
  {
    method: 'get',
    path: /\/projects\/[^/]+\/repository\/tags/,
    name: 'refSelectorTags',
    response: tags,
    headers: { 'x-total': String(tags.length) },
  },
];
