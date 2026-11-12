import { join } from 'node:path';
import { loadFixturesMap } from 'ee_jest/integration/core/fixture_utils';

const FIXTURES_PATH = join('tmp/tests/frontend/fixtures-ee/merge_request_notes/integration/');

export const { discussions, discussionsRootDataset } = loadFixturesMap(FIXTURES_PATH);

export const mergeRequestNotesRestEndpoints = [
  {
    name: 'mergeRequestDiscussions',
    method: 'get',
    path: /\/-\/merge_requests\/\d+\/discussions\.json/,
    response: discussions,
  },
];
