<script>
import { GlAlert, GlBadge, GlButton, GlLink, GlTableLite } from '@gitlab/ui';
import Visibility from 'visibilityjs';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_INTERNAL_SERVER_ERROR } from '~/lib/utils/http_status';
import { s__ } from '~/locale';
import Poll from '~/lib/utils/poll';
import ConfirmDangerModal from '~/vue_shared/components/confirm_danger/confirm_danger_modal.vue';
import TimeAgoTooltip from '~/vue_shared/components/time_ago_tooltip.vue';
import {
  AUTHORITY_PRESENTATIONS,
  AUTHORITY_STATES,
  POLLING_DELAY,
  POLLING_TIMEOUT,
  STOPPABLE_STATES,
} from './constants';
import { buildDataRows, isStatusInProgress } from './status_utils';

const toStatus = ({ state, data, final_pass_incomplete: finalPassIncomplete }) => ({
  state,
  data,
  finalPassIncomplete,
});

export default {
  name: 'GithubUpdatesApp',
  components: {
    ConfirmDangerModal,
    GlAlert,
    GlBadge,
    GlButton,
    GlLink,
    GlTableLite,
    TimeAgoTooltip,
  },
  provide() {
    // ConfirmDangerModal reads its copy by injection, not props.
    return {
      confirmDangerMessage: s__(
        'GithubUpdatesSettings|A GitHub change made while the final check is running might not be included.',
      ),
      confirmButtonText: s__('GithubUpdatesSettings|Stop updates'),
      additionalInformation: s__(
        "GithubUpdatesSettings|GitLab checks GitHub one last time before updates stop. This project stays read-only until the check finishes. After updates stop, you can make changes in GitLab. Later changes in GitHub are not copied here. This action does not change the GitHub repository. You can't turn these updates back on after you stop them.",
      ),
    };
  },
  props: {
    statusUrl: {
      type: String,
      required: true,
    },
    updateNowUrl: {
      type: String,
      required: false,
      default: '',
    },
    stopUrl: {
      type: String,
      required: false,
      default: '',
    },
    projectFullPath: {
      type: String,
      required: true,
    },
    repositoryName: {
      type: String,
      required: true,
    },
    repositoryUrl: {
      type: String,
      required: false,
      default: '',
    },
    initialStatus: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      status: toStatus(this.initialStatus),
      notice: null,
      isRequestingUpdate: false,
      isStopping: false,
      isStopModalVisible: false,
      isPolling: false,
      hasStatusError: false,
      isStatusStale: false,
      actionCount: 0,
    };
  },
  computed: {
    dataRows() {
      return buildDataRows(this.status.data, this.status.state);
    },
    presentation() {
      return (
        AUTHORITY_PRESENTATIONS[this.status.state] || {
          text: s__('GithubUpdatesSettings|GitHub updates need attention'),
          variant: 'warning',
          help: s__(
            'GithubUpdatesSettings|GitLab cannot change this setting until the GitHub update status is available.',
          ),
        }
      );
    },
    updatesOn() {
      return this.status.state !== AUTHORITY_STATES.GITLAB_CANONICAL;
    },
    stopButtonDisabled() {
      return (
        this.isStopping || this.isRequestingUpdate || !STOPPABLE_STATES.includes(this.status.state)
      );
    },
    stopButtonLoading() {
      return this.isStopping || this.status.state === AUTHORITY_STATES.CUTTING_OVER;
    },
    updateButtonDisabled() {
      return (
        this.status.state !== AUTHORITY_STATES.PROVIDER_CANONICAL ||
        this.isRequestingUpdate ||
        this.isStopping ||
        !this.dataRows.every(({ isUpdatable }) => isUpdatable)
      );
    },
  },
  mounted() {
    this.lastStatusChangeAt = Date.now();
    this.poll = new Poll({
      resource: {
        fetchStatus: () => {
          const { actionCount } = this;

          return axios.get(this.statusUrl).then((response) => ({ ...response, actionCount }));
        },
      },
      method: 'fetchStatus',
      // A poll sent before an action finished can carry the state from before it, so drop it.
      successCallback: ({ data, actionCount }) => {
        this.hasRetriedPoll = false;
        this.hasStatusError = false;
        if (actionCount === this.actionCount) this.applyStatus(data);
      },
      // Poll stops scheduling after a failed request, so retry once; the next action or tab change starts it again.
      errorCallback: (error) => {
        // A request that fails after polling was stopped (tab hidden, component destroyed) is not retried.
        if (!this.isPolling) return;

        if (!this.hasRetriedPoll) {
          this.hasRetriedPoll = true;
          this.poll.makeDelayedRequest(POLLING_DELAY);
          return;
        }

        this.isPolling = false;
        this.hasStatusError = true;
        Sentry.captureException(error);
      },
    });
    this.visibilityId = Visibility.change(() => this.restartPolling());
    this.syncPolling();
  },
  beforeDestroy() {
    this.isDestroyed = true;
    this.isPolling = false;
    this.poll.stop();
    Visibility.unbind(this.visibilityId);
  },
  methods: {
    // Only poll while there is progress to follow, so a settled project makes no requests.
    syncPolling() {
      // A poll that was in flight when the component was destroyed must not start polling again.
      if (this.isDestroyed) return;

      const inProgress = isStatusInProgress(this.status);
      const timedOut = Date.now() - this.lastStatusChangeAt >= POLLING_TIMEOUT;
      const shouldPoll = inProgress && !Visibility.hidden() && !timedOut;

      this.isStatusStale = inProgress && timedOut;

      if (!shouldPoll) {
        this.poll.stop();
        this.isPolling = false;
      } else if (!this.isPolling) {
        this.isPolling = true;
        this.hasRetriedPoll = false;
        this.poll.enable();
        this.poll.makeDelayedRequest(POLLING_DELAY);
      }
    },
    restartPolling() {
      this.lastStatusChangeAt = Date.now();
      this.syncPolling();
    },
    applyStatus(status) {
      const nextStatus = toStatus(status);

      if (JSON.stringify(nextStatus) !== JSON.stringify(this.status)) {
        this.lastStatusChangeAt = Date.now();
      }

      // The page-level banner and other settings were rendered while read-only, so a reload is needed.
      if (
        this.status.state !== AUTHORITY_STATES.GITLAB_CANONICAL &&
        nextStatus.state === AUTHORITY_STATES.GITLAB_CANONICAL
      ) {
        this.notice = {
          variant: 'success',
          message: s__(
            'GithubUpdatesSettings|GitHub updates stopped. Refresh the page to make changes in GitLab.',
          ),
        };
      }

      this.status = nextStatus;
      this.syncPolling();
    },
    applyActionStatus(status) {
      this.actionCount += 1;
      this.hasStatusError = false;
      this.lastStatusChangeAt = Date.now();
      this.applyStatus(status);
    },
    errorNotice(error, fallbackMessage) {
      return { variant: 'danger', message: error.response?.data?.message || fallbackMessage };
    },
    // A 4xx is an expected refusal that the notice explains, not a bug.
    reportActionError(error) {
      if (!error.response || error.response.status >= HTTP_STATUS_INTERNAL_SERVER_ERROR) {
        Sentry.captureException(error);
      }
    },
    async requestUpdate() {
      this.isRequestingUpdate = true;
      this.notice = null;

      try {
        const { data } = await axios.post(this.updateNowUrl);

        this.applyActionStatus(data);
        this.notice = { variant: 'info', message: data.message };
      } catch (error) {
        this.notice = this.errorNotice(
          error,
          s__("GithubUpdatesSettings|GitLab couldn't schedule an update from GitHub. Try again."),
        );
        this.reportActionError(error);
      } finally {
        this.isRequestingUpdate = false;
      }
    },
    openStopModal() {
      this.notice = null;
      this.isStopModalVisible = true;
    },
    async requestStop() {
      this.isStopping = true;
      this.notice = null;

      try {
        const { data } = await axios.post(this.stopUrl);

        this.applyActionStatus(data);
      } catch (error) {
        this.notice = this.errorNotice(
          error,
          s__(
            'GithubUpdatesSettings|GitLab could not start the final check. This project is still read-only. Try again.',
          ),
        );
        this.reportActionError(error);
      } finally {
        this.isStopping = false;
      }
    },
  },
  fields: [
    { key: 'label', label: s__('GithubUpdatesSettings|Data'), isRowHeader: true },
    { key: 'status', label: s__('GithubUpdatesSettings|Update status') },
    { key: 'lastUpdatedAt', label: s__('GithubUpdatesSettings|Last successful update') },
    { key: 'lastCheckedAt', label: s__('GithubUpdatesSettings|Last update attempt') },
  ],
};
</script>

<template>
  <div>
    <div class="gl-px-5 gl-pt-5">
      <gl-alert
        v-if="notice"
        :variant="notice.variant"
        class="gl-mb-5"
        data-testid="notice"
        @dismiss="notice = null"
      >
        {{ notice.message }}
      </gl-alert>

      <gl-alert
        v-if="hasStatusError"
        variant="danger"
        class="gl-mb-5"
        data-testid="status-error-alert"
        @dismiss="hasStatusError = false"
      >
        {{
          s__(
            "GithubUpdatesSettings|Couldn't load the GitHub updates status. Refresh the page to try again.",
          )
        }}
      </gl-alert>

      <gl-alert
        v-if="isStatusStale"
        variant="info"
        class="gl-mb-5"
        data-testid="status-stale-alert"
        @dismiss="isStatusStale = false"
      >
        {{
          s__(
            'GithubUpdatesSettings|This status might be out of date. Refresh the page to update it.',
          )
        }}
      </gl-alert>

      <gl-alert
        v-if="status.finalPassIncomplete"
        variant="warning"
        class="gl-mb-5"
        :dismissible="false"
        data-testid="final-pass-incomplete-alert"
      >
        {{
          s__(
            'GithubUpdatesSettings|GitHub updates stopped before the latest GitHub changes were imported. Recent changes on GitHub might be missing.',
          )
        }}
      </gl-alert>

      <div
        class="gl-mb-5 gl-flex gl-flex-col gl-gap-4 @md/panel:gl-flex-row @md/panel:gl-items-start @md/panel:gl-justify-between"
      >
        <dl class="gl-mb-0 gl-grow">
          <div class="gl-grid gl-grid-cols-1 gl-gap-2 gl-py-2 @md/panel:gl-grid-cols-3">
            <dt>{{ s__('GithubUpdatesSettings|GitHub repository') }}</dt>
            <dd class="gl-col-span-2 gl-m-0">
              <gl-link
                v-if="repositoryUrl"
                :href="repositoryUrl"
                target="_blank"
                show-external-icon
              >
                {{ repositoryName }}
              </gl-link>
              <template v-else>{{ repositoryName }}</template>
            </dd>
          </div>
          <div class="gl-grid gl-grid-cols-1 gl-gap-2 gl-py-2 @md/panel:gl-grid-cols-3">
            <dt>{{ s__('GithubUpdatesSettings|Direction') }}</dt>
            <dd class="gl-col-span-2 gl-m-0">
              {{ s__('GithubUpdatesSettings|From GitHub to GitLab') }}
            </dd>
          </div>
          <div class="gl-grid gl-grid-cols-1 gl-gap-2 gl-py-2 @md/panel:gl-grid-cols-3">
            <dt>{{ s__('GithubUpdatesSettings|Status') }}</dt>
            <dd class="gl-col-span-2 gl-m-0" aria-live="polite">
              <gl-badge :variant="presentation.variant" data-testid="overall-status">
                {{ presentation.text }}
              </gl-badge>
              <p class="gl-mb-0 gl-mt-2 gl-text-subtle" data-testid="status-help">
                {{ presentation.help }}
              </p>
            </dd>
          </div>
        </dl>
        <gl-button
          v-if="updatesOn && updateNowUrl"
          :disabled="updateButtonDisabled"
          :loading="isRequestingUpdate"
          data-testid="update-now"
          @click="requestUpdate"
        >
          {{ s__('GithubUpdatesSettings|Update now') }}
        </gl-button>
      </div>
    </div>

    <section aria-labelledby="github-updates-data-heading">
      <h3 id="github-updates-data-heading" class="gl-heading-4 gl-mb-3 gl-px-5">
        {{ s__('GithubUpdatesSettings|Updated data') }}
      </h3>
      <gl-table-lite
        :fields="$options.fields"
        :items="dataRows"
        stacked="md"
        class="gl-mb-0"
        data-testid="data-table"
      >
        <template #cell(status)="{ item }">
          <gl-badge :variant="item.statusVariant">{{ item.statusText }}</gl-badge>
          <p v-if="item.statusHelp" class="gl-mb-0 gl-mt-2 gl-text-subtle">
            {{ item.statusHelp }}
          </p>
        </template>
        <template #cell(lastUpdatedAt)="{ item }">
          <time-ago-tooltip v-if="item.lastUpdatedAt" :time="item.lastUpdatedAt" />
          <template v-else>{{ s__('GithubUpdatesSettings|Never') }}</template>
        </template>
        <template #cell(lastCheckedAt)="{ item }">
          <time-ago-tooltip v-if="item.lastCheckedAt" :time="item.lastCheckedAt" />
          <template v-else>{{ s__('GithubUpdatesSettings|Never') }}</template>
        </template>
      </gl-table-lite>
    </section>

    <section
      v-if="updatesOn && stopUrl"
      class="gl-border-t gl-flex gl-flex-col gl-gap-4 gl-p-5 @md/panel:gl-flex-row @md/panel:gl-items-start @md/panel:gl-justify-between"
      aria-labelledby="github-updates-stop-heading"
      data-testid="stop-section"
    >
      <div>
        <h3 id="github-updates-stop-heading" class="gl-heading-4 gl-mb-3">
          {{ s__('GithubUpdatesSettings|Stop GitHub updates') }}
        </h3>
        <p class="gl-mb-3">
          {{
            s__(
              'GithubUpdatesSettings|Stopping updates is permanent. To get updates from GitHub again, import the repository again.',
            )
          }}
        </p>
        <gl-button
          variant="danger"
          category="secondary"
          :disabled="stopButtonDisabled"
          :loading="stopButtonLoading"
          data-testid="stop-updates"
          @click="openStopModal"
        >
          {{ s__('GithubUpdatesSettings|Stop GitHub updates') }}
        </gl-button>
      </div>
    </section>

    <confirm-danger-modal
      v-if="stopUrl"
      :visible="isStopModalVisible"
      modal-id="stop-github-updates-modal"
      :modal-title="s__('GithubUpdatesSettings|Stop updates from GitHub?')"
      :phrase="projectFullPath"
      :confirm-loading="isStopping"
      @change="isStopModalVisible = $event"
      @confirm="requestStop"
    />
  </div>
</template>
