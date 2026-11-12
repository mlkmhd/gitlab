import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import WorkItemAgentPresence from 'ee/work_items/components/work_item_agent_presence.vue';
import WorkItemCreatedUpdated from '~/work_items/components/work_item_created_updated.vue';
import workItemByIidQuery from '~/work_items/graphql/work_item_by_iid.query.graphql';
import { workItemByIidResponseFactory } from 'ee_jest/work_items/mock_data';

Vue.use(VueApollo);

describe('EE WorkItemCreatedUpdated', () => {
  let wrapper;

  const fullPath = '/some/project';
  const workItemIid = '1';

  const findWorkItemAgentPresence = () => wrapper.findComponent(WorkItemAgentPresence);

  beforeEach(async () => {
    wrapper = shallowMountExtended(WorkItemCreatedUpdated, {
      apolloProvider: createMockApollo([
        [workItemByIidQuery, jest.fn().mockResolvedValue(workItemByIidResponseFactory())],
      ]),
      propsData: { fullPath, workItemIid },
    });

    await waitForPromises();
  });

  it('renders the agent presence for the work item', () => {
    expect(findWorkItemAgentPresence().props()).toEqual({ fullPath, workItemIid });
  });
});
