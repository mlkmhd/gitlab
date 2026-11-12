<script>
import { GlAvatar, GlButton, GlLink, GlSprintf } from '@gitlab/ui';
import { createAlert } from '~/alert';
import { getIdFromGraphQLId } from '~/graphql_shared/utils';
import { __, s__, sprintf } from '~/locale';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import setAutoMergeMutation from '../queries/mr_ai_overview_set_auto_merge.mutation.graphql';
import {
  AUTO_MERGE_STATUS,
  DEFAULT_AUTO_MERGE_STATUS,
  NON_OPEN_STATE,
  WHEN_CHECKS_PASS_STRATEGIES,
} from '../constants';
import { buildRows, getVerdict, isViewerBlockingReviewer } from '../utils';
import ReadinessRow from './readiness_row.vue';

export default {
  name: 'MergeReadiness',
  components: {
    GlAvatar,
    GlButton,
    GlLink,
    GlSprintf,
    ReadinessRow,
  },
  mixins: [glFeatureFlagsMixin()],
  inject: ['projectPath', 'iid'],
  props: {
    mergeRequest: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      isSettingAutoMerge: false,
    };
  },
  computed: {
    rows() {
      return buildRows(this.mergeRequest);
    },
    passingCount() {
      return this.rows.filter((row) => row.passing).length;
    },
    verdict() {
      return getVerdict(this.rows);
    },
    // Everything but an open merge request replaces the panel: the merge gate reports `not_open`
    // as a failing check, which would otherwise read as "not ready to merge" on a merged one.
    nonOpenState() {
      return NON_OPEN_STATE[this.mergeRequest.state] || null;
    },
    checksPassingText() {
      return sprintf(s__('AiOverview|%{passing} of %{total} checks passing'), {
        passing: this.passingCount,
        total: this.rows.length,
      });
    },
    isViewerBlockingReviewer() {
      return !this.nonOpenState && isViewerBlockingReviewer(this.mergeRequest, this.rows);
    },
    heroTitle() {
      if (this.nonOpenState) return this.nonOpenState.title;
      if (this.isViewerBlockingReviewer) return this.$options.i18n.yourReviewBlocks;

      return this.verdict.title;
    },
    autoMergeStatus() {
      const { autoMergeEnabled, autoMergeStrategy, mergeUser } = this.mergeRequest;

      if (!autoMergeEnabled) return null;
      // Deleting the user nullifies `merge_user_id`, leaving nobody to name.
      if (!mergeUser) return DEFAULT_AUTO_MERGE_STATUS;

      return AUTO_MERGE_STATUS[autoMergeStrategy] || DEFAULT_AUTO_MERGE_STATUS;
    },
    mergeUserId() {
      return getIdFromGraphQLId(this.mergeRequest.mergeUser.id);
    },
    // The backend offers no strategy to someone who cannot merge, so this doubles as the
    // permission check.
    autoMergeStrategy() {
      if (this.mergeRequest.autoMergeEnabled) return null;

      return (
        this.mergeRequest.availableAutoMergeStrategies?.find((strategy) =>
          WHEN_CHECKS_PASS_STRATEGIES.includes(strategy),
        ) || null
      );
    },
  },
  methods: {
    async setAutoMerge() {
      this.isSettingAutoMerge = true;
      try {
        const { data } = await this.$apollo.mutate({
          mutation: setAutoMergeMutation,
          variables: {
            projectPath: this.projectPath,
            iid: this.iid,
            sha: this.mergeRequest.diffHeadSha,
            strategy: this.autoMergeStrategy.toUpperCase(),
            // The mutation saves `squash` on the merge request and defaults it to false.
            squash: this.mergeRequest.squashOnMerge,
          },
        });
        const [message] = data.mergeRequestAccept.errors;
        if (message) throw new Error(message);
      } catch (error) {
        createAlert({ message: this.$options.i18n.autoMergeError, captureError: true, error });
      } finally {
        this.isSettingAutoMerge = false;
      }
    },
  },
  i18n: {
    yourReviewBlocks: s__('AiOverview|Your review is the blocker'),
    autoMergeError: __('Could not set auto-merge.'),
  },
};
</script>

<template>
  <div class="gl-flex gl-flex-col gl-gap-2">
    <div
      class="gl-rounded-lg gl-border-1 gl-border-solid gl-border-default gl-bg-default gl-px-4 gl-py-3"
    >
      <div class="gl-flex gl-flex-wrap gl-items-center gl-justify-between gl-gap-x-4 gl-gap-y-3">
        <h3 class="gl-m-0 gl-text-lg gl-font-bold">{{ heroTitle }}</h3>
        <div v-if="!nonOpenState" class="gl-flex gl-items-center gl-gap-4">
          <span class="gl-text-subtle">{{ checksPassingText }}</span>
          <div
            v-if="autoMergeStrategy"
            class="gl-relative gl-inline-flex"
            :class="{ 'mr-merge-button-shimmer': glFeatures.mergeButtonShimmer }"
            data-testid="set-auto-merge-wrapper"
          >
            <gl-button
              variant="confirm"
              size="medium"
              :loading="isSettingAutoMerge"
              data-testid="set-auto-merge-button"
              @click="setAutoMerge"
            >
              {{ __('Set to auto-merge') }}
            </gl-button>
          </div>
        </div>
      </div>
      <p v-if="nonOpenState" class="gl-mb-0 gl-mt-1 gl-text-subtle">
        {{ nonOpenState.summary }}
      </p>
      <p
        v-else-if="autoMergeStatus"
        class="gl-mb-0 gl-mt-1 gl-text-subtle"
        data-testid="auto-merge-status"
      >
        <gl-sprintf :message="autoMergeStatus">
          <template #merge_author>
            <gl-link
              :href="mergeRequest.mergeUser.webPath"
              :data-user-id="mergeUserId"
              :data-username="mergeRequest.mergeUser.username"
              class="js-user-link gl-inline-flex gl-items-center gl-gap-2 gl-align-bottom !gl-text-inherit hover:!gl-text-link"
            >
              <gl-avatar
                :src="mergeRequest.mergeUser.avatarUrl"
                :entity-name="mergeRequest.mergeUser.name"
                :size="16"
              />
              {{ mergeRequest.mergeUser.name }}
            </gl-link>
          </template>
        </gl-sprintf>
      </p>
    </div>

    <ul v-if="!nonOpenState" class="gl-m-0 gl-list-none gl-p-0">
      <readiness-row v-for="row in rows" :key="row.key" :row="row" />
    </ul>
  </div>
</template>
