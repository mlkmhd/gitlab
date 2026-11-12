import { STAGES } from '../constants';
import StageCard from './stage_card.vue';

const buildStage = {
  name: 'build',
  skipped: false,
  status: 'In dev',
  start: 'automated',
  exit: 'manual',
  flow: 414,
  markMergeRequestsReady: true,
};

export default {
  component: StageCard,
  title: 'ee/ai/duo_agents_platform/pages/software_factory/components/stage_card',
  argTypes: {
    select: { action: 'select' },
  },
};

const Template = (args, { argTypes }) => ({
  components: { StageCard },
  props: Object.keys(argTypes),
  template: '<stage-card v-bind="$props" @select="select" />',
});

export const Default = Template.bind({});
Default.args = {
  stage: buildStage,
  position: 3,
  flowName: 'Developer flow',
  errorCount: 0,
  selected: false,
  warning: '',
};

export const Selected = Template.bind({});
Selected.args = { ...Default.args, selected: true };

export const Skipped = Template.bind({});
Skipped.args = {
  ...Default.args,
  stage: { name: 'verify', skipped: true },
  flowName: '',
};

export const WithErrors = Template.bind({});
WithErrors.args = { ...Default.args, errorCount: 2 };

export const SelectedWithErrors = Template.bind({});
SelectedWithErrors.args = { ...Default.args, selected: true, errorCount: 2 };

export const WithLongFlowName = Template.bind({});
WithLongFlowName.args = {
  ...Default.args,
  flowName: 'an-extremely-long-unbroken-flow-reference-name/v1',
};

export const WithWarning = Template.bind({});
WithWarning.args = {
  ...Default.args,
  warning: 'Will not start until the plan stage exits.',
};

// Shows every label and icon in `STAGE_ICONS` / `STAGE_LABELS` at once.
export const AllStages = (args, { argTypes }) => ({
  components: { StageCard },
  props: Object.keys(argTypes),
  computed: {
    stages() {
      return STAGES.map((name, index) => ({
        stage: { ...buildStage, name, skipped: name === 'verify' },
        position: index + 1,
      }));
    },
  },
  template: `
    <div class="gl-flex gl-flex-wrap gl-gap-4">
      <stage-card
        v-for="{ stage, position } in stages"
        :key="stage.name"
        :stage="stage"
        :position="position"
        flow-name="Developer flow"
        @select="select"
      />
    </div>
  `,
});
