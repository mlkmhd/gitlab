import setWindowLocation from 'helpers/set_window_location_helper';
import {
  screen,
  within,
  getText,
  registerBootstrappedApp,
  waitForSetup,
} from 'ee_jest/integration/helpers/test_helpers';
import initBoardsApp from '~/boards/index';
import { PROJECT_FULL_PATH, GROUP_FULL_PATH } from './handlers';

// Jest's Vue 3 lane keeps `vuedraggable` on its Vue 2 build (see jest.config.base.js), which
// renders none of DraggableCompat's items, so no board list or card would ever show up.
jest.mock('vuedraggable', () =>
  process.env.VUE_VERSION === '3'
    ? {
        name: 'DraggableStub',
        props: {
          modelValue: { type: Array, required: false, default: () => [] },
          itemKey: { type: [String, Function], required: false, default: 'id' },
        },
        template: `<div>
          <slot name="header"></slot>
          <template v-for="(element, index) in modelValue">
            <slot name="item" :element="element" :index="index"></slot>
          </template>
          <slot name="footer"></slot>
        </div>`,
      }
    : jest.requireActual('vuedraggable'),
);

export const PROJECT_BOARD_ID = '1';
export const GROUP_BOARD_ID = '2';
// A fresh board always has the default Open and Closed lists.
export const DEFAULT_LIST_COUNT = 2;

// Matches the `false` string every other board_data boolean ships as; mountBoardApp's
// `overrides` turn specific ones on per test, mirroring what stub_licensed_features
// does for the Capybara spec this harness replaces.
const BASE_DATASET = {
  rootPath: '/',
  disabled: 'false',
  canUpdate: 'true',
  canAdminList: 'true',
  canAdminBoard: 'true',
  hasMissingBoards: 'false',
  multipleBoardsAvailable: 'false',
  timeTrackingLimitToHours: 'false',
  weights: '[]',
  wiCanCreateLabel: 'true',
  wiHasScopedLabelsFeature: 'false',
  hasCustomFieldsFeature: 'false',
  epicFeatureAvailable: 'false',
  iterationFeatureAvailable: 'false',
  weightFeatureAvailable: 'false',
  scopedLabels: 'false',
  milestoneListsAvailable: 'false',
  assigneeListsAvailable: 'false',
  iterationListsAvailable: 'false',
  healthStatusFeatureAvailable: 'false',
  scopedIssueBoardFeatureEnabled: 'false',
  subEpicsFeatureAvailable: 'false',
  hasLinkedItemsEpicsFeature: 'false',
  statusListsAvailable: 'false',
  workItemStatusAvailable: 'false',
};

/**
 * Boots the real `boards` page bundle, the same way `app/views/shared/boards/_show.html.haml`
 * does through `#js-issuable-board-app`'s dataset (see `BoardsHelper#board_data`).
 *
 * @param {Object} [options]
 * @param {'project'|'group'} [options.boardType] - which board to mount.
 * @param {Object} [options.dataset] - overrides merged onto the base dataset, for example
 *   `{ milestoneListsAvailable: 'true' }` to turn on a licensed list type.
 */
export function mountBoardApp({ boardType = 'project', dataset = {} } = {}) {
  const isGroup = boardType === 'group';
  const fullPath = isGroup ? GROUP_FULL_PATH : PROJECT_FULL_PATH;
  const boardId = isGroup ? GROUP_BOARD_ID : PROJECT_BOARD_ID;
  const basePath = isGroup ? `/groups/${fullPath}/-/boards` : `/${fullPath}/-/boards`;

  setWindowLocation(`${basePath}/${boardId}`);

  const el = document.createElement('div');
  el.id = 'js-issuable-board-app';
  Object.assign(el.dataset, {
    ...BASE_DATASET,
    boardId,
    fullPath,
    parent: boardType,
    wiGroupPath: isGroup ? fullPath : fullPath.split('/')[0],
    wiIssuesListPath: `/${fullPath}/-/issues`,
    wiReportAbusePath: '/-/abuse_reports/add_category',
    labelsManagePath: isGroup ? `/groups/${fullPath}/-/labels` : `/${fullPath}/-/labels`,
    releasesFetchPath: `/${fullPath}/-/releases.json`,
    boardBaseUrl: basePath,
    ...dataset,
  });
  document.body.appendChild(el);

  return registerBootstrappedApp(initBoardsApp());
}

export const findNewListButton = () => screen.queryByTestId('boards-create-list');
export const findValueDropdownToggle = () => document.getElementById('board-value-dropdown');
export const findAddToBoardButton = () => screen.queryByTestId('addNewColumnButton');
export const findBoardLists = () => screen.queryAllByTestId('board-list');
export const findListTypeRadio = (text) => screen.queryByRole('radio', { name: text });
export const findListboxLoader = () => screen.queryByTestId('listbox-search-loader');

// Boot is setup, so it waits on the setup budget for the New list button and the initial lists.
export const waitForBoard = (listCount) =>
  waitForSetup(() => {
    expect(findNewListButton()).not.toBeNull();
    expect(findBoardLists()).toHaveLength(listCount);
  });

// A fresh board always carries the default Open (backlog) and Closed lists ahead of
// whatever a test creates, so tests look up the list they created by its header text
// instead of a fragile position in `findBoardLists()`.
export const findListByHeaderText = (text) =>
  findBoardLists().find((list) => {
    const header = within(list).queryByTestId('board-list-header');
    return header && getText(header).includes(text);
  }) ?? null;
