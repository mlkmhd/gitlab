<script>
import { GlBadge, GlButton, GlCard, GlFormRadio, GlFormRadioGroup, GlIcon } from '@gitlab/ui';
import { getDefaultProfile } from 'ee/security_configuration/components/scan_profiles/utils';
import TriageProfileDrawer from 'ee/security_configuration/components/scan_profiles/triage_profile_drawer.vue';

export default {
  name: 'EnableScannersSelectProfile',
  components: {
    GlBadge,
    GlButton,
    GlCard,
    GlFormRadio,
    GlFormRadioGroup,
    GlIcon,
    TriageProfileDrawer,
  },
  inject: ['wizard'],
  data() {
    return {
      previewProfileId: '',
    };
  },
  computed: {
    profiles() {
      return this.wizard.availableScanners;
    },
    selectedProfileId: {
      get() {
        return this.wizard.selectedProfiles[0]?.id ?? null;
      },
      set(id) {
        const profile = this.profiles.find((item) => item.id === id);
        this.wizard.selectScannerProfile(profile.scanType, profile);
      },
    },
  },
  created() {
    if (!this.selectedProfileId && this.profiles.length) {
      this.selectedProfileId = getDefaultProfile(this.profiles[0].scanType, this.profiles).id;
    }
  },
  methods: {
    isRecommended(profile) {
      return getDefaultProfile(profile.scanType, this.profiles) === profile;
    },
  },
};
</script>
<template>
  <div>
    <gl-form-radio-group v-model="selectedProfileId" class="gl-grid gl-gap-5 md:gl-grid-cols-3">
      <label
        v-for="profile in profiles"
        :key="profile.id"
        class="gl-mb-0 gl-flex gl-cursor-pointer gl-font-normal"
        data-testid="profile-option"
      >
        <gl-card class="gl-grow" body-class="gl-flex gl-flex-col">
          <template #header>
            <div class="gl-flex gl-items-center gl-justify-between gl-gap-3">
              <span class="gl-flex gl-flex-wrap gl-items-center gl-gap-2">
                <gl-icon name="tanuki-ai" />
                <strong>{{ profile.name }}</strong>
                <gl-badge v-if="isRecommended(profile)" variant="info">
                  {{ __('Recommended') }}
                </gl-badge>
              </span>
              <gl-form-radio :value="profile.id" />
            </div>
          </template>
          <p class="gl-text-subtle">{{ profile.description }}</p>
          <gl-button
            block
            class="gl-mt-auto"
            data-testid="preview-profile-button"
            @click.prevent="previewProfileId = profile.id"
          >
            {{ __('Preview') }}
          </gl-button>
        </gl-card>
      </label>
    </gl-form-radio-group>
    <triage-profile-drawer
      :open="Boolean(previewProfileId)"
      :preset-id="previewProfileId"
      @close="previewProfileId = ''"
    />
  </div>
</template>
