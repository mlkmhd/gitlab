import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import setWindowLocation from 'helpers/set_window_location_helper';
import ExtendedDashboardPanel from '~/vue_shared/components/customizable_dashboard/extended_dashboard_panel.vue';
import ResolvedBySourcePanel from 'ee/security_dashboard/components/shared/resolved_by_source_panel.vue';
import OverTimePeriodSelector from 'ee/security_dashboard/components/shared/over_time_period_selector.vue';
import * as panelStateUrlSync from 'ee/security_dashboard/utils/panel_state_url_sync';

describe('ResolvedBySourcePanel', () => {
  let wrapper;

  const createComponent = () => {
    wrapper = shallowMountExtended(ResolvedBySourcePanel);
  };

  const findPanel = () => wrapper.findComponent(ExtendedDashboardPanel);
  const findTimePeriodSelector = () => wrapper.findComponent(OverTimePeriodSelector);

  beforeEach(() => {
    createComponent();
  });

  it('renders the panel with the correct title', () => {
    expect(findPanel().props('title')).toBe('Resolution breakdown');
  });

  it('defaults the time period to 30 days', () => {
    expect(findTimePeriodSelector().props('value')).toBe(30);
  });

  describe('time period URL sync', () => {
    it('initializes the time period from the URL parameter', () => {
      const initialTimePeriod = 60;

      setWindowLocation(`?vulnerabilitiesResolvedBySource.timePeriod=${initialTimePeriod}`);
      createComponent();

      expect(findTimePeriodSelector().props('value')).toBe(initialTimePeriod);
    });

    it('writes the time period to the URL when it changes', async () => {
      jest.spyOn(panelStateUrlSync, 'writeToUrl');

      await findTimePeriodSelector().vm.$emit('input', 90);

      expect(panelStateUrlSync.writeToUrl).toHaveBeenCalledWith({
        panelId: 'vulnerabilitiesResolvedBySource',
        paramName: 'timePeriod',
        value: 90,
        defaultValue: 30,
      });
    });
  });
});
