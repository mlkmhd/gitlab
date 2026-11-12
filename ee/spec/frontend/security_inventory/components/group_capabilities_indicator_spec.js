import { GlPopover } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import GroupCapabilitiesIndicator from 'ee/security_inventory/components/group_capabilities_indicator.vue';
import SegmentedBar from 'ee/security_inventory/components/segmented_bar.vue';

describe('GroupCapabilitiesIndicator', () => {
  let wrapper;

  const createComponent = (counters = {}, analyzerStatuses, projectsCount) => {
    wrapper = shallowMountExtended(GroupCapabilitiesIndicator, {
      propsData: {
        item: {
          path: 'sub',
          projectsCount,
          analyzerStatuses: analyzerStatuses ?? [{ totalProjectsCount: 7 }],
          triageAndRemediationCoverageCounters: {
            enabledCount: 3,
            flowMissingCount: 1,
            ...counters,
          },
        },
      },
    });
  };

  const findBar = () => wrapper.findComponent(SegmentedBar);
  const findPopover = () => wrapper.findComponent(GlPopover);
  const findRow = (key) => wrapper.findByTestId(`capabilities-row-${key}`);

  it('renders the label under the bar', () => {
    createComponent();

    expect(wrapper.findByTestId('capabilities-label').text()).toBe('Automated Triage');
  });

  it('makes the bar focusable and labelled by the label', () => {
    createComponent();

    expect(findBar().attributes()).toMatchObject({
      tabindex: '0',
      'aria-labelledby': 'capabilities-sub-label',
    });
  });

  it('opens the popover on hover and focus', () => {
    createComponent();

    expect(findPopover().props()).toMatchObject({
      target: 'capabilities-sub-bar',
      title: 'Automated Triage and Remediation',
      triggers: 'hover focus',
    });
  });

  it('renders a bar segment per status in order', () => {
    createComponent();

    expect(
      findBar()
        .props('segments')
        .map(({ count }) => count),
    ).toEqual([2, 1, 4]);
  });

  it.each`
    key                 | text                           | icon
    ${'enabled'}        | ${'Enabled 2 projects'}        | ${'check-circle-filled'}
    ${'needsAttention'} | ${'Needs attention 1 project'} | ${'status-alert'}
    ${'notEnabled'}     | ${'Not enabled 4 projects'}    | ${'clear'}
  `('renders the $key row with its icon and count', ({ key, text, icon }) => {
    createComponent();

    expect(findRow(key).text().replace(/\s+/g, ' ')).toBe(text);
    expect(findRow(key).findComponent({ name: 'GlIcon' }).props('name')).toBe(icon);
  });

  it('treats missing counts as zero', () => {
    createComponent({ enabledCount: undefined, flowMissingCount: undefined });

    expect(findRow('enabled').text()).toContain('0 projects');
    expect(findRow('needsAttention').text()).toContain('0 projects');
  });

  describe('without analyzer statuses', () => {
    it('falls back to the direct projects count for the total', () => {
      createComponent({ enabledCount: 1, flowMissingCount: 0 }, [], 3);

      expect(findRow('notEnabled').text()).toContain('2 projects');
    });

    it('shows no projects as not enabled when the total is unknown', () => {
      createComponent({}, []);

      expect(findRow('notEnabled').text()).toContain('0 projects');
    });
  });
});
