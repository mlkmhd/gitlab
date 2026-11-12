import { STATUS_CATEGORIES } from 'ee/work_items/constants';
import CreateStatusModal from './create_status_modal.vue';

const lifecycles = [
  { id: 'gid://gitlab/Lifecycle/1', name: 'Default' },
  { id: 'gid://gitlab/Lifecycle/2', name: 'Engineering' },
];

export default {
  component: CreateStatusModal,
  title: 'ee/ai/duo_agents_platform/pages/software_factory/components/create_status_modal',
  argTypes: {
    submit: { action: 'submit' },
  },
};

const Template = (args, { argTypes }) => ({
  components: { CreateStatusModal },
  props: Object.keys(argTypes),
  data() {
    return { isVisible: args.visible };
  },
  template: `
    <div>
      <button @click="isVisible = true">Open create status modal</button>
      <create-status-modal
        v-bind="$props"
        :visible="isVisible"
        @submit="submit"
        @hide="isVisible = false"
      />
    </div>
  `,
});

export const Default = Template.bind({});
Default.args = {
  visible: true,
  groupName: 'Flight',
  initialName: 'Verification',
  initialCategory: STATUS_CATEGORIES.IN_PROGRESS,
  lifecycles: [lifecycles[0]],
  initialLifecycleId: lifecycles[0].id,
  existingNames: ['To do', 'Done'],
  usesDefaultStatuses: false,
  isSaving: false,
  error: '',
};

// The lifecycle picker only appears when the group has more than one.
export const MultipleLifecycles = Template.bind({});
MultipleLifecycles.args = { ...Default.args, lifecycles };

export const UsesDefaultStatuses = Template.bind({});
UsesDefaultStatuses.args = { ...Default.args, usesDefaultStatuses: true };

export const DuplicateName = Template.bind({});
DuplicateName.args = { ...Default.args, initialName: 'done' };

export const Saving = Template.bind({});
Saving.args = { ...Default.args, isSaving: true };

export const WithServerError = Template.bind({});
WithServerError.args = { ...Default.args, error: 'Name has already been taken' };
