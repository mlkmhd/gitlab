import { GlButton } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { TEST_HOST } from 'helpers/test_constants';
import HandRaiseLeadButton from 'ee/hand_raise_leads/hand_raise_lead/components/hand_raise_lead_button.vue';
import FeatureLibraryUpgradeCta from 'ee/super_sidebar/components/feature_library/feature_library_upgrade_cta.vue';

describe('FeatureLibraryUpgradeCta', () => {
  let wrapper;

  const createWrapper = (cta) => {
    wrapper = shallowMountExtended(FeatureLibraryUpgradeCta, {
      propsData: { cta },
      stubs: { GlButton },
    });
  };

  const findHandRaiseLeadButton = () => wrapper.findComponent(HandRaiseLeadButton);
  const findButton = () => wrapper.findComponent(GlButton);

  describe('with a hand raise lead payload', () => {
    const cta = {
      type: 'talk_to_sales',
      text: 'Talk to sales',
      hand_raise_lead: {
        glm_content: 'feature_catalog_premium',
        cta_tracking: {
          action: 'click_button',
          label: 'feature_catalog_talk_to_sales',
          property: 'premium',
        },
      },
    };

    beforeEach(() => createWrapper(cta));

    it('renders the hand raise lead button with the payload', () => {
      expect(findHandRaiseLeadButton().props()).toMatchObject({
        buttonText: cta.text,
        buttonAttributes: { variant: 'confirm' },
        glmContent: cta.hand_raise_lead.glm_content,
        ctaTracking: cta.hand_raise_lead.cta_tracking,
      });
      expect(findButton().exists()).toBe(false);
    });

    it('emits click with the CTA type', () => {
      findHandRaiseLeadButton().vm.$emit('click');

      expect(wrapper.emitted('click')).toEqual([[cta.type]]);
    });
  });

  describe('with an external URL', () => {
    const cta = { type: 'upgrade', text: 'Upgrade to Premium', url: 'https://example.com/upgrade' };

    beforeEach(() => createWrapper(cta));

    it('renders a confirm button that opens the CTA URL in a new tab', () => {
      expect(findButton().props('variant')).toBe('confirm');
      expect(findButton().attributes('href')).toBe(cta.url);
      expect(findButton().attributes('target')).toBe('_blank');
      expect(findButton().text()).toBe(cta.text);
      expect(findHandRaiseLeadButton().exists()).toBe(false);
    });

    it('emits click with the CTA type', () => {
      findButton().vm.$emit('click');

      expect(wrapper.emitted('click')).toEqual([[cta.type]]);
    });
  });

  describe('with a URL in GitLab', () => {
    const cta = {
      type: 'upgrade',
      text: 'Upgrade to Ultimate',
      url: `${TEST_HOST}/groups/my-group/-/billings`,
    };

    beforeEach(() => createWrapper(cta));

    it('opens the CTA URL in the same tab', () => {
      expect(findButton().attributes('href')).toBe(cta.url);
      expect(findButton().attributes('target')).toBeUndefined();
    });
  });
});
