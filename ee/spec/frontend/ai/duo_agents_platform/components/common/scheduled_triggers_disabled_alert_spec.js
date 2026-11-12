import { GlAlert, GlLink, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ScheduledTriggersDisabledAlert from 'ee/ai/duo_agents_platform/components/common/scheduled_triggers_disabled_alert.vue';

describe('ScheduledTriggersDisabledAlert', () => {
  let wrapper;

  const createComponent = ({ scheduled = true, duoSettings = {} } = {}) => {
    wrapper = shallowMountExtended(ScheduledTriggersDisabledAlert, {
      propsData: { scheduled },
      provide: { duoSettings },
      stubs: { GlSprintf },
    });
  };

  const findAlert = () => wrapper.findComponent(GlAlert);
  const findSettingsLink = () => wrapper.findComponent(GlLink);

  describe('visibility', () => {
    it('renders when a schedule is present and the setting is off', () => {
      createComponent({ duoSettings: { duoScheduledTriggersEnabled: false } });

      expect(findAlert().exists()).toBe(true);
      expect(findAlert().props('variant')).toBe('warning');
      expect(findAlert().props('dismissible')).toBe(false);
      expect(findAlert().props('title')).toBe('Scheduled automations are turned off');
    });

    it('is hidden when the setting is on', () => {
      createComponent({ duoSettings: { duoScheduledTriggersEnabled: true } });

      expect(findAlert().exists()).toBe(false);
    });

    it('is hidden when nothing on the page is scheduled', () => {
      createComponent({ scheduled: false, duoSettings: { duoScheduledTriggersEnabled: false } });

      expect(findAlert().exists()).toBe(false);
    });

    it('is hidden when the setting was never provided', () => {
      createComponent({ duoSettings: {} });

      expect(findAlert().exists()).toBe(false);
    });
  });

  describe('when beta features are off', () => {
    it('renders even with the setting on, because the schedule has stopped running either way', () => {
      createComponent({
        duoSettings: { duoBetaFeaturesEnabled: false, duoScheduledTriggersEnabled: true },
      });

      expect(findAlert().exists()).toBe(true);
      expect(findAlert().props('title')).toBe('Scheduled automations are not available');
    });

    it('points at beta features rather than the setting', () => {
      createComponent({ duoSettings: { duoBetaFeaturesEnabled: false } });

      expect(findAlert().text()).toMatchInterpolatedText(
        'Existing schedules are kept but do not run, and new ones cannot be added. To run them again, turn on experiment and beta GitLab Duo features.',
      );
    });

    it('does not link to GitLab Duo settings, which is the wrong switch', () => {
      createComponent({
        duoSettings: {
          duoBetaFeaturesEnabled: false,
          duoSettingsPath: '/groups/foo/-/duo',
          duoScheduledTriggersSettingsPath: '/foo/bar/edit#js-gitlab-duo-settings',
        },
      });

      expect(findSettingsLink().exists()).toBe(false);
    });

    it('takes precedence when both are off', () => {
      createComponent({
        duoSettings: {
          duoBetaFeaturesEnabled: false,
          duoScheduledTriggersEnabled: false,
          duoSettingsPath: '/groups/foo/-/duo',
        },
      });

      expect(findAlert().props('title')).toBe('Scheduled automations are not available');
      expect(findSettingsLink().exists()).toBe(false);
    });
  });

  describe('when the user can change the setting', () => {
    beforeEach(() => {
      createComponent({
        duoSettings: { duoScheduledTriggersEnabled: false, duoSettingsPath: '/groups/foo/-/duo' },
      });
    });

    it('links to GitLab Duo settings', () => {
      expect(findSettingsLink().attributes('href')).toBe('/groups/foo/-/duo');
      expect(findSettingsLink().text()).toBe('GitLab Duo settings');
    });

    it('explains what to do', () => {
      expect(findAlert().text()).toMatchInterpolatedText(
        'Existing schedules are kept but do not run, and new ones cannot be added. To run them again, turn on scheduled automations in GitLab Duo settings.',
      );
    });
  });

  describe('when the user can change the setting on the project', () => {
    beforeEach(() => {
      createComponent({
        duoSettings: {
          duoScheduledTriggersEnabled: false,
          duoScheduledTriggersSettingsPath: '/my-group/my-project/edit#js-gitlab-duo-settings',
          duoSettingsPath: '/groups/foo/-/duo',
        },
      });
    });

    it('links to the project settings rather than the group', () => {
      expect(findSettingsLink().attributes('href')).toBe(
        '/my-group/my-project/edit#js-gitlab-duo-settings',
      );
    });
  });

  describe('when the user cannot change the setting', () => {
    beforeEach(() => {
      createComponent({ duoSettings: { duoScheduledTriggersEnabled: false } });
    });

    it('names who can turn them back on instead of linking', () => {
      expect(findSettingsLink().exists()).toBe(false);
      expect(findAlert().text()).toMatchInterpolatedText(
        'Existing schedules are kept but do not run, and new ones cannot be added. Ask a group Owner or administrator to turn them back on.',
      );
    });
  });
});
