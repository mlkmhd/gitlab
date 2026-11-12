<script>
import { GlButton, GlIcon, GlLink, GlSprintf } from '@gitlab/ui';
import { syncPullMirror } from 'ee/api/pull_mirror_api';
import { createAlert } from '~/alert';
import { __, s__ } from '~/locale';
import { captureException } from '~/sentry/sentry_browser_wrapper';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import { TAG_REF_TYPE } from '~/vue_shared/components/ref/constants';
import divergedFromUpstreamQuery from '../graphql/queries/diverged_from_upstream.query.graphql';

export default {
  name: 'CommitListMirrorStatus',
  components: {
    GlButton,
    GlIcon,
    GlLink,
    GlSprintf,
    TimeAgoTooltip,
  },
  inject: ['projectFullPath', 'projectId', 'pullMirror'],
  props: {
    currentRef: {
      type: String,
      required: true,
    },
    currentRefType: {
      type: String,
      required: false,
      default: '',
    },
  },
  data() {
    return {
      divergedFromUpstream: false,
      isUpdateScheduled: this.pullMirror.updateScheduled,
    };
  },
  apollo: {
    divergedFromUpstream: {
      query: divergedFromUpstreamQuery,
      variables() {
        return {
          projectPath: this.projectFullPath,
          ref: this.currentRef,
        };
      },
      skip() {
        return !this.canHaveDiverged;
      },
      update(data) {
        return Boolean(data.project?.repository?.divergedFromUpstream);
      },
      error(error) {
        this.divergedFromUpstream = false;
        captureException(error);
      },
    },
  },
  computed: {
    canHaveDiverged() {
      return (
        this.pullMirror.everUpdatedSuccessfully &&
        Boolean(this.currentRef) &&
        this.currentRefType !== TAG_REF_TYPE
      );
    },
    showDiverged() {
      return (
        this.canHaveDiverged &&
        !this.$apollo.queries.divergedFromUpstream.loading &&
        this.divergedFromUpstream
      );
    },
    isFailed() {
      return this.pullMirror.updateStatus === 'failed';
    },
    buttonText() {
      if (this.isUpdateScheduled) return __('Update scheduled…');
      if (this.pullMirror.updating) return __('Updating…');
      return __('Update now');
    },
    isButtonDisabled() {
      return (
        this.isUpdateScheduled ||
        this.pullMirror.updating ||
        this.pullMirror.updateStatus === 'read_only' ||
        !this.pullMirror.canUpdate
      );
    },
  },
  methods: {
    async updateNow() {
      this.isUpdateScheduled = true;

      try {
        // force resumes a mirror paused after too many failures, like the legacy Update now did
        await syncPullMirror(this.projectId, { force: true });
      } catch (error) {
        this.isUpdateScheduled = false;
        createAlert({ message: s__('Mirror|Failed to sync mirror.'), captureError: true, error });
      }
    },
  },
};
</script>

<template>
  <div
    class="gl-items-center gl-justify-between gl-gap-5 gl-rounded-base gl-border-1 gl-border-solid gl-border-default gl-bg-subtle gl-px-5 gl-py-4 @md/panel:gl-flex"
    data-testid="pull-mirror-status"
  >
    <div class="gl-flex gl-flex-col gl-gap-1">
      <p class="gl-mb-0">
        <gl-sprintf :message="__('This project is mirrored from %{link}.')">
          <template #link>
            <gl-link :href="pullMirror.url">{{ pullMirror.url }}</gl-link>
          </template>
        </gl-sprintf>
      </p>

      <p
        v-if="pullMirror.updateStatus === 'success'"
        class="gl-mb-0 gl-text-sm gl-text-subtle"
        data-testid="mirror-update-status"
      >
        <gl-sprintf :message="__('Pull mirroring updated %{time}.')">
          <template #time>
            <time-ago-tooltip :time="pullMirror.lastSuccessfulUpdateAt" />
          </template>
        </gl-sprintf>
      </p>

      <p
        v-else-if="pullMirror.updateStatus === 'read_only'"
        class="gl-mb-0 gl-text-sm gl-text-subtle"
        data-testid="mirror-update-status"
      >
        {{ __('Pull mirroring is disabled because the repository is set to read-only.') }}
      </p>

      <template v-else-if="isFailed">
        <p class="gl-mb-0 gl-text-sm" data-testid="mirror-update-status">
          <gl-icon name="warning-solid" variant="danger" />
          <gl-link v-if="pullMirror.canUpdate" :href="pullMirror.settingsPath">
            <gl-sprintf :message="__('Pull mirroring failed %{time}.')">
              <template #time>
                <time-ago-tooltip :time="pullMirror.lastUpdateAt" />
              </template>
            </gl-sprintf>
          </gl-link>
          <gl-sprintf v-else :message="__('Pull mirroring failed %{time}.')">
            <template #time>
              <time-ago-tooltip :time="pullMirror.lastUpdateAt" />
            </template>
          </gl-sprintf>
        </p>
        <p
          v-if="pullMirror.hardFailed"
          class="gl-mb-0 gl-text-sm gl-text-subtle"
          data-testid="mirror-hard-failed"
        >
          {{
            __(
              'Repository mirroring has been paused due to too many failed attempts. It can be resumed by a project maintainer or owner.',
            )
          }}
        </p>
        <p
          v-if="pullMirror.everUpdatedSuccessfully"
          class="gl-mb-0 gl-text-sm gl-text-subtle"
          data-testid="mirror-last-successful-update"
        >
          <gl-sprintf :message="__('Last successful update %{time}.')">
            <template #time>
              <time-ago-tooltip :time="pullMirror.lastSuccessfulUpdateAt" />
            </template>
          </gl-sprintf>
        </p>
      </template>

      <p v-if="showDiverged" class="gl-mb-0 gl-text-sm" data-testid="diverged-warning">
        <gl-icon name="warning-solid" variant="danger" />
        <span class="gl-font-bold">{{ __('This branch has diverged from upstream.') }}</span>
        {{
          s__(
            'Branches|The branch could not be updated automatically because it has diverged from its upstream counterpart.',
          )
        }}
      </p>
    </div>

    <gl-button
      class="gl-mt-4 gl-shrink-0 @md/panel:gl-mt-0"
      icon="retry"
      :disabled="isButtonDisabled"
      data-testid="update-now-button"
      @click="updateNow"
    >
      {{ buttonText }}
    </gl-button>
  </div>
</template>
