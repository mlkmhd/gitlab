import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { createMockSubscription } from 'mock-apollo-client';
import { GlLink } from '@gitlab/ui';
import { mount } from '@vue/test-utils';
import createMockApollo from 'helpers/mock_apollo_helper';
import { extendedWrapper } from 'helpers/vue_test_utils_helper';
import CiIcon from '~/vue_shared/components/ci_icon/ci_icon.vue';
import JobsContainer from '~/ci/job_details/components/sidebar/jobs_container.vue';
import stageJobsUpdatedSubscription from '~/ci/job_details/graphql/subscriptions/stage_jobs_updated.subscription.graphql';

Vue.use(VueApollo);

describe('Jobs List block', () => {
  let wrapper;
  let mockSubscription;
  let subscriptionHandler;

  const retried = {
    status: {
      details_path: '/gitlab-org/gitlab-foss/pipelines/28029444',
      group: 'success',
      has_details: true,
      icon: 'status_success',
      label: 'passed',
      text: 'passed',
      tooltip: 'passed',
    },
    id: 233432756,
    tooltip: 'build - passed',
    retried: true,
  };

  const active = {
    name: 'test',
    status: {
      details_path: '/gitlab-org/gitlab-foss/pipelines/28029444',
      group: 'success',
      has_details: true,
      icon: 'status_success',
      label: 'passed',
      text: 'passed',
      tooltip: 'passed',
    },
    id: 2322756,
    tooltip: 'build - passed',
    active: true,
  };

  const job = {
    name: 'build',
    status: {
      details_path: '/gitlab-org/gitlab-foss/pipelines/28029444',
      group: 'success',
      has_details: true,
      icon: 'status_success',
      label: 'passed',
      text: 'passed',
      tooltip: 'passed',
    },
    id: 232153,
    tooltip: 'build - passed',
  };

  const findAllJobs = () => wrapper.findAllComponents(GlLink);
  const findJob = () => findAllJobs().at(0);
  const findCiIcon = () => wrapper.findComponent(CiIcon);

  const findArrowIcon = () => wrapper.findByTestId('arrow-right-icon');
  const findRetryIcon = () => wrapper.findByTestId('retry-icon');

  const createComponent = (props) => {
    const mockApollo = createMockApollo();

    subscriptionHandler = jest.fn(() => {
      mockSubscription = createMockSubscription();
      return mockSubscription;
    });
    mockApollo.defaultClient.setRequestHandler(stageJobsUpdatedSubscription, subscriptionHandler);

    wrapper = extendedWrapper(
      mount(JobsContainer, {
        apolloProvider: mockApollo,
        propsData: {
          ...props,
        },
      }),
    );
  };

  it('renders a list of jobs', () => {
    createComponent({
      jobs: [job, retried, active],
      jobId: 12313,
    });

    expect(findAllJobs()).toHaveLength(3);
  });

  it('renders the arrow right icon when job id matches `jobId`', () => {
    createComponent({
      jobs: [active],
      jobId: active.id,
    });

    expect(findArrowIcon().exists()).toBe(true);
  });

  it('does not render the arrow right icon when the job is not active', () => {
    createComponent({
      jobs: [job],
      jobId: active.id,
    });

    expect(findArrowIcon().exists()).toBe(false);
  });

  it('renders the job name when present', () => {
    createComponent({
      jobs: [job],
      jobId: active.id,
    });

    expect(findJob().text()).toBe(job.name);
    expect(findJob().text()).not.toContain(job.id.toString());
  });

  it('renders job id when job name is not available', () => {
    createComponent({
      jobs: [retried],
      jobId: active.id,
    });

    expect(findJob().text()).toBe(retried.id.toString());
  });

  it('links to the job page', () => {
    createComponent({
      jobs: [job],
      jobId: active.id,
    });

    expect(findJob().attributes('href')).toBe(job.status.details_path);
  });

  it('renders retry icon when job was retried', () => {
    createComponent({
      jobs: [retried],
      jobId: active.id,
    });

    expect(findRetryIcon().exists()).toBe(true);
  });

  it('does not render retry icon when job was not retried', () => {
    createComponent({
      jobs: [job],
      jobId: active.id,
    });

    expect(findRetryIcon().exists()).toBe(false);
  });

  describe('stage jobs subscription', () => {
    const stageJobUpdate = (id, overrides = {}) => ({
      data: {
        ciStageUpdated: {
          id: `gid://gitlab/Ci::Build/${id}`,
          detailedStatus: {
            id: `failed-${id}-${id}`,
            detailsPath: `/root/project/-/jobs/${id}`,
            group: 'failed',
            icon: 'status_failed',
            label: 'failed',
            text: 'Failed',
            tooltip: 'failed',
          },
          scheduled: false,
          scheduledAt: null,
          ...overrides,
        },
      },
    });

    it('does not subscribe without a stage id', () => {
      createComponent({ jobs: [job], jobId: active.id });

      expect(subscriptionHandler).not.toHaveBeenCalled();
    });

    describe('with a stage id', () => {
      beforeEach(() => {
        createComponent({ jobs: [job], jobId: active.id, stageId: 409 });
      });

      it('subscribes to updates for the stage', () => {
        expect(subscriptionHandler).toHaveBeenCalledWith({ stageId: 'gid://gitlab/Ci::Stage/409' });
      });

      it('updates the status of a job in the list', async () => {
        mockSubscription.next(stageJobUpdate(job.id));
        await nextTick();

        expect(findCiIcon().props('status')).toMatchObject({
          details_path: '/root/project/-/jobs/232153',
          icon: 'status_failed',
          text: 'Failed',
        });
        expect(findJob().attributes('href')).toBe('/root/project/-/jobs/232153');
        expect(wrapper.emitted('refetch-jobs')).toBeUndefined();
      });

      it('renders the refetched jobs after a subscription update', async () => {
        mockSubscription.next(stageJobUpdate(job.id));
        await nextTick();

        await wrapper.setProps({ jobs: [job, retried] });

        expect(findAllJobs()).toHaveLength(2);
        expect(findCiIcon().props('status')).toMatchObject({ icon: 'status_success' });
      });

      describe('when unknown jobs are updated', () => {
        beforeEach(() => {
          global.JEST_DEBOUNCE_THROTTLE_TIMEOUT = 1000;
        });

        afterEach(() => {
          global.JEST_DEBOUNCE_THROTTLE_TIMEOUT = undefined;
        });

        it('emits a single debounced refetch', async () => {
          mockSubscription.next(stageJobUpdate(1));
          mockSubscription.next(stageJobUpdate(2));
          await nextTick();

          expect(wrapper.emitted('refetch-jobs')).toBeUndefined();

          jest.runAllTimers();

          expect(wrapper.emitted('refetch-jobs')).toHaveLength(1);
        });

        it('cancels a pending refetch when destroyed', async () => {
          mockSubscription.next(stageJobUpdate(1));
          await nextTick();

          wrapper.destroy();
          jest.runAllTimers();

          expect(wrapper.emitted('refetch-jobs')).toBeUndefined();
        });
      });

      it('shows the remaining time when a job becomes scheduled', async () => {
        const scheduledAt = '2026-11-10T12:00:00Z';
        jest.spyOn(Date, 'now').mockReturnValue(new Date(scheduledAt).getTime() - 1337000);

        mockSubscription.next(
          stageJobUpdate(job.id, {
            detailedStatus: {
              id: `scheduled-${job.id}-${job.id}`,
              detailsPath: `/root/project/-/jobs/${job.id}`,
              group: 'scheduled',
              icon: 'status_scheduled',
              label: 'delayed',
              text: 'Delayed',
              tooltip: 'delayed manual action (%{remainingTime})',
            },
            scheduled: true,
            scheduledAt,
          }),
        );
        await nextTick();

        expect(findJob().attributes('title')).toBe('build - delayed manual action (00:22:17)');
      });

      it('re-subscribes when the stage changes', async () => {
        await wrapper.setProps({ stageId: 410 });

        expect(subscriptionHandler).toHaveBeenLastCalledWith({
          stageId: 'gid://gitlab/Ci::Stage/410',
        });
      });
    });
  });
});
