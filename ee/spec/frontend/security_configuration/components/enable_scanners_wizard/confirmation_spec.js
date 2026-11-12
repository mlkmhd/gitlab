import { GlEmptyState, GlButton, GlSprintf, GlTable } from '@gitlab/ui';
import { shallowMountExtended, mountExtended } from 'helpers/vue_test_utils_helper';
import EnableScannersConfirmation from 'ee/security_configuration/components/enable_scanners_wizard/confirmation.vue';
import {
  ATTACH_MODE_SET,
  ATTACH_MODE_FILL_SCAN_GAPS,
  ATTACH_MODE_REPLACE,
  ATTACH_MODE_OPTIONS,
  TRIAGE_ATTACH_MODE_OPTIONS,
  ATTACH_MODE_FILL_PROFILE_GAPS,
} from 'ee/security_configuration/components/enable_scanners_wizard/constants';

describe('EnableScannersConfirmation', () => {
  let wrapper;

  const selectedProfiles = [
    { id: 'gid://gitlab/Security::ScanProfile/1', name: 'SAST Profile', scanType: 'SAST' },
    {
      id: 'gid://gitlab/Security::ScanProfile/2',
      name: 'Secret Detection Profile',
      scanType: 'SECRET_DETECTION',
    },
  ];

  const createComponent = ({
    areAllItemsSelected = false,
    selectedItems = [],
    selectedProfiles: scanners = [],
    hasModeStep = false,
    attachMode = ATTACH_MODE_FILL_SCAN_GAPS,
    attachModeOptions = ATTACH_MODE_OPTIONS,
    props = {},
    mountFn = shallowMountExtended,
  } = {}) => {
    wrapper = mountFn(EnableScannersConfirmation, {
      propsData: props,
      provide: {
        wizard: {
          areAllItemsSelected,
          selectedItems,
          selectedProfiles: scanners,
          hasModeStep,
          attachMode,
          attachModeOptions,
        },
      },
      stubs: { GlEmptyState, GlSprintf, GlTable, GlButton: true, ScanTypeCell: true },
    });
  };

  const findEmptyState = () => wrapper.findComponent(GlEmptyState);
  const findButton = () => wrapper.findComponent(GlButton);
  const findTableRows = () => wrapper.findAll('tbody tr');
  const findItemsCell = (row) => row.findAll('td').at(2);

  beforeEach(() => {
    createComponent();
  });

  it('renders a "Go to security configuration" link-button to the root route', () => {
    expect(findButton().text()).toBe('Go to security configuration');
    expect(findButton().attributes('to')).toBe('/');
  });

  describe('with a security configuration tab from the wizard', () => {
    it('links the button to the tab', () => {
      createComponent({ props: { securityConfigurationTab: 'automated-triage-and-remediation' } });

      expect(findButton().attributes('href')).toBe(
        `${window.location.pathname}?tab=automated-triage-and-remediation`,
      );
      expect(findButton().attributes('to')).toBeUndefined();
    });
  });

  describe('with copy from the wizard', () => {
    beforeEach(() => {
      createComponent({
        selectedItems: [{ id: 1 }, { id: 2 }],
        selectedProfiles: [{ id: '1', name: 'Triage and Remediation (Standard)' }],
        props: {
          title: 'Automated Triage and Remediation is rolling out',
          itemsRolloutMessage:
            '%{strongStart}%{profileName}%{strongEnd} is rolling out to %{itemCount} in batches.',
        },
      });
    });

    it('renders its title', () => {
      expect(findEmptyState().props('title')).toBe(
        'Automated Triage and Remediation is rolling out',
      );
    });

    it('renders its message with profile and item count', () => {
      expect(findEmptyState().text()).toContain(
        'Triage and Remediation (Standard) is rolling out to 2 items in batches.',
      );
    });
  });

  describe('rollout message', () => {
    it('renders the correct message when all items are selected', () => {
      createComponent({ areAllItemsSelected: true });

      expect(findEmptyState().props()).toMatchObject({
        title: 'Security scanning is rolling out',
      });
      expect(findEmptyState().text()).toContain('all uncovered projects');
    });

    it('renders the correct message when specific items are selected', () => {
      createComponent({ selectedItems: [{ id: 1 }, { id: 2 }] });

      expect(findEmptyState().props()).toMatchObject({
        title: 'Security scanning is rolling out',
      });
      expect(findEmptyState().text()).toContain('2 items');
    });

    it.each`
      attachMode                    | message
      ${ATTACH_MODE_SET}            | ${'Profiles will be applied to all projects as each batch completes'}
      ${ATTACH_MODE_FILL_SCAN_GAPS} | ${"Profiles will be applied to projects that don't scan yet as each batch completes"}
      ${ATTACH_MODE_REPLACE}        | ${'Profiles will be applied to projects that already have a profile, replacing it as each batch completes'}
    `('describes the projects the $attachMode mode applies to', ({ attachMode, message }) => {
      createComponent({ areAllItemsSelected: true, hasModeStep: true, attachMode });

      expect(findEmptyState().text()).toContain(message);
      expect(findEmptyState().text()).not.toContain('uncovered');
    });

    it('renders an empty description for an unknown mode', () => {
      createComponent({ areAllItemsSelected: true, hasModeStep: true, attachMode: 'UNKNOWN' });

      expect(findEmptyState().text()).not.toContain('Profiles will be applied');
    });

    it('shows the profile name in the mode message', () => {
      createComponent({
        areAllItemsSelected: true,
        hasModeStep: true,
        attachMode: ATTACH_MODE_FILL_PROFILE_GAPS,
        attachModeOptions: TRIAGE_ATTACH_MODE_OPTIONS,
        selectedProfiles: [{ id: '1', name: 'Triage and Remediation (Standard)' }],
      });

      expect(findEmptyState().text()).toContain(
        'Triage and Remediation (Standard) is rolling out in batches to projects without an Automated Triage and Remediation profile of their own.',
      );
    });
  });

  describe('configuration applied summary', () => {
    it('renders a row per selected scanner with its scan type and profile name', () => {
      createComponent({ selectedProfiles, mountFn: mountExtended });

      const rows = findTableRows();
      expect(rows).toHaveLength(selectedProfiles.length);
      expect(rows.at(0).text()).toContain('SAST Profile');
      expect(rows.at(1).text()).toContain('Secret Detection Profile');
    });

    it('shows "All" in the items cell when all items are selected', () => {
      createComponent({ areAllItemsSelected: true, selectedProfiles, mountFn: mountExtended });

      expect(findItemsCell(findTableRows().at(0)).text()).toBe('All');
    });

    it('shows the selected project count in the items cell otherwise', () => {
      createComponent({
        selectedItems: [{ id: 1 }, { id: 2 }, { id: 3 }],
        selectedProfiles,
        mountFn: mountExtended,
      });

      expect(findItemsCell(findTableRows().at(0)).text()).toBe('3');
    });
  });

  describe('items cell with a mode step', () => {
    it.each`
      attachMode                       | attachModeOptions             | label
      ${ATTACH_MODE_SET}               | ${ATTACH_MODE_OPTIONS}        | ${'All projects'}
      ${ATTACH_MODE_FILL_SCAN_GAPS}    | ${ATTACH_MODE_OPTIONS}        | ${"Projects that don't scan yet"}
      ${ATTACH_MODE_REPLACE}           | ${ATTACH_MODE_OPTIONS}        | ${'Replace existing'}
      ${ATTACH_MODE_FILL_PROFILE_GAPS} | ${TRIAGE_ATTACH_MODE_OPTIONS} | ${'Fill gaps'}
    `('shows "$label" for the $attachMode mode', ({ attachMode, attachModeOptions, label }) => {
      createComponent({
        areAllItemsSelected: true,
        hasModeStep: true,
        attachMode,
        attachModeOptions,
        selectedProfiles,
        mountFn: mountExtended,
      });

      expect(findItemsCell(findTableRows().at(0)).text()).toBe(label);
    });
  });
});
