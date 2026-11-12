<script>
import { GlEmptyState, GlButton, GlSprintf, GlCard, GlTable, GlIcon } from '@gitlab/ui';
import confirmationSvgPath from '@gitlab/svgs/dist/illustrations/empty-state/empty-devops-md.svg?url';
import { __, s__, n__, sprintf } from '~/locale';
import { mergeUrlParams } from '~/lib/utils/url_utility';
import ScanTypeCell from '~/security_configuration/components/scan_profiles/scan_type_cell.vue';

export default {
  name: 'EnableScannersConfirmation',
  components: {
    GlEmptyState,
    GlButton,
    GlSprintf,
    GlCard,
    GlTable,
    GlIcon,
    ScanTypeCell,
  },
  inject: ['wizard'],
  props: {
    title: {
      type: String,
      required: false,
      default: () => s__('SecurityConfiguration|Security scanning is rolling out'),
    },
    securityConfigurationTab: {
      type: String,
      required: false,
      default: '',
    },
    itemsRolloutMessage: {
      type: String,
      required: false,
      default: () =>
        s__(
          'SecurityConfiguration|Your configuration has been applied and is rolling out to projects in batches. Profiles will be applied to %{strongStart}%{itemCount}%{strongEnd} as each batch completes — this may take a few minutes.',
        ),
    },
  },
  computed: {
    exitLink() {
      if (!this.securityConfigurationTab) return { to: '/' };
      return {
        href: mergeUrlParams({ tab: this.securityConfigurationTab }, window.location.pathname),
      };
    },
    projectCount() {
      return this.wizard.selectedItems.length;
    },
    attachModeOption() {
      if (!this.wizard.hasModeStep) return null;
      return this.wizard.attachModeOptions.find(({ value }) => value === this.wizard.attachMode);
    },
    itemsLabel() {
      if (this.attachModeOption) return this.attachModeOption.label;
      return this.wizard.areAllItemsSelected ? __('All') : this.projectCount;
    },
    rolloutMessage() {
      if (this.wizard.hasModeStep) {
        const option = this.wizard.attachModeOptions.find(
          ({ value }) => value === this.wizard.attachMode,
        );
        if (!option) return '';

        return sprintf(
          option.rolloutMessage,
          { profileName: this.wizard.selectedProfiles[0]?.name },
          false,
        );
      }

      if (this.wizard.areAllItemsSelected) {
        return s__(
          'SecurityConfiguration|Your configuration has been applied and is rolling out to projects in batches. Profiles will be applied to %{strongStart}all uncovered projects%{strongEnd} as each batch completes — this may take a few minutes.',
        );
      }

      return sprintf(
        this.itemsRolloutMessage,
        {
          itemCount: n__('%d item', '%d items', this.projectCount),
          profileName: this.wizard.selectedProfiles[0]?.name,
        },
        false,
      );
    },
  },
  confirmationSvgPath,
  tableFields: [
    { key: 'scanType', label: __('Scanner'), tdClass: '!gl-bg-transparent !gl-align-middle' },
    { key: 'name', label: __('Profile'), tdClass: '!gl-bg-transparent !gl-align-middle' },
    { key: 'items', label: __('Items'), tdClass: '!gl-bg-transparent !gl-align-middle' },
  ],
};
</script>
<template>
  <div>
    <gl-empty-state :title="title" :svg-path="$options.confirmationSvgPath">
      <template #description>
        <gl-sprintf :message="rolloutMessage">
          <template #strong="{ content }">
            <strong>{{ content }}</strong>
          </template>
        </gl-sprintf>
      </template>
      <template #actions>
        <gl-button category="primary" variant="confirm" v-bind="exitLink">{{
          s__('SecurityConfiguration|Go to security configuration')
        }}</gl-button>
      </template>
    </gl-empty-state>

    <gl-card class="gl-mt-5">
      <template #header>
        <span class="gl-flex gl-items-center gl-gap-2">
          <gl-icon name="project" />
          <strong>{{ s__('SecurityConfiguration|Configuration applied') }}</strong>
        </span>
      </template>
      <gl-table
        :fields="$options.tableFields"
        :items="wizard.selectedProfiles"
        table-class="!gl-bg-transparent !gl-border-collapse"
        borderless
      >
        <template #cell(scanType)="{ item }">
          <scan-type-cell :scan-type="item.scanType" solid />
        </template>
        <template #cell(items)>
          {{ itemsLabel }}
        </template>
      </gl-table>
    </gl-card>
  </div>
</template>
