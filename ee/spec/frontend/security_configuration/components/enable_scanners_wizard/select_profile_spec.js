import { GlFormRadioGroup, GlBadge } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import EnableScannersSelectProfile from 'ee/security_configuration/components/enable_scanners_wizard/select_profile.vue';
import TriageProfileDrawer from 'ee/security_configuration/components/scan_profiles/triage_profile_drawer.vue';
import { triagePresets, standardPreset, proactivePreset } from './mock_data';

describe('EnableScannersSelectProfile', () => {
  let wrapper;
  let wizard;

  const createComponent = ({ selectedProfiles = [] } = {}) => {
    wizard = {
      availableScanners: triagePresets,
      selectedProfiles,
      selectScannerProfile: jest.fn((scanType, profile) => {
        wizard.selectedProfiles = [profile];
      }),
    };

    wrapper = shallowMountExtended(EnableScannersSelectProfile, {
      provide: { wizard },
      stubs: { GlCard: { template: '<div><slot name="header" /><slot /></div>' } },
    });
  };

  const findOptions = () => wrapper.findAllByTestId('profile-option');
  const findRadioGroup = () => wrapper.findComponent(GlFormRadioGroup);
  const findPreviewButtons = () => wrapper.findAllComponentsByTestId('preview-profile-button');
  const findDrawer = () => wrapper.findComponent(TriageProfileDrawer);

  it('renders each preset', () => {
    createComponent();

    expect(findOptions().wrappers.map((option) => option.text())).toEqual([
      expect.stringContaining('Triage and Remediation (Conservative)'),
      expect.stringContaining('Triage and Remediation (Proactive)'),
      expect.stringContaining('Triage and Remediation (Standard)'),
    ]);
  });

  it('sets Standard by default', () => {
    createComponent();

    expect(wizard.selectScannerProfile).toHaveBeenCalledWith(
      'TRIAGE_AND_REMEDIATION',
      standardPreset,
    );
  });

  it('keeps a preset the user already chose', () => {
    createComponent({ selectedProfiles: [proactivePreset] });

    expect(wizard.selectScannerProfile).not.toHaveBeenCalled();
    expect(findRadioGroup().attributes('checked')).toBe(proactivePreset.id);
  });

  it('shows the Recommended badge on Standard', () => {
    createComponent();

    const badges = findOptions().wrappers.map((option) => option.findComponent(GlBadge).exists());

    expect(badges).toEqual([false, false, true]);
  });

  it('sets the chosen preset on the wizard', () => {
    createComponent();

    findRadioGroup().vm.$emit('input', proactivePreset.id);

    expect(wizard.selectScannerProfile).toHaveBeenLastCalledWith(
      'TRIAGE_AND_REMEDIATION',
      proactivePreset,
    );
  });

  describe('preview', () => {
    it('shows the preset drawer on the previewed preset', async () => {
      createComponent();

      const event = { preventDefault: jest.fn() };

      await findPreviewButtons().at(1).vm.$emit('click', event);

      expect(findDrawer().props()).toMatchObject({ open: true, presetId: proactivePreset.id });
      expect(event.preventDefault).toHaveBeenCalled();
    });

    it('hides the drawer on close', async () => {
      createComponent();
      await findPreviewButtons().at(1).vm.$emit('click', { preventDefault: jest.fn() });

      await findDrawer().vm.$emit('close');

      expect(findDrawer().props('open')).toBe(false);
    });
  });
});
