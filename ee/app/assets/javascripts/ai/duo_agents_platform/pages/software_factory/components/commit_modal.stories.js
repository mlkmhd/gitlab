import CommitModal from './commit_modal.vue';

export default {
  component: CommitModal,
  title: 'ee/ai/duo_agents_platform/pages/software_factory/components/commit_modal',
  argTypes: {
    submit: { action: 'submit' },
  },
};

const Template = (args, { argTypes }) => ({
  components: { CommitModal },
  props: Object.keys(argTypes),
  data() {
    return { isVisible: args.visible };
  },
  template: `
    <div>
      <button @click="isVisible = true">Open commit modal</button>
      <commit-modal
        v-bind="$props"
        :visible="isVisible"
        @submit="submit"
        @hide="isVisible = false"
      />
    </div>
  `,
});

export const CommitToDefaultBranch = Template.bind({});
CommitToDefaultBranch.args = {
  visible: true,
  defaultBranch: 'main',
  openMergeRequest: false,
  errorCount: 0,
};

export const OpenMergeRequest = Template.bind({});
OpenMergeRequest.args = { ...CommitToDefaultBranch.args, openMergeRequest: true };

export const WithConfigurationErrors = Template.bind({});
WithConfigurationErrors.args = { ...CommitToDefaultBranch.args, errorCount: 2 };
