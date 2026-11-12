<script>
import { GlSingleStat } from '@gitlab/ui/src/charts';
import { GlCard, GlIcon, GlButton, GlTableLite, GlTooltipDirective, GlLink } from '@gitlab/ui';
import { __ } from '~/locale';
import NameCell from 'ee/security_inventory/components/name_cell.vue';
import { APPROACH_ADVANCED } from './constants';
import ScannersCard from './scanners_card.vue';

export default {
  name: 'EnableScannersReview',
  components: {
    GlSingleStat,
    GlCard,
    GlIcon,
    GlButton,
    GlTableLite,
    GlLink,
    NameCell,
    ScannersCard,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  inject: ['wizard'],
  props: {
    profilesCard: {
      type: Object,
      required: false,
      default: () => ScannersCard,
    },
  },
  computed: {
    attachModeOption() {
      if (!this.wizard.hasModeStep) return null;
      return this.wizard.attachModeOptions.find(({ value }) => value === this.wizard.attachMode);
    },
    itemsImpacted() {
      if (this.attachModeOption) return this.attachModeOption.label;
      return this.wizard.areAllItemsSelected ? __('All') : `${this.wizard.selectedItems.length}`;
    },
  },
  APPROACH_ADVANCED,
  projectFields: [
    { key: 'name', label: __('Item'), thClass: 'gl-w-1/2' },
    { key: 'group', label: __('Group'), thClass: 'gl-w-1/2' },
  ],
};
</script>
<template>
  <div>
    <div class="gl-my-5 gl-grid gl-grid-cols-2 gl-gap-5">
      <gl-card>
        <template #header>
          <strong>{{ s__('SecurityConfiguration|Items impacted') }}</strong>
        </template>
        <gl-single-stat title="" data-testid="items-impacted-stat" :value="itemsImpacted" />
      </gl-card>
      <gl-card>
        <template #header>
          <strong>{{ s__('SecurityConfiguration|Scanners configured') }}</strong>
        </template>
        <gl-single-stat
          title=""
          data-testid="scanners-configured-stat"
          :value="wizard.selectedProfiles.length"
        />
      </gl-card>
    </div>

    <gl-card class="gl-my-5">
      <template #header>
        <div class="gl-flex gl-items-center gl-justify-between">
          <span class="gl-flex gl-items-center gl-gap-2">
            <gl-icon name="project" />
            <strong>{{ __('Items') }}</strong>
          </span>
          <gl-button
            v-if="wizard.approach === $options.APPROACH_ADVANCED"
            v-gl-tooltip
            :aria-label="s__('SecurityConfiguration|Edit project scope')"
            :title="s__('SecurityConfiguration|Edit project scope')"
            icon="pencil"
            category="tertiary"
            size="small"
            :to="{ name: wizard.routes.items }"
          />
        </div>
      </template>
      <p v-if="wizard.areAllItemsSelected" class="gl-m-3">
        {{
          attachModeOption
            ? attachModeOption.selectedMessage
            : s__('SecurityConfiguration|All uncovered projects are selected.')
        }}
      </p>
      <gl-table-lite
        v-else
        :fields="$options.projectFields"
        :items="wizard.selectedItems"
        table-class="!gl-bg-transparent"
        data-testid="items-table"
        borderless
      >
        <template #cell(name)="{ item }">
          <name-cell :item="item" :link-subgroups="false" />
        </template>
        <template #cell(group)="{ item }">
          <gl-link v-if="item.group" :href="item.group.webPath" target="_blank">
            {{ item.group.name }}
          </gl-link>
          <span v-else>
            {{ __('—') }}
          </span>
        </template>
      </gl-table-lite>
    </gl-card>

    <component :is="profilesCard" :editable="wizard.approach === $options.APPROACH_ADVANCED" />
  </div>
</template>
