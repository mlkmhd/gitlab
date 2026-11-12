<script>
import {
  GlBadge,
  GlDropdownDivider,
  GlDropdownSectionHeader,
  GlFilteredSearchSuggestion,
  GlFilteredSearchToken,
  GlIcon,
} from '@gitlab/ui';
import { s__ } from '~/locale';
import { getSelectedOptionsText } from '~/lib/utils/listbox_helpers';
import { glListenersMixin } from '~/lib/utils/vue3compat/gl_listeners_mixin';
import { ALL_ID } from 'ee/security_dashboard/components/shared/filtered_search/constants';

const ALL_ACTIVITY_VALUE = 'ALL';

const ITEMS = {
  DISMISSED_IN_MR: {
    value: 'DISMISSED_IN_MR',
    text: s__('SecurityReports|Dismissed in MR'),
  },
};

export const GROUPS = [
  {
    text: '',
    options: [
      {
        value: ALL_ACTIVITY_VALUE,
        text: s__('SecurityReports|All activity'),
      },
    ],
  },
  {
    text: s__('SecurityReports|Policy violations'),
    options: [ITEMS.DISMISSED_IN_MR],
    icon: 'flag',
    // Temporary until https://gitlab.com/gitlab-org/gitlab/-/work_items/628673: only the
    // PostgreSQL finder resolves policy violations, and a tracked ref filter sends the dependency
    // query to Elasticsearch, which does not index them.
    blockedByTrackedRefFilter: true,
  },
];

export default {
  activityTokenGroups: GROUPS,
  name: 'ActivityToken',
  components: {
    GlBadge,
    GlDropdownDivider,
    GlDropdownSectionHeader,
    GlFilteredSearchSuggestion,
    GlFilteredSearchToken,
    GlIcon,
  },
  mixins: [glListenersMixin],
  props: {
    config: {
      type: Object,
      required: true,
    },
    // contains the token, with the selected operand (e.g.: '=') and the data (comma separated, e.g.: 'MIT, GNU')
    value: {
      type: Object,
      required: true,
    },
    active: {
      type: Boolean,
      required: true,
    },
  },
  emits: ['destroy'],
  data() {
    // Default values are set on page load by parent component, when there is no query parameter.
    // Subsequent token mounts should use the ALL value because clearing tokens should reset to
    // ALL value and not default values.
    const defaultSelected = this.value.data || [ALL_ACTIVITY_VALUE];

    return {
      selectedActivities: defaultSelected,
    };
  },
  computed: {
    tokenValue() {
      return {
        ...this.value,
        // when the token is active (dropdown is open), we set the value to null to prevent an UX issue
        // in which only the last selected item is being displayed.
        // more information: https://gitlab.com/gitlab-org/gitlab-services/design.gitlab.com/-/issues/2467
        data: this.active ? null : this.selectedActivities,
      };
    },
    toggleText() {
      return getSelectedOptionsText({
        options: Object.values(ITEMS),
        selected: this.selectedActivities,
        placeholder: this.$options.i18n.allItemsText,
        maxOptionsShown: 2,
      });
    },
    isCompatibleWithAppliedTrackedRefFilter() {
      return (this.config.appliedTrackedRefs ?? []).every((ref) => ref === ALL_ID);
    },
    blockedActivityValues() {
      return this.$options.activityTokenGroups
        .filter((group) => group.blockedByTrackedRefFilter)
        .flatMap((group) => group.options.map((option) => option.value));
    },
  },
  watch: {
    isCompatibleWithAppliedTrackedRefFilter() {
      this.dropValueWhenOutOfScope();
    },
  },
  mounted() {
    // A watcher does not run for a value the token already holds on its first render.
    this.dropValueWhenOutOfScope();
  },
  methods: {
    dropValueWhenOutOfScope() {
      if (this.isCompatibleWithAppliedTrackedRefFilter) return;

      const hasBlockedValue = this.selectedActivities.some((activity) =>
        this.blockedActivityValues.includes(activity),
      );

      if (hasBlockedValue) {
        this.$emit('destroy');
      }
    },
    isGroupBlocked(group) {
      return (
        Boolean(group.blockedByTrackedRefFilter) && !this.isCompatibleWithAppliedTrackedRefFilter
      );
    },
    resetSelected() {
      this.selectedActivities = [];
    },
    toggleSelected(selectedValue) {
      if (selectedValue === ALL_ACTIVITY_VALUE || this.selectedActivities.includes(selectedValue)) {
        this.selectedActivities = [ALL_ACTIVITY_VALUE];
      } else {
        this.selectedActivities = [selectedValue];
      }
    },
    isActivitySelected(name) {
      return this.selectedActivities.includes(name);
    },
  },
  i18n: {
    label: s__('SecurityReports|Activity'),
    allItemsText: s__('SecurityReports|All activity'),
    blockedByTrackedRefFilter: s__(
      "SecurityReports|Policy violations aren't available for a specific tracked ref. Set Tracked ref to All tracked refs or clear the ref filter.",
    ),
  },
};
</script>

<template>
  <gl-filtered-search-token
    :config="config"
    v-bind="{ ...$props, ...$attrs }"
    :multi-select-values="selectedActivities"
    :value="tokenValue"
    v-on="glListeners()"
    @select="toggleSelected"
    @destroy="resetSelected"
  >
    <template #view>
      <span data-testid="activity-token-placeholder">{{ toggleText }}</span>
    </template>
    <template #suggestions>
      <template v-for="(group, index) in $options.activityTokenGroups">
        <gl-dropdown-section-header v-if="group.text" :key="group.text">
          <div
            v-if="group.icon"
            class="gl-flex gl-items-center gl-justify-center"
            :data-testid="`header-${group.text}`"
          >
            <div class="gl-grow">{{ group.text }}</div>
            <gl-badge :icon="group.icon" />
          </div>
        </gl-dropdown-section-header>
        <div
          v-if="isGroupBlocked(group)"
          :key="`${group.text}-blocked`"
          class="gl-p-2 gl-text-subtle"
          data-testid="policy-violations-blocked-by-ref"
        >
          {{ $options.i18n.blockedByTrackedRefFilter }}
        </div>
        <gl-filtered-search-suggestion
          v-for="activity in group.options"
          v-else
          :key="activity.value"
          :value="activity.value"
        >
          <div class="gl-flex gl-items-center">
            <gl-icon
              name="check"
              class="gl-mr-3 gl-shrink-0"
              :class="{ 'gl-invisible': !isActivitySelected(activity.value) }"
              variant="subtle"
            />
            {{ activity.text }}
          </div>
        </gl-filtered-search-suggestion>
        <gl-dropdown-divider
          v-if="index < $options.activityTokenGroups.length - 1"
          :key="`${group.text}-divider`"
        />
      </template>
    </template>
  </gl-filtered-search-token>
</template>
