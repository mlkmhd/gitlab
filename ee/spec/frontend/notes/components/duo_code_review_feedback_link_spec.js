import { GlButton } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DuoCodeReviewFeedbackLink from 'ee/notes/components/duo_code_review_feedback_link.vue';

describe('DuoCodeReviewFeedbackLink', () => {
  let wrapper;

  const createComponent = () => {
    wrapper = shallowMountExtended(DuoCodeReviewFeedbackLink);
  };

  const findLink = () => wrapper.findComponent(GlButton);

  beforeEach(() => {
    createComponent();
  });

  it('renders the "Leave feedback" link', () => {
    expect(findLink().text()).toBe('Leave feedback');
  });

  it('links to the feedback issue', () => {
    expect(findLink().attributes('href')).toBe(
      'https://gitlab.com/gitlab-org/gitlab/-/issues/517386',
    );
  });
});
