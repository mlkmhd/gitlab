<script>
import { debounce } from 'lodash-es';
import { getIdFromGraphQLId, convertToGraphQLId } from '~/graphql_shared/utils';
import { TYPENAME_CI_STAGE } from '~/graphql_shared/constants';
import stageJobsUpdatedSubscription from '../../graphql/subscriptions/stage_jobs_updated.subscription.graphql';
import DetailRow from './sidebar_detail_row.vue';
import JobContainerItem from './job_container_item.vue';

const REFETCH_DEBOUNCE_MS = 1000;

export default {
  name: 'JobsContainer',
  components: {
    DetailRow,
    JobContainerItem,
  },

  props: {
    jobs: {
      type: Array,
      required: true,
    },
    jobId: {
      type: Number,
      required: true,
    },
    stageId: {
      type: Number,
      required: false,
      default: null,
    },
  },
  emits: ['refetch-jobs'],
  data() {
    return {
      stageJobs: this.jobs,
    };
  },
  apollo: {
    $subscribe: {
      // eslint-disable-next-line @gitlab/vue-no-undef-apollo-properties
      stageJobUpdated: {
        query: stageJobsUpdatedSubscription,
        variables() {
          return { stageId: convertToGraphQLId(TYPENAME_CI_STAGE, this.stageId) };
        },
        skip() {
          return !this.stageId;
        },
        result({ data }) {
          const updatedJob = data?.ciStageUpdated;

          if (updatedJob) this.onStageJobUpdated(updatedJob);
        },
      },
    },
  },
  watch: {
    jobs(jobs) {
      this.stageJobs = jobs;
    },
  },
  created() {
    // A retry or a bulk transition can fire one event per job in the stage
    this.debouncedRefetch = debounce(() => this.$emit('refetch-jobs'), REFETCH_DEBOUNCE_MS);
  },
  beforeDestroy() {
    this.debouncedRefetch.cancel();
  },
  methods: {
    isJobActive(currentJobId) {
      return this.jobId === currentJobId;
    },
    onStageJobUpdated({ id, detailedStatus, scheduled, scheduledAt }) {
      const jobId = getIdFromGraphQLId(id);

      // Unknown ids are newly created jobs (for example, a retry), which need a full refetch
      if (!this.stageJobs.some((job) => job.id === jobId)) {
        this.debouncedRefetch();
        return;
      }

      this.stageJobs = this.stageJobs.map((job) =>
        job.id === jobId
          ? {
              ...job,
              scheduled,
              scheduled_at: scheduledAt,
              status: {
                ...job.status,
                details_path: detailedStatus.detailsPath,
                group: detailedStatus.group,
                icon: detailedStatus.icon,
                label: detailedStatus.label,
                text: detailedStatus.text,
                tooltip: detailedStatus.tooltip,
              },
            }
          : job,
      );
    },
  },
};
</script>
<template>
  <detail-row :title="__('Related jobs')" heading-tag="h2" class="builds-container">
    <job-container-item
      v-for="job in stageJobs"
      :key="job.id"
      :job="job"
      :is-active="isJobActive(job.id)"
    />
  </detail-row>
</template>
