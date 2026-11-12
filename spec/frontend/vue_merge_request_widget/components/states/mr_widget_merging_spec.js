import { shallowMount } from '@vue/test-utils';
import waitForPromises from 'helpers/wait_for_promises';
import simplePoll from '~/lib/utils/simple_poll';
import MrWidgetMerging from '~/vue_merge_request_widget/components/states/mr_widget_merging.vue';
import BoldText from '~/vue_merge_request_widget/components/bold_text.vue';
import { STATUS_MERGED } from '~/issues/constants';
import eventHub from '~/vue_merge_request_widget/event_hub';
import { fetchUserCounts } from '~/super_sidebar/user_counts_fetch';

jest.mock('~/super_sidebar/user_counts_fetch');
jest.mock('~/lib/utils/simple_poll', () =>
  jest.fn().mockImplementation(jest.requireActual('~/lib/utils/simple_poll').default),
);

describe('MRWidgetMerging', () => {
  let wrapper;

  const pollMock = jest.fn().mockResolvedValue();
  const createComponent = () => {
    wrapper = shallowMount(MrWidgetMerging, {
      propsData: {
        mr: {
          targetBranchPath: '/branch-path',
          targetBranch: 'branch',
          transitionStateMachine() {},
        },
        service: {
          poll: pollMock,
        },
      },
    });
  };

  it('renders information about merge request being merged', () => {
    createComponent();

    const message = wrapper.findComponent(BoldText).props('message');
    expect(message).toContain('Merging!');
  });

  describe('initiateMergePolling', () => {
    beforeEach(createComponent);

    it('should call simplePoll', () => {
      expect(simplePoll).toHaveBeenCalledWith(expect.any(Function), { timeout: 0 });
    });

    it('should call handleMergePolling', () => {
      expect(pollMock).toHaveBeenCalled();
    });
  });

  describe('on successful merge', () => {
    const checkStatusCalls = () =>
      eventHub.$emit.mock.calls.filter(([event]) => event === 'mr-widget-check-status').length;

    beforeEach(async () => {
      jest.spyOn(eventHub, '$emit');
      pollMock.mockResolvedValue({ data: { state: STATUS_MERGED } });
      createComponent();

      await waitForPromises();
    });

    it('requests the merge status and re-fetches user counts once', async () => {
      expect(checkStatusCalls()).toBe(1);

      jest.advanceTimersByTime(2000);
      await waitForPromises();

      expect(checkStatusCalls()).toBe(2);
      expect(fetchUserCounts).toHaveBeenCalledTimes(1);
    });

    it('stops polling when the component is destroyed', async () => {
      wrapper.destroy();

      jest.advanceTimersByTime(2000);
      await waitForPromises();

      expect(pollMock).toHaveBeenCalledTimes(1);
    });
  });
});
