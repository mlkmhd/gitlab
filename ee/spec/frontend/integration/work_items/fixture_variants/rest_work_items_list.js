import restWorkItemsList from 'test_fixtures/graphql/work_items/integration/rest_work_items_list.json';
import restWorkItemsListOpened from 'test_fixtures/graphql/work_items/integration/rest_work_items_list_opened.json';
import restWorkItemsListClosed from 'test_fixtures/graphql/work_items/integration/rest_work_items_list_closed.json';
import restWorkItemsListAll from 'test_fixtures/graphql/work_items/integration/rest_work_items_list_all.json';
import restWorkItemsListStatusUnlicensed from 'test_fixtures/graphql/work_items/integration/rest_work_items_list_status_unlicensed.json';
import restWorkItemsListHealthStatusUnlicensed from 'test_fixtures/graphql/work_items/integration/rest_work_items_list_health_status_unlicensed.json';
import restWorkItemsListIterationUnlicensed from 'test_fixtures/graphql/work_items/integration/rest_work_items_list_iteration_unlicensed.json';
import { defineRestFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { listFilterVariants } from './list_filter_variants';

const filterVariants = listFilterVariants();

// Like setFixtureItemsCount for a REST list: copies the last row, with ids counting up from
// the highest recorded one, until the list holds `itemCount` rows.
const withItemsCount = (rows, itemCount) => {
  const highestId = Math.max(...rows.map(({ id }) => id));

  return Array.from({ length: itemCount }, (_, index) => {
    if (index < rows.length) return rows[index];

    const id = highestId + index - rows.length + 1;
    return { ...rows.at(-1), id, iid: id, global_id: `gid://gitlab/WorkItem/${id}` };
  });
};

const idByTitle = (title) => restWorkItemsListOpened.find((row) => row.title === title)?.id;

const UNLABELLED_ISSUE = idByTitle('Dependent test issue');
const LABELLED_ISSUE = idByTitle('Second test issue');
const LABELLED_TASK = idByTitle('Child task');

// The label rows already recorded on these items, keyed by title so the bulk edit variants
// below can move them onto other items.
const labelsByTitle = Object.fromEntries(
  restWorkItemsListOpened
    .flatMap((row) => row.features.labels?.labels ?? [])
    .map((label) => [label.title, label]),
);

// The open list as it looks right after a bulk label edit. `labelsByItemId` only names the
// items an edit changes; every other item keeps its recorded labels.
const withLabels = (labelsByItemId) =>
  restWorkItemsListOpened.map((row) => {
    const titles = labelsByItemId[row.id];
    if (!titles) return row;

    const { labels } = row.features;
    return {
      ...row,
      features: {
        ...row.features,
        labels: { ...labels, labels: titles.map((t) => labelsByTitle[t]) },
      },
    };
  });

export default defineRestFixtureVariants({
  query: 'restWorkItemsList',
  variants: {
    BASE: restWorkItemsList,
    EMPTY: [],
    // BASE is recorded without a state, so it includes closed items. The list defaults to open ones.
    OPENED: restWorkItemsListOpened,
    CLOSED: restWorkItemsListClosed,
    ALL: restWorkItemsListAll,
    // 51 rows: pages of 20, 20 and 11, or 50 and 1.
    MANY_PAGES: withItemsCount(restWorkItemsListOpened, 51),
    MANY_PAGES_GROUP: withItemsCount(filterVariants.GROUP, 51),
    MANY_PAGES_EPICS: withItemsCount(filterVariants.GROUP_EPICS, 51),
    // Post bulk-edit-label states, one per spec case. See bulk_edit_labels_spec.js.
    AFTER_ADD_DOING_TO_UNLABELLED: withLabels({ [UNLABELLED_ISSUE]: ['Doing'] }),
    AFTER_ADD_DOING_TO_TWO: withLabels({
      [UNLABELLED_ISSUE]: ['Doing'],
      [LABELLED_ISSUE]: ['To Do', 'Doing'],
    }),
    AFTER_ADD_TWO_TO_UNLABELLED: withLabels({ [UNLABELLED_ISSUE]: ['To Do', 'Doing'] }),
    AFTER_ADD_TODO_MIXED: withLabels({
      [UNLABELLED_ISSUE]: ['To Do'],
      [LABELLED_TASK]: ['Doing', 'To Do'],
    }),
    AFTER_REMOVE_TODO: withLabels({ [LABELLED_ISSUE]: [] }),
    AFTER_REMOVE_FROM_TWO: withLabels({ [LABELLED_ISSUE]: [], [LABELLED_TASK]: [] }),
    AFTER_ADD_AND_REMOVE: withLabels({
      [UNLABELLED_ISSUE]: ['Doing'],
      [LABELLED_ISSUE]: ['Doing'],
    }),
    // The list rows carry a status of their own, so an unlicensed namespace needs its own capture.
    STATUS_UNLICENSED: restWorkItemsListStatusUnlicensed,
    HEALTH_STATUS_UNLICENSED: restWorkItemsListHealthStatusUnlicensed,
    ITERATION_UNLICENSED: restWorkItemsListIterationUnlicensed,
    ...filterVariants,
  },
});
