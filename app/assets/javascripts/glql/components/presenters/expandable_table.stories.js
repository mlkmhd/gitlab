import ExpandableTablePresenter from './expandable_table.vue';
import { withBreakdown } from './utils/expandable_table';

const mockGroup = (id, path, fullName) => ({
  __typename: 'Group',
  id: `gid://gitlab/Group/${id}`,
  fullName,
  webUrl: `https://gitlab.example.com/${path}`,
});
const mockProject = (id, path, name) => ({
  __typename: 'Project',
  id: `gid://gitlab/Project/${id}`,
  name,
  nameWithNamespace: path,
  webPath: `/${path}`,
});

const PLATFORM = mockGroup(1, 'example-org/platform', 'Example Org / Platform');
const MOBILE = mockGroup(2, 'example-org/mobile', 'Example Org / Mobile');
const API = mockProject(1, 'example-org/platform/api', 'api');
const WEB_APP = mockProject(2, 'example-org/platform/web-app', 'web-app');
const IOS = mockProject(3, 'example-org/mobile/ios', 'ios');
const DOCS = mockProject(4, 'example-org/platform/docs', 'docs');
const TOOLS = mockProject(5, 'example-org/tools', 'tools');

// Keys as the compiler emits them for `dimensions: group(depth=2) as "Group"` with
// `expandRowsBy: project`: the alias keys the group, and `project` keeps its own name.
const GROUP_FIELD = {
  key: 'Group',
  label: 'Group',
  field: 'group',
  name: 'group_depth_2',
  type: 'dimension',
  parameters: { depth: '2' },
};
const PROJECT_FIELD = { key: 'project', label: 'Project', name: 'project', type: 'dimension' };
const METRIC_FIELDS = [
  { key: 'creditsUsedSum', label: 'Credits', name: 'creditsUsedSum', type: 'metric' },
  { key: 'usersCount', label: 'Users', name: 'usersCount', type: 'metric' },
];
const FIELDS = [GROUP_FIELD, ...METRIC_FIELDS];

// Users are counted once per row, so a group's users are not the sum of its projects'.
const DATA = {
  nodes: [
    { Group: PLATFORM, usersCount: 21, creditsUsedSum: 613.25 },
    { Group: MOBILE, usersCount: 7, creditsUsedSum: 96 },
    { Group: null, usersCount: 2, creditsUsedSum: 8 },
  ],
};
const BREAKDOWN_DATA = {
  count: 5,
  fields: [GROUP_FIELD, PROJECT_FIELD, ...METRIC_FIELDS],
  nodes: [
    { Group: PLATFORM, project: API, usersCount: 18, creditsUsedSum: 412.5 },
    { Group: PLATFORM, project: WEB_APP, usersCount: 9, creditsUsedSum: 188.25 },
    { Group: PLATFORM, project: DOCS, usersCount: 3, creditsUsedSum: 12.5 },
    { Group: MOBILE, project: IOS, usersCount: 7, creditsUsedSum: 96 },
    { Group: null, project: TOOLS, usersCount: 2, creditsUsedSum: 8 },
  ],
};

// DataPresenter joins the breakdown in before the table renders it.
const JOINED = withBreakdown({ fields: FIELDS, data: DATA, breakdownData: BREAKDOWN_DATA });
const UNLOADED = withBreakdown({ fields: FIELDS, data: DATA, breakdownData: null });

export default {
  component: ExpandableTablePresenter,
  title: 'glql/components/presenters/expandable_table',
  argTypes: {
    data: {
      control: false,
      description: 'Query result, as `{ nodes: [] }`, each row carrying its children.',
    },
    fields: { control: false, description: 'Fields the query selected, one column each.' },
    source: {
      control: 'text',
      description: 'Query data source. Decides how a null group or project reads.',
    },
    childDimension: {
      control: false,
      description: 'The dimension child rows show in the first column, null until they load.',
    },
    childrenLoading: { control: 'boolean', description: 'Whether the child rows are loading.' },
    childrenError: { control: 'boolean', description: 'Whether the child rows failed to load.' },
  },
};

const Template = (args, { argTypes }) => ({
  components: { ExpandableTablePresenter },
  props: Object.keys(argTypes),
  template: `<expandable-table-presenter
    :data="data"
    :fields="fields"
    :source="source"
    :child-dimension="childDimension"
    :children-loading="childrenLoading"
    :children-error="childrenError"
  />`,
});

// `expandRowsBy` nests a row per project under each group, aligned with the group's columns.
// The children arrive from a second query, so each group's own total stays exact.
export const Default = Template.bind({});
Default.args = {
  data: JOINED.data,
  fields: FIELDS,
  source: 'DuoWorkflows',
  childDimension: JOINED.dimension,
  childrenLoading: false,
  childrenError: false,
};

// Expand a row to see the skeleton that holds its place while the child query runs.
export const Loading = Template.bind({});
Loading.args = {
  ...Default.args,
  data: UNLOADED.data,
  childDimension: null,
  childrenLoading: true,
};
