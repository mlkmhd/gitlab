import { nextTick } from 'vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import DynamicPanel from '~/vue_shared/components/dynamic_panel.vue';
import SessionDetailsDrawer from 'ee/agent_artifacts/components/session_details_drawer.vue';
import GovernanceSidePanel from 'ee/ai/governance/components/side_panel/governance_side_panel.vue';
import AuditEventsPanelView from 'ee/ai/governance/components/side_panel/audit_events_panel_view.vue';
import SkillPanelView from 'ee/ai/governance/components/side_panel/skill_panel_view.vue';

const filters = { projectPath: 'gitlab-duo/web-app', startTimeAfter: '2026-11-03' };
const session = { id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/1', sessionId: '1' };
const listEntry = { view: 'audit-events', props: { filters } };
const sessionEntry = { view: 'session', props: { session } };
const skillEntry = {
  view: 'skill',
  props: {
    vulnerabilityId: 'gid://gitlab/Vulnerability/7',
    title: '0x-swap',
    href: '/gitlab-duo/data-pipeline/-/security/vulnerabilities/7',
  },
};

describe('GovernanceSidePanel', () => {
  let wrapper;
  let focusSession;

  const createComponent = ({ props = {}, attachTo } = {}) => {
    focusSession = jest.fn();
    wrapper = shallowMountExtended(GovernanceSidePanel, {
      attachTo,
      propsData: { stack: [listEntry], ...props },
      stubs: {
        MountingPortal: { template: '<div><slot /></div>' },
        DynamicPanel: stubComponent(DynamicPanel),
        SessionDetailsDrawer: stubComponent(SessionDetailsDrawer, {
          methods: { focus: focusSession },
        }),
      },
    });
  };

  const findPanel = () => wrapper.findComponent(DynamicPanel);
  const findList = () => wrapper.findComponent(AuditEventsPanelView);
  const findSession = () => wrapper.findComponent(SessionDetailsDrawer);
  const findSkill = () => wrapper.findComponent(SkillPanelView);
  const pressEscape = () => document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));

  describe('with the Audit events list on top', () => {
    beforeEach(() => {
      createComponent();
    });

    it('shows the list with its filters in a panel titled Audit events', () => {
      expect(findPanel().props('header')).toBe('Audit events');
      expect(findPanel().isVisible()).toBe(true);
      expect(findList().props()).toEqual({ filters });
      expect(findSession().exists()).toBe(false);
    });

    it('opens the Audit events tab with the same filters in full page', () => {
      expect(findPanel().props('maximizeUrl')).toBe(
        '?tab=agent-artifacts&projectPath=gitlab-duo%2Fweb-app&startTimeAfter=2026-11-03',
      );
    });

    it('pushes the session a row opens', () => {
      findList().vm.$emit('open-session', session);

      expect(wrapper.emitted('push')).toEqual([[sessionEntry]]);
    });

    it('starts the list over when a card opens a new panel', async () => {
      const firstList = findList().vm;
      const newFilters = { projectPath: 'gitlab-duo/api-service' };

      await wrapper.setProps({ stack: [{ view: 'audit-events', props: { filters: newFilters } }] });

      expect(findList().vm).not.toBe(firstList);
      expect(findList().props('filters')).toEqual(newFilters);
    });

    it('emits close when the panel is closed', () => {
      findPanel().vm.$emit('close');

      expect(wrapper.emitted('close')).toHaveLength(1);
    });

    it('emits close on Escape', () => {
      pressEscape();

      expect(wrapper.emitted('close')).toHaveLength(1);
    });

    it('stops listening for Escape once it is gone', () => {
      wrapper.destroy();
      pressEscape();

      expect(wrapper.emitted('close')).toBeUndefined();
    });

    describe('when Escape belongs to something else', () => {
      it('stays open while a modal is open', () => {
        document.body.classList.add('modal-open');
        pressEscape();
        document.body.classList.remove('modal-open');

        expect(wrapper.emitted('close')).toBeUndefined();
      });

      it('stays open while typing in an input, such as the filter bar', () => {
        const input = document.createElement('input');
        document.body.appendChild(input);
        input.focus();
        pressEscape();
        input.remove();

        expect(wrapper.emitted('close')).toBeUndefined();
      });
    });
  });

  describe('when the card names what it opened', () => {
    beforeEach(() => {
      createComponent({
        props: { stack: [{ ...listEntry, props: { ...listEntry.props, title: 'web-app' } }] },
      });
    });

    it('titles the panel with that name', () => {
      expect(findPanel().props('header')).toBe('web-app');
    });
  });

  describe('with a skill', () => {
    beforeEach(() => {
      createComponent({ props: { stack: [skillEntry] } });
    });

    it('shows the skill in a panel titled with its name', () => {
      expect(findPanel().props('header')).toBe('0x-swap');
      expect(findSkill().props('vulnerabilityId')).toBe('gid://gitlab/Vulnerability/7');
      expect(findList().exists()).toBe(false);
    });

    it('emits close on Escape', () => {
      pressEscape();

      expect(wrapper.emitted('close')).toHaveLength(1);
    });

    it('opens its vulnerability in full page', () => {
      expect(findPanel().props('maximizeUrl')).toBe(
        '/gitlab-duo/data-pipeline/-/security/vulnerabilities/7',
      );
    });

    it('emits close when the panel is closed', () => {
      findPanel().vm.$emit('close');

      expect(wrapper.emitted('close')).toHaveLength(1);
    });
  });

  describe('with a session on top of the list', () => {
    beforeEach(() => {
      createComponent({ props: { stack: [listEntry, sessionEntry] } });
    });

    it('shows the session details in the panel layout with a back button', () => {
      expect(findSession().props()).toMatchObject({
        activeItem: session,
        selectedEvent: null,
        backLabel: 'Back',
        panelLayout: true,
      });
    });

    it('opens the Audit events tab with the same filters and this session in full page', () => {
      expect(findSession().props('maximizeUrl')).toBe(
        '?tab=agent-artifacts&projectPath=gitlab-duo%2Fweb-app&startTimeAfter=2026-11-03&session=1',
      );
    });

    it('takes the list out of the panel while the session shows', () => {
      expect(findList().exists()).toBe(false);
    });

    it('emits back from the session', () => {
      findSession().vm.$emit('back');

      expect(wrapper.emitted('back')).toHaveLength(1);
    });

    it('leaves an open audit event before going back', async () => {
      const event = { id: 'gid://gitlab/AuditEvent/1' };

      findSession().vm.$emit('select', event);
      await nextTick();
      expect(findSession().props('selectedEvent')).toBe(event);

      findSession().vm.$emit('back');
      await nextTick();

      expect(findSession().props('selectedEvent')).toBeNull();
      expect(wrapper.emitted('back')).toBeUndefined();
    });

    it('emits close when the session closes', () => {
      findSession().vm.$emit('close');

      expect(wrapper.emitted('close')).toHaveLength(1);
    });

    it('leaves Escape to the session view', () => {
      pressEscape();

      expect(wrapper.emitted('close')).toBeUndefined();
    });
  });

  it('shows no back button for a session with nothing under it', () => {
    createComponent({ props: { stack: [sessionEntry] } });

    expect(findSession().props('backLabel')).toBeNull();
    expect(findSession().props('maximizeUrl')).toBe('?tab=agent-artifacts&session=1');
    expect(findList().exists()).toBe(false);
  });

  describe('focus', () => {
    let opener;

    const focusNewOpener = () => {
      const button = document.createElement('button');
      document.body.appendChild(button);
      button.focus();
      return button;
    };

    beforeEach(() => {
      opener = focusNewOpener();
      createComponent({ attachTo: document.body });
    });

    afterEach(() => {
      opener.remove();
    });

    it('moves focus into the panel when it opens', async () => {
      await nextTick();

      expect(document.activeElement).toBe(findPanel().element);
    });

    it('keeps the panel out of the click focus order once focus leaves it', async () => {
      await nextTick();
      opener.focus();

      expect(findPanel().attributes('tabindex')).toBeUndefined();
    });

    it('moves focus into the session when one is pushed, and back to the list after', async () => {
      await wrapper.setProps({ stack: [listEntry, sessionEntry] });
      await nextTick();
      expect(focusSession).toHaveBeenCalled();

      await wrapper.setProps({ stack: [listEntry] });
      await nextTick();
      expect(document.activeElement).toBe(findPanel().element);
    });

    it('returns focus to what opened the panel when it closes', async () => {
      await nextTick();
      wrapper.destroy();

      expect(document.activeElement).toBe(opener);
    });

    it('returns focus to the card that opened the latest panel', async () => {
      const secondOpener = focusNewOpener();
      await wrapper.setProps({ stack: [{ view: 'audit-events', props: { filters: {} } }] });
      await nextTick();
      wrapper.destroy();

      expect(document.activeElement).toBe(secondOpener);
      secondOpener.remove();
    });
  });
});
