import { GlButton, GlEmptyState, GlPopover } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import AutoRemediationCard from 'ee/security_configuration/components/scan_profiles/auto_remediation_card.vue';
import { mockTriageAndRemediationProfile } from './mock_data';

describe('AutoRemediationCard', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(AutoRemediationCard, {
      propsData: { canApplyProfiles: true, ...props },
      stubs: { GlButton, GlEmptyState },
    });
  };

  const findButton = () => wrapper.findComponentByTestId('auto-remediation-button');
  const findEmptyState = () => wrapper.findComponent(GlEmptyState);
  const findAttachedState = () => wrapper.findByTestId('auto-remediation-attached');
  const findProfileName = () => wrapper.findByTestId('auto-remediation-profile-name');
  const findProfileLink = () => wrapper.findComponentByTestId('auto-remediation-profile-link');
  const findProfileDescription = () => wrapper.findByTestId('auto-remediation-profile-description');

  describe('when no profile is attached', () => {
    beforeEach(() => {
      createComponent();
    });

    it('shows the empty state', () => {
      expect(findEmptyState().props()).toMatchObject({
        title: 'No profile applied',
        description:
          'Apply a profile to choose how GitLab triages and fixes vulnerabilities in this project.',
      });
      expect(findAttachedState().exists()).toBe(false);
    });

    it('labels the button to apply a profile', () => {
      expect(findButton().text()).toBe('Apply profile');
    });

    it('emits select-profile when the button is clicked', () => {
      findButton().vm.$emit('click');

      expect(wrapper.emitted('select-profile')).toHaveLength(1);
    });
  });

  describe('when a profile is attached', () => {
    beforeEach(() => {
      createComponent({ profile: mockTriageAndRemediationProfile });
    });

    it('shows the profile name and description', () => {
      expect(findProfileName().text()).toBe('Standard');
      expect(findProfileDescription().text()).toBe('Balanced settings for most projects.');
      expect(findEmptyState().exists()).toBe(false);
    });

    it('shows the profile name as a link that asks to view the profile', () => {
      expect(findProfileLink().props('variant')).toBe('link');
      expect(findProfileLink().text()).toBe('Standard');

      findProfileLink().vm.$emit('click');

      expect(wrapper.emitted('view-profile')).toHaveLength(1);
    });

    it('shows the profile link to users who cannot apply profiles', () => {
      createComponent({ profile: mockTriageAndRemediationProfile, canApplyProfiles: false });

      expect(findProfileLink().exists()).toBe(true);
    });

    it('focuses the profile link', () => {
      const focus = jest.spyOn(findProfileLink().element, 'focus');

      wrapper.vm.focusProfileLink();

      expect(focus).toHaveBeenCalled();
    });

    it('explains what a profile is next to the profile label', () => {
      expect(wrapper.findComponentByTestId('auto-remediation-profile-info').props('name')).toBe(
        'information-o',
      );
      expect(wrapper.findComponent(GlPopover).props('title')).toBe('What is a profile?');
      expect(wrapper.findComponent(GlPopover).text()).toContain(
        'A profile sets which capabilities run',
      );
    });
  });

  describe('when the user cannot apply profiles', () => {
    it('hides the apply button', () => {
      createComponent({ canApplyProfiles: false });

      expect(findButton().exists()).toBe(false);
    });
  });
});
