<script>
import { GlCard, GlIcon, GlButton, GlTableLite, GlTooltipDirective } from '@gitlab/ui';
import { __ } from '~/locale';
import TriageProfileDrawer from 'ee/security_configuration/components/scan_profiles/triage_profile_drawer.vue';

export default {
  name: 'EnableScannersProfileCard',
  components: {
    GlCard,
    GlIcon,
    GlButton,
    GlTableLite,
    TriageProfileDrawer,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  inject: ['wizard'],
  props: {
    editable: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  data() {
    return {
      previewProfileId: '',
    };
  },
  profileFields: [{ key: 'name', label: __('Profile') }],
};
</script>
<template>
  <gl-card class="gl-my-5">
    <template #header>
      <div class="gl-flex gl-items-center gl-justify-between">
        <span class="gl-flex gl-items-center gl-gap-2">
          <gl-icon name="tanuki-ai" />
          <strong>{{ __('Profile') }}</strong>
        </span>
        <gl-button
          v-if="editable"
          v-gl-tooltip
          :aria-label="s__('SecurityConfiguration|Change profile')"
          :title="s__('SecurityConfiguration|Change profile')"
          icon="pencil"
          category="tertiary"
          size="small"
          data-testid="edit-profile-button"
          :to="{ name: wizard.routes.profiles }"
        />
      </div>
    </template>
    <gl-table-lite
      :fields="$options.profileFields"
      :items="wizard.selectedProfiles"
      table-class="!gl-bg-transparent"
      data-testid="profile-table"
      borderless
    >
      <template #cell(name)="{ item }">
        <gl-button
          variant="link"
          data-testid="preview-profile-link"
          @click="previewProfileId = item.id"
        >
          {{ item.name }}
        </gl-button>
      </template>
    </gl-table-lite>

    <triage-profile-drawer
      :open="Boolean(previewProfileId)"
      :preset-id="previewProfileId"
      @close="previewProfileId = ''"
    />
  </gl-card>
</template>
