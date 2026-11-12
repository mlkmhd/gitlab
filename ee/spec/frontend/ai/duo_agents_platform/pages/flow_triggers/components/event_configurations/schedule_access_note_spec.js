import { GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ScheduleAccessNote from 'ee/ai/duo_agents_platform/pages/flow_triggers/components/event_configurations/schedule_access_note.vue';
import HelpPageLink from '~/vue_shared/components/help_page_link/help_page_link.vue';

describe('ScheduleAccessNote', () => {
  let wrapper;

  const createWrapper = (propsData = {}) => {
    wrapper = shallowMountExtended(ScheduleAccessNote, {
      propsData,
      stubs: { GlSprintf, HelpPageLink },
    });
  };

  const findLinkByHref = (href) =>
    wrapper.findAllComponents(HelpPageLink).wrappers.find((link) => link.props('href') === href);
  const findRoleLink = () => findLinkByHref('user/permissions');
  const findDocsLink = () => findLinkByHref('user/duo_agent_platform/triggers/_index');

  describe('when a service account role is provided', () => {
    beforeEach(() => {
      createWrapper({ serviceAccountRole: 'Developer' });
    });

    it('names the separate account, the role, and how the role changes', () => {
      expect(wrapper.text()).toBe(
        "Scheduled automations use a separate service account with the Developer role on this project and no composite identity, so they can do anything that role allows. The account's role follows the flow's service account role: it's lowered automatically before each run, and raised only when someone who can assign that role edits this automation. Learn more.",
      );
    });

    it('links the role to the roles documentation', () => {
      expect(findRoleLink().props('anchor')).toBe('roles');
      expect(findRoleLink().text()).toBe('Developer role');
    });
  });

  describe('when no service account role is provided', () => {
    beforeEach(() => {
      createWrapper({ serviceAccountRole: null });
    });

    it('falls back to the generic wording without a role link', () => {
      expect(wrapper.text()).toBe(
        "Scheduled automations use a separate service account with no composite identity, so they can do anything its role allows. The account's role follows the flow's service account role: it's lowered automatically before each run, and raised only when someone who can assign that role edits this automation. Learn more.",
      );
      expect(findRoleLink()).toBeUndefined();
    });
  });

  describe.each([['Developer'], [null]])('with a service account role of %s', (role) => {
    beforeEach(() => {
      createWrapper({ serviceAccountRole: role });
    });

    it('links to the section describing how the role is kept in sync', () => {
      expect(findDocsLink().props('anchor')).toBe('service-account-for-scheduled-automations');
      expect(findDocsLink().text()).toBe('Learn more');
    });
  });
});
