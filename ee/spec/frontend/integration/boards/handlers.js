import { join } from 'node:path';
import { cloneDeep } from 'lodash-es';
import { HttpResponse } from 'msw';
import {
  loadFixturesMap,
  mapStaticOperationHandlers,
} from 'ee_jest/integration/core/fixture_utils';

const FIXTURES_PATH = join('tmp/tests/frontend/fixtures-ee/graphql/boards/integration/');
const fixtures = loadFixturesMap(FIXTURES_PATH);

export const PROJECT_FULL_PATH = 'flightjs/Flight';
export const GROUP_FULL_PATH = 'flightjs';

// The group_label used when recording the fixtures; handleListsIssuesEE keys off this id
// to decide which created list needs an issue inside it.
export const GROUP_LABEL_ID = fixtures.boardLabelsGroup.data.group.labels.nodes.find(
  ({ title }) => title === 'Frontend',
)?.id;

// Operation names authored in PascalCase in the .graphql files don't match the camelCase
// `loadFixturesMap` derives from their (snake_case) fixture file names.
const OPERATION_NAME_OVERRIDES = {
  ProjectBoard: fixtures.projectBoard,
  GroupBoard: fixtures.groupBoard,
  ProjectBoardMilestones: fixtures.projectBoardMilestones,
  GroupBoardMilestones: fixtures.groupBoardMilestones,
};

const STATIC_OPERATION_HANDLERS = mapStaticOperationHandlers({
  ...fixtures,
  ...OPERATION_NAME_OVERRIDES,
});

function pickByBoardType(variables, { project, group }) {
  return variables.isProject ? project : group;
}

// `ListIssues` returns list metadata (not each list's issues, despite the query file's name);
// it only needs to differ by board type.
function handleListIssues({ variables }) {
  return pickByBoardType(variables, {
    project: fixtures.listIssuesProject,
    group: fixtures.listIssuesGroup,
  });
}

// The recorded per-list issues payloads are for a label list. Without this, answering them for
// the Open, Closed or a non-label list overwrites that list's `listType` in the Apollo cache.
const LIST_TYPE_BY_ID = Object.fromEntries([
  ...[fixtures.listIssuesProject.data.project, fixtures.listIssuesGroup.data.group].flatMap(
    ({ board }) => board.lists.nodes.map(({ id, listType }) => [id, listType]),
  ),
  ...[
    fixtures.boardListCreateMilestone,
    fixtures.boardListCreateAssignee,
    fixtures.boardListCreateIteration,
    fixtures.boardListCreateStatus,
  ].map(
    ({
      data: {
        boardListCreate: { list },
      },
    }) => [(list.milestone ?? list.assignee ?? list.iteration ?? list.status).id, list.listType],
  ),
]);

// Only the GROUP_LABEL_ID list gets the seeded issue. The fixtures are recorded on the
// project board, so a group board gets the same payload re-keyed onto its own group and board.
function handleListsIssuesEE({ variables }) {
  const base =
    variables.id === GROUP_LABEL_ID ? fixtures.listsIssuesWithIssue : fixtures.listsIssuesEmpty;
  const { project } = cloneDeep(base).data;
  const [list] = project.board.lists.nodes;
  list.id = variables.id;
  list.listType = LIST_TYPE_BY_ID[variables.id] ?? list.listType;

  if (variables.isProject) {
    return { data: { project } };
  }

  const { board: groupBoard, ...group } = fixtures.groupBoard.data.namespace;
  return {
    data: { group: { ...group, board: { ...project.board, id: groupBoard.id } } },
  };
}

function handleBoardLabels({ variables }) {
  return pickByBoardType(variables, {
    project: fixtures.boardLabelsProject,
    group: fixtures.boardLabelsGroup,
  });
}

// Declines other domains' paths, so they never get the "Board Owner" fixture by accident.
function handleUsersAutocomplete({ variables }) {
  if (![PROJECT_FULL_PATH, GROUP_FULL_PATH].includes(variables.fullPath)) return null;

  return pickByBoardType(variables, {
    project: fixtures.usersAutocompleteProject,
    group: fixtures.usersAutocompleteGroup,
  });
}

function handleSearchIterations({ variables }) {
  return pickByBoardType(variables, {
    project: fixtures.searchIterationsProject,
    group: fixtures.searchIterationsGroup,
  });
}

// The deferred per-list issue count/weight query. No spec asserts on these numbers, so a
// generic zeroed response keyed by the requested list id is enough to answer every list.
function handleListCount({ variables }) {
  return {
    data: {
      boardList: {
        id: variables.id,
        totalIssueWeight: '0',
        issuesCount: 0,
        __typename: 'BoardList',
      },
    },
  };
}

// The create-list fixture was recorded for "Frontend", so a list for any other label (for
// example "Backend") takes its title and color from the labels fixtures instead.
function labelById(labelId) {
  const projectLabels = fixtures.boardLabelsProject.data.project.labels.nodes;
  const groupLabels = fixtures.boardLabelsGroup.data.group.labels.nodes;

  return [...projectLabels, ...groupLabels].find(({ id }) => id === labelId);
}

// Picks the recorded create-list response matching whichever scope id the form submitted,
// then gives the new list its own id derived from that scope id, so two lists created in the
// same test (for example Backlog then Closed) never collide in the Apollo cache.
function handleCreateList({ variables }) {
  const { labelId, milestoneId, assigneeId, iterationId, statusId } = variables;
  const scopeId = labelId ?? milestoneId ?? assigneeId ?? iterationId ?? statusId;

  const FIXTURE_BY_SCOPE = [
    [labelId, fixtures.boardListCreateLabel],
    [milestoneId, fixtures.boardListCreateMilestone],
    [assigneeId, fixtures.boardListCreateAssignee],
    [iterationId, fixtures.boardListCreateIteration],
    [statusId, fixtures.boardListCreateStatus],
  ];
  const match = FIXTURE_BY_SCOPE.find(([scoped]) => scoped);
  if (!match) {
    throw new Error('createBoardListEE: no scope id (label, milestone, ...) in the variables');
  }
  const base = match[1];

  const response = cloneDeep(base);
  const { list } = response.data.boardListCreate;
  list.id = scopeId;

  if (labelId) {
    // The labels query's Label fragment doesn't select descriptionHtml, but
    // BoardListFragment's does, so the match is merged onto the recorded label
    // (which has the full field set) instead of replacing it outright.
    const label = labelById(labelId);
    list.label = { ...list.label, ...label };
    list.title = label.title;
  }

  return response;
}

const QUERY_OPERATION_HANDLERS = {
  ListIssues: handleListIssues,
  BoardListsEE: handleListsIssuesEE,
  BoardLabels: handleBoardLabels,
  usersAutocomplete: handleUsersAutocomplete,
  searchIterations: handleSearchIterations,
  BoardListCountEE: handleListCount,
};

const MUTATION_OPERATION_HANDLERS = {
  createBoardListEE: handleCreateList,
};

const OPERATION_HANDLERS = {
  ...STATIC_OPERATION_HANDLERS,
  ...QUERY_OPERATION_HANDLERS,
  ...MUTATION_OPERATION_HANDLERS,
};

export function handleBoardsOperation({ operationName, variables }) {
  const handler = OPERATION_HANDLERS[operationName];

  if (!handler) {
    return null;
  }

  const payload = handler({ variables });

  return payload ? HttpResponse.json(payload) : null;
}

export const boardsRestEndpoints = [];
