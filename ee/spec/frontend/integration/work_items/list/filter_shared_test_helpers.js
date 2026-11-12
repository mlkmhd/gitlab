// Shared helper module (not a test file) for the work item list filter specs.
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import WorkItemsRoot from '~/work_items/components/app.vue';
import { createRouter } from '~/work_items/router';
import { apolloProvider } from '~/graphql_shared/issuable_client';
import {
  assignRouter,
  fullMount,
  getText,
  screen,
  waitForAssertion,
} from 'ee_jest/integration/helpers/test_helpers';
import { createPortalElement } from 'ee_jest/integration/work_items/test_helpers';
import { restWorkItemsResolver } from 'ee_else_ce/work_items/list/graphql/rest/work_items_rest_resolver';
import { activateVariant, setFeatureFlags } from 'ee_jest/integration/helpers/setup_utils';
import { capturedRequests } from 'ee_jest/integration/core/operation_helpers';
import { PROJECT_PATH, GROUP_PATH } from './filter_test_constants';

Vue.use(VueApollo);

// While work_item_rest_api_frontend_users exists, issuable_client.js only registers the REST
// resolver when the flag is on at import time, which is before a spec can set it.
apolloProvider.defaultClient.addResolvers({
  Query: { restWorkItems: restWorkItemsResolver },
});

/**
 * The setup every filter spec needs, registering its own hooks. Named `use*` to match
 * `useFakeDate` and the other helpers called bare inside a `describe`. Do not wrap this
 * in a `beforeAll`: the inner `beforeAll` would then be registered too late to run, and
 * the portal element would silently never be created. `jest.mock` stays per file
 * because it is hoisted.
 */
export function useFilterSpec() {
  beforeAll(() => {
    createPortalElement();
  });

  beforeEach(async () => {
    // Serve the open items the list asks for by default, as the GraphQL base fixture did.
    activateVariant('restWorkItemsList', 'OPENED');
    await apolloProvider.defaultClient.cache.reset();
  });
}

/**
 * Selects the generated fixture this test should be served by the REST list endpoint.
 *
 * @param {string} variant key from the fixture variants, e.g. 'WITH_LABEL'
 */
export function useListFixture(variant) {
  activateVariant('restWorkItemsList', variant);
}

/**
 * Returns the URL of the list's latest REST request. Two filters can return the same rows,
 * so a filter spec asserts on the request as well as on what is shown.
 */
export function lastListRequest() {
  const calls = capturedRequests.getWorkItemsRest;

  if (!calls?.length) {
    throw new Error('The work items list made no REST request.');
  }

  return new URL(calls.at(-1).url);
}

/**
 * Asserts the query params of the list's latest REST request. A param the list sends more
 * than once, such as `or[label_names][]`, takes an array of its values.
 *
 * @param {Object<string, string|string[]>} expectedParams
 */
export function expectListRequestParams(expectedParams) {
  const { searchParams } = lastListRequest();

  Object.entries(expectedParams).forEach(([key, value]) => {
    expect(searchParams.getAll(key)).toEqual([value].flat());
  });
}

const findList = () => document.querySelector('.issuable-list');

/**
 * Mounts the list on a filtered URL, the way a user arrives from a bookmarked
 * or shared link. The list reads its filter state from window.location.search.
 *
 * `routerPath` becomes Vue Router's history base, so the location that resolves
 * to the list route is base + path — hence the repeated segment.
 *
 * @param {string} search query string, including the leading `?`
 * @param {Object} [options]
 * @param {boolean} [options.isGroup] mount the group list instead of the project one
 * @param {string} [options.workItemType] fixed type, as only the service desk page sets it
 */
export function mountListWithQuery(search, { isGroup = false, workItemType } = {}) {
  const fullPath = isGroup ? GROUP_PATH : PROJECT_PATH;

  if (isGroup) activateVariant('workItemMetadataEE', 'GROUP');

  const router = assignRouter(createRouter, {
    fullPath,
    routerPath: 'work_items',
    routerLocation: `/work_items/work_items${search}`,
  });

  setFeatureFlags({ workItemRestApiFrontendUsers: true });

  fullMount(WorkItemsRoot, {
    router,
    propsData: {
      rootPageFullPath: fullPath,
    },
    apolloProvider,
    provide: {
      isGroup,
      fullPath,
      groupPath: GROUP_PATH,
      workItemType,
      isSignedIn: true,
      initialSort: 'created_desc',
      isServiceDeskSupported: false,
    },
  });
}

/**
 * Asserts the exact set of rows on screen.
 *
 * Matches on row title links rather than the list's text content: a row also
 * renders its parent's title as metadata, so a filtered-out title can still
 * appear in the list text.
 *
 * @param {string[]} expectedTitles
 */
export function expectListToShow(expectedTitles) {
  return waitForAssertion(() => {
    const titles = [...findList().querySelectorAll('[data-testid="issuable-title-link"]')].map(
      (el) => getText(el),
    );

    expect(titles.sort()).toEqual([...expectedTitles].sort());
  });
}

/**
 * Clears every applied filter the way the "Clear" button in the search bar does.
 */
export function clearFilters() {
  screen.queryByTestId('filtered-search-clear-button').click();
}

/**
 * Asserts the filter tokens rendered in the search bar.
 *
 * Covers the URL to token direction: these specs arrive on an already-filtered
 * URL, so the token has to reconstruct its own label, operator and value from
 * the query string. The deleted feature specs got this for free by picking the
 * token in the UI.
 *
 * @param {string[]} expectedTokens e.g. ['My reaction is thumbsup']
 */
export function expectTokensToShow(expectedTokens) {
  return waitForAssertion(() => {
    const tokens = screen
      .queryAllByTestId('filtered-search-token')
      .map((el) => getText(el).replace(/\s+/g, ' ').trim());

    expect(tokens.sort()).toEqual([...expectedTokens].sort());
  });
}
