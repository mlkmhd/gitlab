import DashboardsListNameCell from './dashboards_list_name_cell.vue';

export default {
  component: DashboardsListNameCell,
  title: 'explore/analytics_dashboards/components/dashboards_list/dashboards_list_name_cell',
};

const Template = (args, { argTypes }) => ({
  components: { DashboardsListNameCell },
  props: Object.keys(argTypes),
  template: `<dashboards-list-name-cell v-bind="$props" />`,
});

export const Default = Template.bind({});
Default.args = {
  name: 'Built in dashboard',
  description: 'Built in dashboard',
  dashboardUrl: '/fake/link/to/share',
};

export const WithStatus = Template.bind({});
WithStatus.args = {
  ...Default.args,
  status: 'beta',
  system: true,
};
WithStatus.argTypes = {
  status: { control: 'select', options: ['beta', 'experiment'] },
};
