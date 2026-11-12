import { pinia } from '~/pinia/instance';
import { useFileBrowser } from '~/diffs/stores/file_browser';
import { useCodeReview } from '~/diffs/stores/code_review';
import TreeList from './tree_list.vue';

const stylesheetsRequireCtx = require.context(
  '../../../stylesheets',
  true,
  /(page_bundles\/merge_requests)\.scss$/,
);

stylesheetsRequireCtx('./page_bundles/merge_requests.scss');

const DIFF_FILES = [
  {
    new_path: 'app/models/merge_request.rb',
    old_path: 'app/models/merge_request.rb',
    file_hash: 'merge-request-model',
    added_lines: 12,
    removed_lines: 4,
  },
  {
    new_path: 'app/models/project.rb',
    old_path: 'app/models/project.rb',
    file_hash: 'project-model',
    added_lines: 3,
    removed_lines: 1,
  },
  {
    new_path: 'app/services/merge_service.rb',
    old_path: 'app/services/merge_service.rb',
    file_hash: 'merge-service',
    added_lines: 20,
    new_file: true,
  },
  {
    new_path: 'lib/gitlab/diff/file.rb',
    old_path: 'lib/gitlab/diff/file.rb',
    file_hash: 'diff-file',
    removed_lines: 8,
    deleted_file: true,
  },
  {
    new_path: 'README.md',
    old_path: 'README.md',
    file_hash: 'readme',
    added_lines: 1,
  },
];

export default {
  component: TreeList,
  title: 'diffs/components/tree_list',
  args: {
    hideFileStats: false,
    rowHeight: 32,
    groupBlobsListItems: true,
  },
  argTypes: {
    hideFileStats: { control: 'boolean', description: 'Hide added and removed line counts.' },
    groupBlobsListItems: {
      control: 'boolean',
      description: 'Group files under folder headers in list view.',
    },
    rowHeight: { control: false },
  },
};

const UNSORTED_DIFF_FILES = [
  'app/application.rb',
  'app/models/merge_request.rb',
  'app/routes.rb',
  'app/models/project.rb',
].map((path, index) => ({
  new_path: path,
  old_path: path,
  file_hash: `unsorted-${index}`,
  added_lines: index + 1,
}));

const CONFLICTING_DIFF_FILES = DIFF_FILES.map((file) => {
  if (file.file_hash === 'merge-request-model') return { ...file, conflict_type: 'both_modified' };
  if (file.file_hash === 'merge-service') return { ...file, conflict_type: 'both_added' };
  return file;
});

const ALL_CONFLICT_TYPES = [
  'both_modified',
  'modified_source_removed_target',
  'modified_target_removed_source',
  'renamed_same_file',
  'removed_source_renamed_target',
  'removed_target_renamed_source',
  'both_added',
].map((conflictType) => ({
  new_path: `conflicts/${conflictType}.rb`,
  old_path: `conflicts/${conflictType}.rb`,
  file_hash: conflictType,
  added_lines: 2,
  removed_lines: 1,
  conflict_type: conflictType,
}));

const createStory = ({ diffFiles = DIFF_FILES, renderTreeList = true, sort = true } = {}) => {
  return (args, { argTypes }) => {
    const fileBrowser = useFileBrowser(pinia);
    fileBrowser.$reset();
    fileBrowser.setTreeData(diffFiles, sort);
    fileBrowser.renderTreeList = renderTreeList;
    useCodeReview(pinia).$reset();

    return {
      components: { TreeList },
      props: Object.keys(argTypes),
      pinia,
      template: `
        <div class="gl-h-48 gl-w-62">
          <tree-list v-bind="$props" />
        </div>
      `,
    };
  };
};

export const Default = createStory();

export const ListView = createStory({ renderTreeList: false });

export const UngroupedListView = createStory({
  diffFiles: UNSORTED_DIFF_FILES,
  renderTreeList: false,
  sort: false,
});
UngroupedListView.args = { groupBlobsListItems: false };

export const HiddenFileStats = createStory();
HiddenFileStats.args = { hideFileStats: true };

export const NoFiles = createStory({ diffFiles: [] });

export const Conflicts = createStory({ diffFiles: CONFLICTING_DIFF_FILES });

export const AllConflictTypes = createStory({ diffFiles: ALL_CONFLICT_TYPES });
