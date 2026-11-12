import { GlButton, GlLink } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import BoardCardSessionBadgeRow from 'ee/boards/components/board_card_session_badge_row.vue';
import AgentStatusIcon from 'ee/ai/shared/widgets/agent_status_icon.vue';
import {
  buildSession,
  FINISHED_SESSION,
  SESSION_WITHOUT_PROJECT,
} from './board_card_session_badge_mock_data';

describe('BoardCardSessionBadgeRow', () => {
  let wrapper;

  const buildClickEvent = (modifiers = {}) => ({
    metaKey: false,
    ctrlKey: false,
    shiftKey: false,
    preventDefault: jest.fn(),
    ...modifiers,
  });

  const createComponent = (session = FINISHED_SESSION) => {
    wrapper = shallowMountExtended(BoardCardSessionBadgeRow, {
      propsData: { session },
      directives: { GlTooltip: createMockDirective('gl-tooltip') },
    });
  };

  const findSessionLink = () => wrapper.findComponentByTestId('popover-session-link');
  const findDefinition = () => wrapper.findByTestId('popover-session-definition');
  const findStatus = () => wrapper.findByTestId('popover-session-status');

  describe('with a session in a project', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the ID as a link to the session page', () => {
      expect(wrapper.findComponent(GlLink).exists()).toBe(true);
      expect(findSessionLink().text()).toBe('1');
      expect(findSessionLink().attributes('href')).toBe(
        '/group/project/-/automate/agent-sessions/1',
      );
    });

    it('renders the status icon, title and status text', () => {
      expect(wrapper.findComponent(AgentStatusIcon).props('status')).toBe('FINISHED');
      expect(findDefinition().text()).toBe('Planner');
      expect(findStatus().text()).toBe('Completed');
    });

    it('labels the status icon with the status description', () => {
      expect(wrapper.findComponent(AgentStatusIcon).props('label')).toBe(
        'Finished. The session completed its work.',
      );
    });

    it('hides the visible status from screen readers, since the icon label describes it', () => {
      expect(findStatus().attributes('aria-hidden')).toBe('true');
    });

    it('tooltips the session title with its ID on the ID link', () => {
      expect(getBinding(findSessionLink().element, 'gl-tooltip')).toBeDefined();
      expect(findSessionLink().attributes('title')).toBe('Planner 1');
    });

    it('emits show-session and prevents navigation on plain click', () => {
      const event = buildClickEvent();
      findSessionLink().vm.$emit('click', event);

      expect(event.preventDefault).toHaveBeenCalled();
      expect(wrapper.emitted('show-session')).toEqual([[FINISHED_SESSION]]);
    });

    it.each`
      modifier
      ${'metaKey'}
      ${'ctrlKey'}
      ${'shiftKey'}
    `('leaves $modifier-click to the browser', ({ modifier }) => {
      const event = buildClickEvent({ [modifier]: true });
      findSessionLink().vm.$emit('click', event);

      expect(event.preventDefault).not.toHaveBeenCalled();
      expect(wrapper.emitted('show-session')).toBeUndefined();
    });
  });

  describe.each`
    status              | humanStatus         | visibleStatus
    ${'STOPPED'}        | ${'stopped'}        | ${'Canceled'}
    ${'INPUT_REQUIRED'} | ${'input required'} | ${'Awaiting your input'}
  `('with a $status session', ({ status, humanStatus, visibleStatus }) => {
    beforeEach(() => {
      createComponent(buildSession({ status, humanStatus }));
    });

    it('shows the formatted status', () => {
      expect(findStatus().text()).toBe(visibleStatus);
    });
  });

  describe('with a session without a title', () => {
    it('falls back to the humanized workflow definition', () => {
      createComponent(buildSession({ title: null }));

      expect(findDefinition().text()).toBe('Planner');
    });
  });

  describe('with a session without a project', () => {
    beforeEach(() => {
      createComponent(SESSION_WITHOUT_PROJECT);
    });

    it('renders the ID as a link-variant button without an href', () => {
      expect(wrapper.findComponent(GlLink).exists()).toBe(false);
      expect(wrapper.findComponent(GlButton).props('variant')).toBe('link');
      expect(findSessionLink().text()).toBe('6');
      expect(findSessionLink().attributes('href')).toBeUndefined();
    });

    it('emits show-session on plain click', () => {
      const event = buildClickEvent();
      findSessionLink().vm.$emit('click', event);

      expect(event.preventDefault).toHaveBeenCalled();
      expect(wrapper.emitted('show-session')).toEqual([[SESSION_WITHOUT_PROJECT]]);
    });
  });
});
