import { http, HttpResponse } from 'msw';
import { server } from 'ee_jest/integration/server';
import { captureRequest } from 'ee_jest/integration/core/operation_helpers';
import {
  getText,
  waitAndClick,
  waitForAssertion,
  within,
  screen,
} from 'ee_jest/integration/helpers/test_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import {
  getWorkItemsCountOnly,
  restWorkItemsList,
} from 'ee_jest/integration/work_items/fixture_variants';
import {
  expectListRequestParams,
  expectTokensToShow,
  lastListRequest,
  mountListWithQuery,
  useFilterSpec,
} from './filter_shared_test_helpers';
import { GROUP_LIST_PATH, PROJECT_LIST_PATH } from './filter_test_constants';

// REST keyset cursors carry the `_kd` direction marker, which the list checks for.
const encodeCursor = (offset) => btoa(JSON.stringify({ offset, _kd: 'n' }));
const offsetOf = (cursor) => JSON.parse(atob(cursor)).offset;

// The REST endpoint fixture serves one fixed page, so these specs page the variant themselves.
// Pagination only checks row ids, so the rows skip their features to keep rendering fast.
const servePagesOf = (variant) => {
  const items = restWorkItemsList[variant].map((row) => ({ ...row, features: {} }));

  server.use(
    http.get(/\/api\/v4\/namespaces\/.*\/-\/work_items/, ({ request }) => {
      captureRequest('getWorkItemsRest', request);

      const params = new URL(request.url).searchParams;
      const perPage = Number(params.get('per_page'));
      const offset = params.has('cursor') ? offsetOf(params.get('cursor')) : 0;
      const headers = {
        'x-next-cursor': offset + perPage < items.length ? encodeCursor(offset + perPage) : '',
        'x-prev-cursor': offset > 0 ? encodeCursor(Math.max(0, offset - perPage)) : '',
      };

      return HttpResponse.json(items.slice(offset, offset + perPage), { headers });
    }),
  );
};

// Read from the recorded epics so the URL filter and the fixture agree on the Epic type id.
const EPIC_TYPE_ID = String(restWorkItemsList.GROUP_EPICS[0].work_item_type.id);

// The epics list is the group list filtered to the Epic type, the URL group_epics_path
// redirects to.
const LISTS = [
  {
    list: 'project',
    variant: 'MANY_PAGES',
    isGroup: false,
    query: '',
    requestPath: PROJECT_LIST_PATH,
    requestParams: {},
  },
  {
    list: 'group',
    variant: 'MANY_PAGES_GROUP',
    isGroup: true,
    query: '',
    requestPath: GROUP_LIST_PATH,
    requestParams: {},
  },
  {
    list: 'epics',
    variant: 'MANY_PAGES_EPICS',
    isGroup: true,
    query: `type[]=${EPIC_TYPE_ID}`,
    requestPath: GROUP_LIST_PATH,
    requestParams: { 'work_item_type_ids[]': EPIC_TYPE_ID },
  },
];

const searchOf = (...params) => {
  const search = params.filter(Boolean).join('&');
  return search ? `?${search}` : '';
};

const findPagination = () => screen.queryByTestId('list-footer');
const findPrevButton = () => within(findPagination()).queryByTestId('prevButton');
const findNextButton = () => within(findPagination()).queryByTestId('nextButton');
// GlButton renders disabled pagination buttons with aria-disabled, not the disabled attribute.
const isDisabled = (button) => button.getAttribute('aria-disabled') === 'true';
// GlCollapsibleListbox toggles use the ARIA select-only combobox pattern, not the button role.
const findPageSizeToggle = (text) =>
  within(findPagination()).queryAllByRole('combobox', { name: text })[0] ?? null;

const findRowIds = () =>
  [...document.querySelectorAll('[data-testid="issuable-container"]')].map((row) =>
    row.id.replace('issuable_', ''),
  );

const expectRows = (ids) =>
  waitForAssertion(() => {
    expect(findRowIds()).toEqual(ids);
  });

describe('Work items list - pagination', () => {
  useFilterSpec();

  describe('when the URL filters by the Epic type', () => {
    beforeEach(() => {
      servePagesOf('MANY_PAGES_EPICS');
      setQueryVariant(getWorkItemsCountOnly).manyPages();
      mountListWithQuery(searchOf(`type[]=${EPIC_TYPE_ID}`), { isGroup: true });
    });

    it('shows the Type token', async () => {
      await expectTokensToShow(['Type is Epic', 'State is Open']);
    });
  });

  describe.each(LISTS)(
    'on the $list list',
    ({ variant, isGroup, query, requestPath, requestParams }) => {
      const allIds = restWorkItemsList[variant].map(({ id }) => String(id));

      beforeEach(() => {
        servePagesOf(variant);
        setQueryVariant(getWorkItemsCountOnly).manyPages();
      });

      describe('with the default page size', () => {
        beforeEach(async () => {
          mountListWithQuery(searchOf(query), { isGroup });
          await expectRows(allIds.slice(0, 20));
        });

        it('requests that list', () => {
          expect(lastListRequest().pathname).toBe(requestPath);
          expectListRequestParams(requestParams);
        });

        it('shows the first page with Previous disabled', () => {
          expect(isDisabled(findPrevButton())).toBe(true);
          expect(isDisabled(findNextButton())).toBe(false);
          expect(findPageSizeToggle('Show 20 items')).not.toBe(null);
        });

        it('shows the total count', () => {
          expect(getText(document.body)).toContain('51 items');
        });

        describe('when paginating to the next page', () => {
          beforeEach(async () => {
            await waitAndClick(findNextButton);
            await expectRows(allIds.slice(20, 40));
          });

          it('requests the page after the first one', () => {
            expect(offsetOf(lastListRequest().searchParams.get('cursor'))).toBe(20);
            expectListRequestParams({ per_page: '20' });
          });

          it('enables both buttons', () => {
            expect(isDisabled(findPrevButton())).toBe(false);
            expect(isDisabled(findNextButton())).toBe(false);
          });

          describe('when paginating to the last page', () => {
            beforeEach(async () => {
              await waitAndClick(findNextButton);
            });

            it('shows the remaining items with Next disabled', async () => {
              await expectRows(allIds.slice(40));

              expect(isDisabled(findNextButton())).toBe(true);
            });
          });

          describe('when going back', () => {
            beforeEach(async () => {
              await waitAndClick(findPrevButton);
            });

            it('shows the first page again', async () => {
              await expectRows(allIds.slice(0, 20));

              expect(isDisabled(findPrevButton())).toBe(true);
              expect(isDisabled(findNextButton())).toBe(false);
              expect(offsetOf(lastListRequest().searchParams.get('cursor'))).toBe(0);
              expectListRequestParams({ per_page: '20' });
            });
          });
        });

        describe('when choosing a larger page size', () => {
          beforeEach(async () => {
            await waitAndClick(() => findPageSizeToggle('Show 20 items'));
            await waitAndClick(() => screen.queryByRole('option', { name: 'Show 50 items' }));
          });

          // The chosen page size is persisted by local-storage-sync.
          afterEach(() => {
            localStorage.clear();
          });

          it('shows 50 items with Next enabled', async () => {
            await expectRows(allIds.slice(0, 50));

            expect(findRowIds()).toHaveLength(50);
            expect(isDisabled(findNextButton())).toBe(false);
            expect(isDisabled(findPrevButton())).toBe(true);
          });
        });
      });

      describe('when the URL sets first_page_size', () => {
        beforeEach(() => {
          mountListWithQuery(searchOf(query, 'first_page_size=50'), { isGroup });
        });

        it('shows that many items per page', async () => {
          await expectRows(allIds.slice(0, 50));

          expect(findRowIds()).toHaveLength(50);
          expectListRequestParams({ per_page: '50' });
        });
      });
    },
  );
});
