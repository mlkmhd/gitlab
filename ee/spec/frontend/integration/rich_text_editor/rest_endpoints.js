import { join } from 'node:path';
import { loadFixturesMap } from 'ee_jest/integration/core/fixture_utils';
import uploadFileVariants from './fixture_variants/upload_file';

const FIXTURES_PATH = join('tmp/tests/frontend/fixtures-ee/rich_text_editor/integration/');

const {
  autocompleteMembers,
  autocompleteLabels,
  autocompleteMilestones,
  autocompleteIssues,
  autocompleteMergeRequests,
  autocompleteCommands,
  autocompleteWikis,
} = loadFixturesMap(FIXTURES_PATH);

export const richTextEditorRestEndpoints = [
  {
    name: 'autocompleteMembers',
    method: 'get',
    path: /\/-\/autocomplete_sources\/members/,
    response: autocompleteMembers,
  },
  {
    name: 'autocompleteLabels',
    method: 'get',
    path: /\/-\/autocomplete_sources\/labels/,
    response: autocompleteLabels,
  },
  {
    name: 'autocompleteMilestones',
    method: 'get',
    path: /\/-\/autocomplete_sources\/milestones/,
    response: autocompleteMilestones,
  },
  {
    name: 'autocompleteIssues',
    method: 'get',
    path: /\/-\/autocomplete_sources\/issues/,
    response: autocompleteIssues,
  },
  {
    name: 'autocompleteMergeRequests',
    method: 'get',
    path: /\/-\/autocomplete_sources\/merge_requests/,
    response: autocompleteMergeRequests,
  },
  {
    name: 'autocompleteCommands',
    method: 'get',
    path: /\/-\/autocomplete_sources\/commands/,
    response: autocompleteCommands,
  },
  {
    name: 'autocompleteWikis',
    method: 'get',
    path: /\/-\/autocomplete_sources\/wikis/,
    response: autocompleteWikis,
  },
  {
    name: 'uploadFile',
    method: 'post',
    path: /\/uploads$/,
    variants: uploadFileVariants,
  },
];
