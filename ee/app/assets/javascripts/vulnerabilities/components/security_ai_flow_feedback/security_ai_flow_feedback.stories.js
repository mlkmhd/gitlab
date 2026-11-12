import { nextTick } from 'vue';
import { GlFormCheckbox } from '@gitlab/ui';
import createMockApollo from 'helpers/mock_apollo_helper';
import securityAiFlowFeedbackCreateMutation from './graphql/security_ai_flow_feedback_create.mutation.graphql';
import { SAST_FP_REASONS } from './constants';
import SecurityAiFlowFeedback from './security_ai_flow_feedback.vue';

export default {
  component: SecurityAiFlowFeedback,
  title: 'ee/vulnerabilities/components/security_ai_flow_feedback/security_ai_flow_feedback',
  parameters: {
    docs: {
      description: {
        component:
          'Asks whether an AI security flow assessment is correct. Yes submits right away. No shows optional reasons, then Submit feedback and Cancel. Responses are mocked and resolve after one second.',
      },
    },
  },
};

const SAVE_DELAY_MS = 1000;

const payload = (errors) => ({
  data: {
    securityAiFlowFeedbackCreate: { __typename: 'SecurityAiFlowFeedbackCreatePayload', errors },
  },
});

const delayed = (settle) => () =>
  new Promise((resolve, reject) => {
    setTimeout(() => settle(resolve, reject), SAVE_DELAY_MS);
  });

const successHandler = delayed((resolve) => resolve(payload([])));
const errorHandler = delayed((resolve) =>
  resolve(payload(['You have submitted feedback too many times. Please try again later.'])),
);
const rejectedHandler = delayed((_, reject) => reject(new Error('Network error')));
const pendingHandler = () => new Promise(() => {});

const clickByTestId = (canvasElement, testId) =>
  canvasElement.querySelector(`[data-testid="${testId}"]`).click();
const clickYes = ({ canvasElement }) =>
  clickByTestId(canvasElement, 'security-ai-flow-feedback-agree-button');
const clickNo = ({ canvasElement }) =>
  clickByTestId(canvasElement, 'security-ai-flow-feedback-disagree-button');

const createStory = ({ handler = successHandler, slot = '', args = {}, play } = {}) => {
  const Story = (_, { argTypes }) => ({
    components: { SecurityAiFlowFeedback, GlFormCheckbox },
    apolloProvider: createMockApollo([[securityAiFlowFeedbackCreateMutation, handler]]),
    props: Object.keys(argTypes),
    template: `
      <security-ai-flow-feedback v-bind="$props">
        ${slot}
      </security-ai-flow-feedback>
    `,
  });
  Story.args = { vulnerabilityId: 1, reasons: SAST_FP_REASONS, ...args };
  Story.play = play;
  return Story;
};

export const Default = createStory();

export const Disagreeing = createStory({ play: clickNo });

export const DisagreeingWithoutReasons = createStory({ args: { reasons: [] }, play: clickNo });

export const WithDisagreeExtra = createStory({
  slot: `
    <template #disagree-extra="{ disabled }">
      <gl-form-checkbox checked :disabled="disabled">Remove the false positive flag</gl-form-checkbox>
    </template>
  `,
  play: clickNo,
});

export const Submitted = createStory({ play: clickYes });

export const SavingNeverCompletes = createStory({ handler: pendingHandler, play: clickYes });

export const SaveFails = createStory({
  handler: errorHandler,
  play: async ({ canvasElement }) => {
    clickNo({ canvasElement });
    await nextTick();
    clickByTestId(canvasElement, 'security-ai-flow-feedback-submit-button');
  },
});

export const NetworkFailure = createStory({ handler: rejectedHandler, play: clickYes });
