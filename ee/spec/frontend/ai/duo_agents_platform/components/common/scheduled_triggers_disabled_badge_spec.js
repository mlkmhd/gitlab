import { GlBadge } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import ScheduledTriggersDisabledBadge from 'ee/ai/duo_agents_platform/components/common/scheduled_triggers_disabled_badge.vue';

describe('ScheduledTriggersDisabledBadge', () => {
  let wrapper;

  const createComponent = ({ scheduled = true, active = true, duoSettings = {} } = {}) => {
    wrapper = shallowMountExtended(ScheduledTriggersDisabledBadge, {
      propsData: { scheduled, active },
      provide: { duoSettings },
      directives: { GlTooltip: createMockDirective('gl-tooltip') },
    });
  };

  const findBadge = () => wrapper.findComponent(GlBadge);

  describe('visibility', () => {
    it('renders when the trigger is scheduled and the setting is off', () => {
      createComponent({ scheduled: true, duoSettings: { duoScheduledTriggersEnabled: false } });

      expect(findBadge().exists()).toBe(true);
    });

    it('is hidden when the setting is on', () => {
      createComponent({ scheduled: true, duoSettings: { duoScheduledTriggersEnabled: true } });

      expect(findBadge().exists()).toBe(false);
    });

    it('is hidden when the trigger is not scheduled', () => {
      createComponent({ scheduled: false, duoSettings: { duoScheduledTriggersEnabled: false } });

      expect(findBadge().exists()).toBe(false);
    });

    it('is hidden when the trigger is not active', () => {
      createComponent({ active: false, duoSettings: { duoScheduledTriggersEnabled: false } });

      expect(findBadge().exists()).toBe(false);
    });

    it('is hidden when the setting was never provided', () => {
      createComponent({ scheduled: true, duoSettings: {} });

      expect(findBadge().exists()).toBe(false);
    });

    it('renders when beta features are off, even with the setting on', () => {
      createComponent({
        scheduled: true,
        duoSettings: { duoBetaFeaturesEnabled: false, duoScheduledTriggersEnabled: true },
      });

      expect(findBadge().exists()).toBe(true);
    });
  });

  describe('tooltip', () => {
    const findTooltip = () => getBinding(findBadge().element, 'gl-tooltip').value;

    it('names the setting when only the setting is off', () => {
      createComponent({ duoSettings: { duoScheduledTriggersEnabled: false } });

      expect(findTooltip()).toBe(
        'Scheduled automations are turned off in GitLab Duo settings. This schedule is kept but does not run.',
      );
    });

    it('names beta features when they are off', () => {
      createComponent({ duoSettings: { duoBetaFeaturesEnabled: false } });

      expect(findTooltip()).toBe(
        'Scheduled automations need experiment and beta features. This schedule is kept but does not run.',
      );
    });

    it('names beta features first when both are off, so it does not point at the wrong switch', () => {
      createComponent({
        duoSettings: { duoBetaFeaturesEnabled: false, duoScheduledTriggersEnabled: false },
      });

      expect(findTooltip()).toBe(
        'Scheduled automations need experiment and beta features. This schedule is kept but does not run.',
      );
    });
  });

  it('marks the row without competing with the page-level alert', () => {
    createComponent({ scheduled: true, duoSettings: { duoScheduledTriggersEnabled: false } });

    expect(findBadge().props('variant')).toBe('neutral');
    expect(findBadge().props('icon')).toBe('clock');
    expect(findBadge().text()).toBe('Not running');
  });
});
