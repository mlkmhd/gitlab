<script>
import { GlButton } from '@gitlab/ui';
import HandRaiseLeadButton from 'ee/hand_raise_leads/hand_raise_lead/components/hand_raise_lead_button.vue';
import { isExternal } from '~/lib/utils/url_utility';

// The call to action in an Explore page's header, as built by Onboarding::FeatureLibrary::UpgradeCta.
// On GitLab.com, talking to sales opens the hand raise lead modal. Otherwise it's a button that
// links to the CTA's URL, in a new tab when it leaves GitLab.
export default {
  name: 'FeatureLibraryUpgradeCta',
  components: { GlButton, HandRaiseLeadButton },
  buttonAttributes: { variant: 'confirm' },
  props: {
    cta: {
      type: Object,
      required: true,
    },
  },
  emits: ['click'],
  computed: {
    target() {
      return isExternal(this.cta.url) ? '_blank' : undefined;
    },
  },
};
</script>

<template>
  <hand-raise-lead-button
    v-if="cta.hand_raise_lead"
    :button-text="cta.text"
    :button-attributes="$options.buttonAttributes"
    :glm-content="cta.hand_raise_lead.glm_content"
    :cta-tracking="cta.hand_raise_lead.cta_tracking"
    data-testid="feature-library-cta-hand-raise"
    @click="$emit('click', cta.type)"
  />
  <gl-button
    v-else
    variant="confirm"
    :href="cta.url"
    :target="target"
    data-testid="feature-library-cta-button"
    @click="$emit('click', cta.type)"
  >
    {{ cta.text }}
  </gl-button>
</template>
