import Vue from 'vue';
import VueApollo from 'vue-apollo';
import WorkItemsRoot from '~/work_items/components/app.vue';
import { createRouter } from '~/work_items/router';
import { apolloProvider } from '~/graphql_shared/issuable_client';
import { restWorkItemsResolver } from 'ee_else_ce/work_items/list/graphql/rest/work_items_rest_resolver';
import { setFeatureFlags, setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import {
  getWorkItemsCountOnly,
  hasWorkItems,
  restWorkItemsList,
} from 'ee_jest/integration/work_items/fixture_variants';
import { createPortalElement } from 'ee_jest/integration/work_items/test_helpers';
import {
  assignRouter,
  fullMount,
  getText,
  waitForAssertion,
} from 'ee_jest/integration/helpers/test_helpers';

Vue.use(VueApollo);

// While work_item_rest_api_frontend_users exists, issuable_client.js only registers the REST
// resolver when the flag is on at import time, which is before a spec can set it.
apolloProvider.defaultClient.addResolvers({
  Query: { restWorkItems: restWorkItemsResolver },
});

describe('Work items list - empty state', () => {
  const router = assignRouter(createRouter, {
    fullPath: 'gitlab-org/gitlab',
    routerPath: 'work_items',
  });

  beforeEach(() => {
    setQueryVariant(restWorkItemsList).empty();
    setQueryVariant(getWorkItemsCountOnly).empty();
    setQueryVariant(hasWorkItems).empty();
  });

  beforeAll(() => {
    createPortalElement();
  });

  beforeEach(async () => {
    await apolloProvider.defaultClient.cache.reset();
  });

  it('shows empty state message when there are no work items', async () => {
    setFeatureFlags({ workItemRestApiFrontendUsers: true });

    fullMount(WorkItemsRoot, {
      router,
      propsData: {
        rootPageFullPath: 'gitlab-org/gitlab',
      },
      apolloProvider,
      provide: {
        isGroup: false,
        fullPath: 'gitlab-org/gitlab',
        groupPath: 'gitlab-org',
        workItemType: undefined,
        isSignedIn: true,
        initialSort: 'created_desc',
        isServiceDeskSupported: false,
      },
    });

    await waitForAssertion(() => {
      expect(getText(document.body)).toContain('Track bugs, plan features');
    });
  });
});
