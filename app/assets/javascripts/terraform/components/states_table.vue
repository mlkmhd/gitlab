<script>
import {
  GlAlert,
  GlBadge,
  GlLink,
  GlLoadingIcon,
  GlSprintf,
  GlTable,
  GlTooltip,
  GlTooltipDirective,
} from '@gitlab/ui';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { s__, sprintf } from '~/locale';
import CiIcon from '~/vue_shared/components/ci_icon/ci_icon.vue';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import timeagoMixin from '~/vue_shared/mixins/timeago';
import StateActions from './states_table_actions.vue';

export default {
  name: 'StatesTable',
  components: {
    CiIcon,
    GlAlert,
    GlBadge,
    GlLink,
    GlLoadingIcon,
    GlSprintf,
    GlTable,
    GlTooltip,
    StateActions,
    TimeAgoTooltip,
  },
  directives: {
    GlTooltip: GlTooltipDirective,
  },
  mixins: [timeagoMixin, glFeatureFlagsMixin()],
  props: {
    states: {
      required: true,
      type: Array,
    },
    terraformAdmin: {
      required: false,
      type: Boolean,
      default: false,
    },
  },
  computed: {
    fields() {
      return [
        {
          key: 'name',
          label: s__('Terraform|Name'),
        },
        {
          key: 'pipeline',
          label: s__('Terraform|Pipeline'),
        },
        {
          key: 'updated',
          label: s__('Terraform|Details'),
        },
        {
          key: 'actions',
          label: s__('Terraform|Actions'),
          thClass: 'gl-w-12',
          tdClass: 'gl-text-right',
        },
      ];
    },
  },
  methods: {
    createdByUserName(item) {
      return item.latestVersion?.createdByUser?.name;
    },
    isPendingDeletion(item) {
      return Boolean(this.glFeatures.terraformStateDelayedDeletion && item.permanentDeletionAt);
    },
    loadingLockText(item) {
      return item.lockedAt ? s__('Terraform|Unlocking state') : s__('Terraform|Locking state');
    },
    lockedByUserName(item) {
      return item.lockedByUser?.name || s__('Terraform|Unknown User');
    },
    lockedByUserText(item) {
      return sprintf(s__('Terraform|Locked by %{user} %{timeAgo}'), {
        user: this.lockedByUserName(item),
        timeAgo: this.timeFormatted(item.lockedAt),
      });
    },
    pipelineDetailedStatus(item) {
      return item.latestVersion?.job?.detailedStatus;
    },
    pipelineID(item) {
      let id = item.latestVersion?.job?.pipeline?.id;

      if (id) {
        id = getIdFromGraphQLId(id);
      }

      return id;
    },
    pipelinePath(item) {
      return item.latestVersion?.job?.pipeline?.path;
    },
    updatedTime(item) {
      return item.latestVersion?.updatedAt || item.updatedAt;
    },
  },
};
</script>

<template>
  <gl-table
    :items="states"
    :fields="fields"
    data-testid="terraform-states-table"
    details-td-class="!gl-p-0"
    fixed
    stacked="md"
  >
    <template #cell(name)="{ item }">
      <div
        data-testid="terraform-states-table-name"
        class="gl-align-center gl-flex gl-justify-end gl-gap-3 @md/panel:gl-justify-start"
      >
        <p class="gl-m-0 gl-text-default">
          {{ item.name }}
        </p>

        <div v-if="item.loadingLock">
          <gl-loading-icon size="sm" class="gl-inline gl-pr-1" />
          {{ loadingLockText(item) }}
        </div>

        <div v-else-if="item.loadingRemove">
          <gl-loading-icon size="sm" class="gl-inline gl-pr-1" />
          {{ s__('Terraform|Removing') }}
        </div>

        <div v-else-if="item.loadingRestore">
          <gl-loading-icon size="sm" class="gl-inline gl-pr-1" />
          {{ s__('Terraform|Restoring') }}
        </div>

        <div v-else-if="isPendingDeletion(item)" :data-testid="`state-badge-${item.name}`">
          <gl-badge icon="remove">
            {{ s__('Terraform|Pending deletion') }}
          </gl-badge>
        </div>

        <div
          v-else-if="item.deletedAt"
          v-gl-tooltip.right
          :title="s__('Terraform|Deletion in progress')"
          :data-testid="`state-badge-${item.name}`"
        >
          <gl-badge icon="remove">
            {{ s__('Terraform|Removed') }}
          </gl-badge>
        </div>

        <div
          v-else-if="item.lockedAt"
          v-gl-tooltip.right
          :title="lockedByUserText(item)"
          :data-testid="`state-badge-${item.name}`"
        >
          <gl-badge icon="lock">
            {{ s__('Terraform|Locked') }}
          </gl-badge>
        </div>
      </div>
    </template>

    <template #cell(pipeline)="{ item }">
      <div
        data-testid="terraform-states-table-pipeline"
        class="gl-flex gl-items-center gl-justify-end gl-gap-3 @md/panel:gl-justify-start"
      >
        <gl-link v-if="pipelineID(item)" :href="pipelinePath(item)">
          #{{ pipelineID(item) }}
        </gl-link>

        <div v-if="pipelineDetailedStatus(item)" :id="`terraformJobStatusContainer${item.name}`">
          <ci-icon
            :id="`terraformJobStatus${item.name}`"
            :status="pipelineDetailedStatus(item)"
            show-status-text
          />

          <gl-tooltip
            :container="`terraformJobStatusContainer${item.name}`"
            :target="`terraformJobStatus${item.name}`"
            placement="right"
          >
            {{ s__('Terraform|Job status') }}
          </gl-tooltip>
        </div>
      </div>
    </template>

    <template #cell(updated)="{ item }">
      <p class="gl-m-0" data-testid="terraform-states-table-updated">
        <gl-sprintf :message="s__('Terraform|%{user} updated %{timeAgo}')">
          <template #user>
            <span v-if="item.latestVersion">
              {{ createdByUserName(item) }}
            </span>
          </template>

          <template #timeAgo>
            <time-ago-tooltip :time="updatedTime(item)" />
          </template>
        </gl-sprintf>
      </p>

      <p
        v-if="isPendingDeletion(item)"
        class="gl-m-0"
        data-testid="terraform-states-table-deletion-scheduled"
      >
        <gl-sprintf :message="s__('Terraform|Scheduled for deletion %{timeAgo}')">
          <template #timeAgo>
            <time-ago-tooltip :time="item.permanentDeletionAt" />
          </template>
        </gl-sprintf>
      </p>
    </template>

    <template #cell(actions)="{ item }">
      <state-actions :state="item" :terraform-admin="terraformAdmin" />
    </template>

    <template #row-details="row">
      <gl-alert
        data-testid="terraform-states-table-error"
        variant="danger"
        @dismiss="row.toggleDetails"
      >
        <span v-for="errorMessage in row.item.errorMessages" :key="errorMessage">
          {{ errorMessage }}
        </span>
      </gl-alert>
    </template>
  </gl-table>
</template>
