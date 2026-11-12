import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import WorkplanQuestionNavigator from 'ee/work_items/components/implementation_widget/workplan_question_navigator.vue';
import { jumpToQuestion } from 'ee/work_items/utils/question_navigation';

jest.mock('ee/work_items/utils/question_navigation');

describe('WorkplanQuestionNavigator', () => {
  let wrapper;

  const { bindInternalEventDocument } = useMockInternalEventsTracking();

  const questions = [
    { noteId: 'gid://gitlab/DiscussionNote/1', answered: false },
    { noteId: 'gid://gitlab/DiscussionNote/2', answered: true },
    { noteId: 'gid://gitlab/DiscussionNote/3', answered: false },
  ];

  const createComponent = ({ surface = 'inline_row' } = {}) => {
    wrapper = shallowMountExtended(WorkplanQuestionNavigator, {
      propsData: { questions, surface },
    });
  };

  const findPreviousButton = () => wrapper.findComponentByTestId('previous-question-button');
  const findNextButton = () => wrapper.findComponentByTestId('next-question-button');

  it.each`
    scenario      | findButton            | label                       | icon                 | direction
    ${'previous'} | ${findPreviousButton} | ${'Previous open question'} | ${'chevron-lg-up'}   | ${'previous'}
    ${'next'}     | ${findNextButton}     | ${'Next open question'}     | ${'chevron-lg-down'} | ${'next'}
  `(
    'jumps between the unanswered questions from the $scenario button',
    ({ findButton, label, icon, direction }) => {
      createComponent();

      expect(findButton().attributes('aria-label')).toBe(label);
      expect(findButton().props('icon')).toBe(icon);

      findButton().vm.$emit('click');

      expect(jumpToQuestion).toHaveBeenCalledWith({
        noteIds: ['gid://gitlab/DiscussionNote/1', 'gid://gitlab/DiscussionNote/3'],
        direction,
      });
    },
  );

  describe('tracking', () => {
    it.each`
      surface            | scenario      | findButton            | label
      ${'inline_row'}    | ${'previous'} | ${findPreviousButton} | ${'previous'}
      ${'inline_row'}    | ${'next'}     | ${findNextButton}     | ${'next'}
      ${'sticky_header'} | ${'previous'} | ${findPreviousButton} | ${'previous'}
      ${'sticky_header'} | ${'next'}     | ${findNextButton}     | ${'next'}
    `(
      'tracks one event when the $scenario button is clicked in the $surface',
      ({ surface, findButton, label }) => {
        createComponent({ surface });
        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

        findButton().vm.$emit('click');

        expect(trackEventSpy).toHaveBeenCalledTimes(1);
        expect(trackEventSpy).toHaveBeenCalledWith(
          'click_work_item_workplan_question_navigation',
          { label, property: surface },
          undefined,
        );
      },
    );
  });
});
