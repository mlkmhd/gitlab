import { shallowMount } from '@vue/test-utils';
import { nextTick } from 'vue';
import MockAdapter from 'axios-mock-adapter';
import { extendedWrapper } from 'helpers/vue_test_utils_helper';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_OK } from '~/lib/utils/http_status';
import ArtifactsBlock from '~/ci/job_details/components/sidebar/artifacts_block.vue';
import ExternalLinksBlock from '~/ci/job_details/components/sidebar/external_links_block.vue';
import JobRetryForwardDeploymentModal from '~/ci/job_details/components/sidebar/job_retry_forward_deployment_modal.vue';
import JobsContainer from '~/ci/job_details/components/sidebar/jobs_container.vue';
import Sidebar from '~/ci/job_details/components/sidebar/sidebar.vue';
import StagesDropdown from '~/ci/job_details/components/sidebar/stages_dropdown.vue';
import createStore from '~/ci/job_details/store';
import job, { jobsInStage } from 'jest/ci/jobs_mock_data';

describe('Sidebar details block', () => {
  let mock;
  let store;
  let wrapper;

  const forwardDeploymentFailure = 'forward_deployment_failure';
  const findModal = () => wrapper.findComponent(JobRetryForwardDeploymentModal);
  const findArtifactsBlock = () => wrapper.findComponent(ArtifactsBlock);
  const findExternalLinksBlock = () => wrapper.findComponent(ExternalLinksBlock);
  const findJobStagesDropdown = () => wrapper.findComponent(StagesDropdown);
  const findJobsContainer = () => wrapper.findComponent(JobsContainer);

  const createWrapper = (props) => {
    store = createStore();

    store.state.job = job;

    wrapper = extendedWrapper(
      shallowMount(Sidebar, {
        propsData: {
          ...props,
        },

        store,
      }),
    );
  };

  beforeEach(() => {
    mock = new MockAdapter(axios);
    mock.onGet().reply(HTTP_STATUS_OK, {
      name: job.stage,
    });
  });

  describe('forward deployment failure', () => {
    describe('when the relevant data is missing', () => {
      it.each`
        retryPath         | failureReason
        ${null}           | ${null}
        ${''}             | ${''}
        ${job.retry_path} | ${''}
        ${''}             | ${forwardDeploymentFailure}
        ${job.retry_path} | ${'unmet_prerequisites'}
      `(
        'should not render the modal when path and failure are $retryPath, $failureReason',
        async ({ retryPath, failureReason }) => {
          createWrapper();
          await store.dispatch('receiveJobSuccess', {
            ...job,
            failure_reason: failureReason,
            retry_path: retryPath,
          });
          expect(findModal().exists()).toBe(false);
        },
      );
    });

    describe('when there is the relevant error', () => {
      beforeEach(() => {
        createWrapper();
        return store.dispatch('receiveJobSuccess', {
          ...job,
          failure_reason: forwardDeploymentFailure,
        });
      });

      it('should render the modal', () => {
        expect(findModal().exists()).toBe(true);
      });
    });
  });

  describe('stages dropdown', () => {
    beforeEach(() => {
      createWrapper();
      return store.dispatch('receiveJobSuccess', job);
    });

    describe('with stages', () => {
      it('renders value provided as selectedStage as selected', () => {
        expect(findJobStagesDropdown().props('selectedStage')).toBe(job.stage);
      });
    });

    describe('without jobs for stages', () => {
      it('does not render jobs container', () => {
        expect(findJobsContainer().exists()).toBe(false);
      });
    });

    describe('with jobs for stages', () => {
      beforeEach(() => {
        return store.dispatch('receiveJobsForStageSuccess', jobsInStage.latest_statuses);
      });

      it('renders list of jobs', () => {
        expect(findJobsContainer().exists()).toBe(true);
      });

      it('passes the selected stage id to the jobs container', async () => {
        store.state.stages = store.state.stages.map((stage) => ({ ...stage, id: 409 }));
        await nextTick();

        expect(findJobsContainer().props('stageId')).toBe(409);
      });
    });

    describe('jobs container events', () => {
      const stageArg = job.pipeline.details.stages.find((stage) => stage.name === job.stage);

      beforeEach(async () => {
        await store.dispatch('receiveJobsForStageSuccess', jobsInStage.latest_statuses);
        jest.spyOn(store, 'dispatch').mockImplementation();
      });

      it('refetches the jobs for the selected stage when requested', () => {
        findJobsContainer().vm.$emit('refetch-jobs');

        expect(store.dispatch).toHaveBeenCalledWith('fetchJobsForStage', stageArg);
      });
    });
  });

  describe('artifacts', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('artifacts are not shown if there are no properties other than locked', () => {
      expect(findArtifactsBlock().exists()).toBe(false);
    });

    it.each([[null], [undefined]])('artifacts are not shown if they are %s', async (value) => {
      store.state.job.artifact = value;

      await nextTick();

      expect(findArtifactsBlock().exists()).toBe(false);
    });

    it('artifacts are shown if present', async () => {
      store.state.job.artifact = {
        download_path: '/root/ci-project/-/jobs/1960/artifacts/download',
        browse_path: '/root/ci-project/-/jobs/1960/artifacts/browse',
        keep_path: '/root/ci-project/-/jobs/1960/artifacts/keep',
        expire_at: '2021-03-23T17:57:11.211Z',
        expired: false,
        locked: false,
      };

      await nextTick();

      expect(findArtifactsBlock().exists()).toBe(true);
    });
  });

  describe('external links', () => {
    beforeEach(() => {
      createWrapper();
    });

    it('external links block is not shown if there are no external links', () => {
      expect(findExternalLinksBlock().exists()).toBe(false);
    });

    it('external links block is shown if there are external links', async () => {
      store.state.job.annotations = [
        {
          name: 'external_links',
          data: [
            {
              external_link: {
                label: 'URL 1',
                url: 'https://url1.example.com/',
              },
            },
            {
              external_link: {
                label: 'URL 2',
                url: 'https://url2.example.com/',
              },
            },
          ],
        },
      ];

      await nextTick();

      expect(findExternalLinksBlock().exists()).toBe(true);
    });
  });
});
