import {
  clearFilters,
  mountListWithQuery,
  expectListToShow,
  useFilterSpec,
  useListFixture,
  expectListRequestParams,
  lastListRequest,
} from './filter_shared_test_helpers';
import { GROUP_LIST_PATH, PROJECT_LIST_PATH, WORK_ITEMS } from './filter_test_constants';

const CRM_ID = '1';
const SECOND_CRM_ID = '2';
const ORGANIZATION_ITEMS = [WORK_ITEMS.SECOND, WORK_ITEMS.BLOCKING];
const ALL_ITEMS = [
  WORK_ITEMS.AGENT_PLAN,
  WORK_ITEMS.LINKABLE,
  WORK_ITEMS.BLOCKING,
  WORK_ITEMS.CHILD_TASK,
  WORK_ITEMS.SECOND,
  WORK_ITEMS.DEPENDENT,
];

describe('Work items list - CRM filters', () => {
  useFilterSpec();

  it('filters to work items linked to the organization', async () => {
    useListFixture('WITH_CRM_ORGANIZATION');
    mountListWithQuery(`?crm_organization_id=${CRM_ID}`);

    await expectListToShow(ORGANIZATION_ITEMS);

    expect(lastListRequest().pathname).toBe(PROJECT_LIST_PATH);
    expectListRequestParams({ crm_organization_id: '1' });
  });

  it('filters to work items linked to the second organization', async () => {
    useListFixture('WITH_SECOND_CRM_ORGANIZATION');
    mountListWithQuery(`?crm_organization_id=${SECOND_CRM_ID}`);

    await expectListToShow([WORK_ITEMS.LINKABLE]);

    expect(lastListRequest().pathname).toBe(PROJECT_LIST_PATH);
    expectListRequestParams({ crm_organization_id: '2' });
  });

  it('filters to work items linked to the contact', async () => {
    useListFixture('WITH_CRM_CONTACT');
    mountListWithQuery(`?crm_contact_id=${CRM_ID}`);

    await expectListToShow([WORK_ITEMS.SECOND]);

    expect(lastListRequest().pathname).toBe(PROJECT_LIST_PATH);
    expectListRequestParams({ crm_contact_id: '1' });
  });

  it('filters to work items linked to the second contact', async () => {
    useListFixture('WITH_SECOND_CRM_CONTACT');
    mountListWithQuery(`?crm_contact_id=${SECOND_CRM_ID}`);

    await expectListToShow([WORK_ITEMS.BLOCKING]);

    expect(lastListRequest().pathname).toBe(PROJECT_LIST_PATH);
    expectListRequestParams({ crm_contact_id: '2' });
  });

  it('filters to work items linked to the organization on the group list', async () => {
    useListFixture('GROUP_WITH_CRM_ORGANIZATION');
    mountListWithQuery(`?crm_organization_id=${CRM_ID}`, { isGroup: true });

    await expectListToShow(ORGANIZATION_ITEMS);

    expect(lastListRequest().pathname).toBe(GROUP_LIST_PATH);
    expectListRequestParams({ crm_organization_id: '1' });
  });

  it('clears the filter and shows every work item again', async () => {
    useListFixture('WITH_CRM_ORGANIZATION');
    mountListWithQuery(`?crm_organization_id=${CRM_ID}`);
    await expectListToShow(ORGANIZATION_ITEMS);

    useListFixture('OPENED');
    clearFilters();

    await expectListToShow(ALL_ITEMS);

    expect(lastListRequest().searchParams.has('crm_organization_id')).toBe(false);
  });

  it('filters to work items linked to the contact on the group list', async () => {
    useListFixture('GROUP_WITH_CRM_CONTACT');
    mountListWithQuery(`?crm_contact_id=${CRM_ID}`, { isGroup: true });

    await expectListToShow([WORK_ITEMS.SECOND]);

    expect(lastListRequest().pathname).toBe(GROUP_LIST_PATH);
    expectListRequestParams({ crm_contact_id: '1' });
  });
});
