import { GlIcon } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import WorkItemCardAiSessionStatus from 'ee/work_items/board/components/work_item_card_ai_session_status.vue';

describe('WorkItemCardAiSessionStatus', () => {
  let wrapper;

  const createComponent = (session) => {
    wrapper = mountExtended(WorkItemCardAiSessionStatus, {
      propsData: { session },
    });
  };

  const findIcon = () => wrapper.findComponent(GlIcon);

  it.each`
    status              | icon                | variant
    ${'RUNNING'}        | ${'status-running'} | ${'info'}
    ${'INPUT_REQUIRED'} | ${'status-alert'}   | ${'warning'}
    ${'PAUSED'}         | ${'status-paused'}  | ${'subtle'}
  `('shows the $icon icon for a $status session', ({ status, icon, variant }) => {
    createComponent({ id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/1', status, humanStatus: 'x' });

    expect(findIcon().props()).toMatchObject({ name: icon, variant });
  });

  it('uses the human status as tooltip and accessible label', () => {
    createComponent({
      id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/1',
      status: 'RUNNING',
      humanStatus: 'Running',
    });

    expect(wrapper.attributes('title')).toBe('Running');
    expect(findIcon().attributes('aria-label')).toBe('Running');
  });
});
