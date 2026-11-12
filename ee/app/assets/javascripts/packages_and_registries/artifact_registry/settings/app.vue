<script>
import { GlAlert, GlSprintf } from '@gitlab/ui';
import { s__ } from '~/locale';
import InputCopyToggleVisibility from '~/vue_shared/components/input_copy_toggle_visibility/input_copy_toggle_visibility.vue';
import SettingsBlock from '~/vue_shared/components/settings/settings_block.vue';
import ActivationSection from './activation_section.vue';

const ORGANIZATION_ID_INPUT_ID = 'artifact-registry-organization-id-input';

export default {
  name: 'ArtifactRegistrySettingsApp',
  components: { ActivationSection, GlAlert, GlSprintf, InputCopyToggleVisibility, SettingsBlock },
  inject: ['organizationId'],
  organizationIdInputId: ORGANIZATION_ID_INPUT_ID,
  organizationIdInputProps: { id: ORGANIZATION_ID_INPUT_ID },
  data() {
    return {
      announcement: null,
    };
  },
  methods: {
    announce(variant, message) {
      this.announcement = { variant, message };
    },
  },
  i18n: {
    activationTitle: s__('ArtifactRegistry|Activation'),
    activationDescription: s__(
      'ArtifactRegistry|Control artifact registry access for this organization. When enabled, all projects and groups have access to a unified registry.',
    ),
    organizationIdTitle: s__('ArtifactRegistry|Organization ID'),
    organizationIdDescription: s__(
      'ArtifactRegistry|Use this ID in the %{codeStart}X-GitLab-Organization-ID%{codeEnd} header when you call the artifact registry API.',
    ),
    copyOrganizationId: s__('ArtifactRegistry|Copy organization ID'),
  },
};
</script>

<template>
  <div>
    <settings-block
      :title="$options.i18n.activationTitle"
      expanded
      data-testid="artifact-registry-settings"
    >
      <template #description>{{ $options.i18n.activationDescription }}</template>
      <template #default>
        <gl-alert
          v-if="announcement"
          :variant="announcement.variant"
          class="gl-mb-5"
          data-testid="settings-alert-region"
          @dismiss="announcement = null"
        >
          {{ announcement.message }}
        </gl-alert>

        <activation-section
          @success="announce('success', $event)"
          @error="announce('danger', $event)"
        />
      </template>
    </settings-block>

    <settings-block
      :title="$options.i18n.organizationIdTitle"
      expanded
      data-testid="artifact-registry-organization-id"
    >
      <template #description>
        <gl-sprintf :message="$options.i18n.organizationIdDescription">
          <template #code="{ content }">
            <code>{{ content }}</code>
          </template>
        </gl-sprintf>
      </template>
      <template #default>
        <input-copy-toggle-visibility
          :value="organizationId"
          :label="$options.i18n.organizationIdTitle"
          :label-for="$options.organizationIdInputId"
          label-sr-only
          :form-input-group-props="$options.organizationIdInputProps"
          :copy-button-title="$options.i18n.copyOrganizationId"
          :show-toggle-visibility-button="false"
          readonly
          size="md"
          class="gl-mb-0"
        />
      </template>
    </settings-block>
  </div>
</template>
