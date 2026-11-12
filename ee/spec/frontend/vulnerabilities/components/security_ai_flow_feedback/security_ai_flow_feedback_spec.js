import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlAlert, GlIcon } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import { createControlledMockApollo } from 'helpers/mock_apollo_helper';
import { assertProps } from 'helpers/assert_props';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import SecurityAiFlowFeedback from 'ee/vulnerabilities/components/security_ai_flow_feedback/security_ai_flow_feedback.vue';
import securityAiFlowFeedbackCreateMutation from 'ee/vulnerabilities/components/security_ai_flow_feedback/graphql/security_ai_flow_feedback_create.mutation.graphql';

// Lets the specs check which errors are reported.
jest.mock('~/sentry/sentry_browser_wrapper');

Vue.use(VueApollo);

describe('SecurityAiFlowFeedback', () => {
  let wrapper;
  let mutationHandler;
  let resolveMutation;
  let rejectMutation;

  const vulnerabilityId = 1;
  const reasons = [
    { value: 'VERDICT_WRONG', text: 'Verdict is wrong' },
    { value: 'IGNORED_DATA_FLOW', text: 'Missed data flow' },
    { value: 'OTHER', text: 'Other' },
  ];

  const successResponse = {
    data: {
      securityAiFlowFeedbackCreate: {
        __typename: 'SecurityAiFlowFeedbackCreatePayload',
        errors: [],
      },
    },
  };
  const errorsResponse = {
    data: {
      securityAiFlowFeedbackCreate: {
        __typename: 'SecurityAiFlowFeedbackCreatePayload',
        errors: ['No AI assessment is available for this vulnerability'],
      },
    },
  };
  const notAvailableMessage =
    "The resource that you are attempting to access does not exist or you don't have permission to perform this action";
  const topLevelErrorsResponse = { errors: [{ message: notAvailableMessage }] };
  const networkError = new Error('Network error');
  const genericErrorText = "Feedback couldn't be saved. Try again.";

  const createComponent = ({ props = {}, slots = {} } = {}) => {
    mutationHandler = jest.fn().mockResolvedValue(successResponse);
    const mockApollo = createControlledMockApollo([
      [securityAiFlowFeedbackCreateMutation, mutationHandler],
    ]);
    ({ resolveMutation, rejectMutation } = mockApollo);

    wrapper = mountExtended(SecurityAiFlowFeedback, {
      apolloProvider: mockApollo.apolloProvider,
      propsData: { vulnerabilityId, reasons, ...props },
      scopedSlots: slots,
      attachTo: document.body,
    });
  };

  const findForm = () => wrapper.findByTestId('security-ai-flow-feedback-form');
  const findQuestionFieldset = () => findForm().find('fieldset');
  const findAgreeButton = () =>
    wrapper.findComponentByTestId('security-ai-flow-feedback-agree-button');
  const findDisagreeButton = () =>
    wrapper.findComponentByTestId('security-ai-flow-feedback-disagree-button');
  const findDisagreeSection = () =>
    wrapper.findByTestId('security-ai-flow-feedback-disagree-section');
  const findReasonsFieldset = () => wrapper.findByTestId('security-ai-flow-feedback-reasons');
  const findReason = (value) =>
    wrapper.findComponentByTestId(`security-ai-flow-feedback-reason-${value}`);
  const findSubmitButton = () =>
    wrapper.findComponentByTestId('security-ai-flow-feedback-submit-button');
  const findCancelButton = () =>
    wrapper.findComponentByTestId('security-ai-flow-feedback-cancel-button');
  const findSubmittedMessage = () =>
    wrapper.findByTestId('security-ai-flow-feedback-submitted-message');
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findSlotContent = () => wrapper.findByTestId('disagree-extra-content');

  const click = async (button) => {
    button.trigger('click');
    await nextTick();
  };

  // The mutation stays pending until the spec resolves or rejects it.
  const clickAgree = async () => {
    findAgreeButton().trigger('click');
    await waitForPromises();
  };

  const submitForm = async () => {
    findForm().trigger('submit');
    await waitForPromises();
  };

  const saveSucceeds = () => resolveMutation(securityAiFlowFeedbackCreateMutation);

  const expectMutationCalledWith = (sentiment, selectedReasons) => {
    expect(mutationHandler).toHaveBeenCalledWith({
      input: {
        vulnerabilityId: 'gid://gitlab/Vulnerability/1',
        sentiment,
        reasons: selectedReasons,
      },
    });
  };

  describe('initial state', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the default question as the legend of a fieldset', () => {
      expect(findQuestionFieldset().find('legend').text()).toBe('Is this assessment correct?');
    });

    it('renders Yes and No buttons with icons', () => {
      expect(findAgreeButton().text()).toBe('Yes');
      expect(findAgreeButton().props('icon')).toBe('thumb-up');
      expect(findDisagreeButton().text()).toBe('No');
      expect(findDisagreeButton().props('icon')).toBe('thumb-down');
    });

    it('renders Yes as an action button, not a toggle', () => {
      expect(findAgreeButton().attributes('aria-pressed')).toBeUndefined();
      expect(findAgreeButton().attributes('aria-expanded')).toBeUndefined();
    });

    it('renders No as a collapsed disclosure button', () => {
      expect(findDisagreeButton().attributes('aria-expanded')).toBe('false');
      expect(findDisagreeButton().attributes('aria-controls')).toMatch(
        /^security-ai-flow-feedback-disagree-/,
      );
    });

    it('does not render the reasons or the submit button', () => {
      expect(findDisagreeSection().exists()).toBe(false);
      expect(findSubmitButton().exists()).toBe(false);
    });

    it('does not call the mutation', () => {
      expect(mutationHandler).not.toHaveBeenCalled();
    });
  });

  describe('with a custom question', () => {
    beforeEach(() => {
      createComponent({ props: { question: 'Was this fix helpful?' } });
    });

    it('renders the question as the legend', () => {
      expect(findQuestionFieldset().find('legend').text()).toBe('Was this fix helpful?');
    });
  });

  describe('reasons prop validator', () => {
    it('accepts reasons with a value and text', () => {
      expect(() => assertProps(SecurityAiFlowFeedback, { vulnerabilityId, reasons })).not.toThrow();
    });

    it('rejects reasons without text', () => {
      expect(() =>
        assertProps(SecurityAiFlowFeedback, { vulnerabilityId, reasons: [{ value: 'OTHER' }] }),
      ).toThrow('Invalid prop');
    });
  });

  describe('when the user agrees', () => {
    beforeEach(async () => {
      createComponent();
      await clickAgree();
    });

    describe('while saving', () => {
      it('marks Yes as selected and loading', () => {
        expect(findAgreeButton().props('selected')).toBe(true);
        expect(findAgreeButton().props('loading')).toBe(true);
      });

      it('disables Yes and No', () => {
        expect(findAgreeButton().props('disabled')).toBe(true);
        expect(findDisagreeButton().props('disabled')).toBe(true);
      });
    });

    describe('when saved', () => {
      beforeEach(async () => {
        await saveSucceeds();
      });

      it('submits the global ID with the agree sentiment and no reasons', () => {
        expectMutationCalledWith('AGREE', []);
      });

      it('shows the thanks message', () => {
        expect(findSubmittedMessage().text()).toBe('Thanks for your feedback.');
        expect(findForm().exists()).toBe(false);
      });

      it('emits the submitted event with the feedback', () => {
        expect(wrapper.emitted('submitted')).toEqual([[{ sentiment: 'AGREE', reasons: [] }]]);
      });

      it('moves focus to the thanks message', () => {
        expect(document.activeElement).toBe(findSubmittedMessage().element);
      });
    });
  });

  describe('when the user disagrees', () => {
    beforeEach(async () => {
      createComponent();
      await click(findDisagreeButton());
    });

    it('expands No and points it at the disagree section', () => {
      expect(findDisagreeButton().attributes('aria-expanded')).toBe('true');
      expect(findDisagreeButton().attributes('aria-controls')).toBe(
        findDisagreeSection().attributes('id'),
      );
      expect(findDisagreeButton().props('selected')).toBe(true);
      expect(findAgreeButton().props('selected')).toBe(false);
    });

    it('does not call the mutation yet', () => {
      expect(mutationHandler).not.toHaveBeenCalled();
    });

    it('renders the reasons as unpressed toggle chips in a fieldset', () => {
      expect(findReasonsFieldset().find('legend').text()).toBe("What's wrong? (optional)");
      expect(reasons.map(({ value }) => findReason(value).text())).toEqual([
        'Verdict is wrong',
        'Missed data flow',
        'Other',
      ]);
      reasons.forEach(({ value }) => {
        expect(findReason(value).attributes('aria-pressed')).toBe('false');
        expect(findReason(value).findComponent(GlIcon).exists()).toBe(false);
      });
    });

    it('renders the Submit feedback button', () => {
      expect(findSubmitButton().text()).toBe('Submit feedback');
    });

    it('moves focus to the first reason', () => {
      expect(document.activeElement).toBe(findReason('VERDICT_WRONG').element);
    });

    describe('when a reason is clicked', () => {
      beforeEach(async () => {
        await click(findReason('OTHER'));
      });

      it('marks the reason as pressed with a check icon', () => {
        expect(findReason('OTHER').attributes('aria-pressed')).toBe('true');
        expect(findReason('OTHER').props('selected')).toBe(true);
        expect(findReason('OTHER').findComponent(GlIcon).props('name')).toBe('check');
      });

      describe('when it is clicked again', () => {
        beforeEach(async () => {
          await click(findReason('OTHER'));
        });

        it('unmarks the reason', () => {
          expect(findReason('OTHER').attributes('aria-pressed')).toBe('false');
        });
      });
    });

    describe('when No is clicked again', () => {
      beforeEach(async () => {
        await click(findReason('OTHER'));
        await click(findDisagreeButton());
      });

      it('collapses the form and clears the selection', () => {
        expect(findDisagreeSection().exists()).toBe(false);
        expect(findDisagreeButton().attributes('aria-expanded')).toBe('false');
        expect(findDisagreeButton().props('selected')).toBe(false);
        expect(mutationHandler).not.toHaveBeenCalled();
      });

      it('keeps focus on the No button', () => {
        expect(document.activeElement).toBe(findDisagreeButton().element);
      });
    });

    describe('when the form is submitted without reasons', () => {
      beforeEach(async () => {
        await submitForm();
        await saveSucceeds();
      });

      it('sends the disagree sentiment with no reasons', () => {
        expectMutationCalledWith('DISAGREE', []);
      });

      it('shows the thanks message', () => {
        expect(findSubmittedMessage().text()).toBe('Thanks for your feedback.');
      });
    });

    describe('when reasons are selected in a different order than shown', () => {
      beforeEach(async () => {
        await click(findReason('OTHER'));
        await click(findReason('VERDICT_WRONG'));
        await submitForm();
      });

      describe('while saving', () => {
        it('shows Submit as loading and disables the other controls', () => {
          expect(findSubmitButton().props('loading')).toBe(true);
          expect(findCancelButton().props('disabled')).toBe(true);
          expect(findReason('OTHER').props('disabled')).toBe(true);
        });
      });

      describe('when saved', () => {
        beforeEach(async () => {
          await saveSucceeds();
        });

        it('sends the reasons in display order', () => {
          expectMutationCalledWith('DISAGREE', ['VERDICT_WRONG', 'OTHER']);
        });

        it('shows the same thanks message as without reasons', () => {
          expect(findSubmittedMessage().text()).toBe('Thanks for your feedback.');
        });

        it('emits the submitted event with the feedback', () => {
          expect(wrapper.emitted('submitted')).toEqual([
            [{ sentiment: 'DISAGREE', reasons: ['VERDICT_WRONG', 'OTHER'] }],
          ]);
        });

        it('moves focus to the thanks message', () => {
          expect(document.activeElement).toBe(findSubmittedMessage().element);
        });
      });
    });

    describe('when the user cancels', () => {
      beforeEach(async () => {
        await click(findReason('OTHER'));
        await click(findCancelButton());
      });

      it('closes the form and clears the selection', () => {
        expect(findDisagreeSection().exists()).toBe(false);
        expect(findDisagreeButton().attributes('aria-expanded')).toBe('false');
        expect(mutationHandler).not.toHaveBeenCalled();
      });

      it('moves focus to the No button', () => {
        expect(document.activeElement).toBe(findDisagreeButton().element);
      });

      describe('when the form is re-opened', () => {
        beforeEach(async () => {
          await click(findDisagreeButton());
        });

        it('does not keep the previous reasons', () => {
          expect(findReason('OTHER').attributes('aria-pressed')).toBe('false');
        });
      });
    });

    describe('when the user switches to Yes', () => {
      beforeEach(async () => {
        await click(findReason('OTHER'));
        await clickAgree();
      });

      it('submits the agree sentiment without reasons', () => {
        expectMutationCalledWith('AGREE', []);
      });
    });
  });

  describe('without reasons', () => {
    beforeEach(async () => {
      createComponent({ props: { reasons: [] } });
      await click(findDisagreeButton());
    });

    it('does not render the reasons fieldset', () => {
      expect(findReasonsFieldset().exists()).toBe(false);
      expect(findSubmitButton().exists()).toBe(true);
    });

    it('moves focus to the Submit button', () => {
      expect(document.activeElement).toBe(findSubmitButton().element);
    });
  });

  describe('disagree-extra slot', () => {
    beforeEach(() => {
      createComponent({
        slots: {
          'disagree-extra':
            '<input type="checkbox" data-testid="disagree-extra-content" :disabled="props.disabled" />',
        },
      });
    });

    it('is not rendered before the user disagrees', () => {
      expect(findSlotContent().exists()).toBe(false);
    });

    describe('when the user disagrees', () => {
      beforeEach(async () => {
        await click(findDisagreeButton());
      });

      it('is rendered, enabled, inside the disagree section', () => {
        expect(findDisagreeSection().find('[data-testid="disagree-extra-content"]').exists()).toBe(
          true,
        );
        expect(findSlotContent().element.disabled).toBe(false);
      });

      describe('while saving', () => {
        beforeEach(async () => {
          await submitForm();
        });

        it('receives disabled as a slot prop', () => {
          expect(findSlotContent().element.disabled).toBe(true);
        });
      });
    });
  });

  describe('when the mutation fails', () => {
    describe.each`
      description                        | fail                                                                                   | alertText                                                 | reportedErrors
      ${'with a network error'}          | ${() => rejectMutation(securityAiFlowFeedbackCreateMutation, networkError)}            | ${genericErrorText}                                       | ${[[networkError]]}
      ${'with top-level GraphQL errors'} | ${() => resolveMutation(securityAiFlowFeedbackCreateMutation, topLevelErrorsResponse)} | ${genericErrorText}                                       | ${[[expect.objectContaining({ message: notAvailableMessage })]]}
      ${'with errors in the payload'}    | ${() => resolveMutation(securityAiFlowFeedbackCreateMutation, errorsResponse)}         | ${'No AI assessment is available for this vulnerability'} | ${[]}
    `('$description', ({ fail, alertText, reportedErrors }) => {
      describe('after agreeing', () => {
        beforeEach(async () => {
          createComponent();
          await clickAgree();
          await fail();
        });

        it('shows an inline danger alert', () => {
          expect(findAlert().props('variant')).toBe('danger');
          expect(findAlert().text()).toBe(alertText);
        });

        it('keeps Yes selected and moves focus to it', () => {
          expect(findAgreeButton().props('selected')).toBe(true);
          expect(findAgreeButton().props('loading')).toBe(false);
          expect(document.activeElement).toBe(findAgreeButton().element);
        });

        it('reports only unexpected errors to Sentry', () => {
          expect(Sentry.captureException.mock.calls).toEqual(reportedErrors);
        });

        it('does not emit the submitted event', () => {
          expect(wrapper.emitted('submitted')).toBeUndefined();
        });

        describe('when the user clicks No', () => {
          beforeEach(async () => {
            await click(findDisagreeButton());
          });

          it('hides the alert', () => {
            expect(findAlert().exists()).toBe(false);
          });
        });

        describe('when the user retries Yes successfully', () => {
          beforeEach(async () => {
            await clickAgree();
            await saveSucceeds();
          });

          it('hides the alert and shows the thanks message', () => {
            expect(findAlert().exists()).toBe(false);
            expect(findSubmittedMessage().text()).toBe('Thanks for your feedback.');
          });
        });
      });

      describe('after switching to Yes with the form open', () => {
        beforeEach(async () => {
          createComponent();
          await click(findDisagreeButton());
          await clickAgree();
          await fail();
        });

        it('shows an inline danger alert with the form closed', () => {
          expect(findAlert().text()).toBe(alertText);
          expect(findDisagreeSection().exists()).toBe(false);
          expect(findSubmitButton().exists()).toBe(false);
        });

        it('moves focus to Yes', () => {
          expect(document.activeElement).toBe(findAgreeButton().element);
        });
      });

      describe('after disagreeing', () => {
        beforeEach(async () => {
          createComponent();
          await click(findDisagreeButton());
          await click(findReason('IGNORED_DATA_FLOW'));
          await submitForm();
          await fail();
        });

        it('shows an inline danger alert', () => {
          expect(findAlert().text()).toBe(alertText);
        });

        it('keeps the form open with the selection', () => {
          expect(findDisagreeButton().attributes('aria-expanded')).toBe('true');
          expect(findReason('IGNORED_DATA_FLOW').attributes('aria-pressed')).toBe('true');
          expect(findSubmitButton().props('loading')).toBe(false);
        });

        it('moves focus to the Submit button', () => {
          expect(document.activeElement).toBe(findSubmitButton().element);
        });

        describe('when the user retries successfully', () => {
          beforeEach(async () => {
            await submitForm();
            await saveSucceeds();
          });

          it('hides the alert and shows the thanks message', () => {
            expect(findAlert().exists()).toBe(false);
            expect(findSubmittedMessage().text()).toBe('Thanks for your feedback.');
          });
        });

        describe('when the user cancels', () => {
          beforeEach(async () => {
            await click(findCancelButton());
          });

          it('hides the alert', () => {
            expect(findAlert().exists()).toBe(false);
          });
        });
      });
    });
  });
});
