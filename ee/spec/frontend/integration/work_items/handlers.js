import { join } from 'node:path';
import { HttpResponse } from 'msw';
import { cloneDeep, escape } from 'lodash-es';
import {
  buildAgentPlanWidgetMock,
  buildWorkplanFlowAvailabilityResponse,
} from 'ee_else_ce_jest/work_items/mock_data';
import {
  loadFixturesMap,
  mapStaticOperationHandlers,
} from 'ee_jest/integration/core/fixture_utils';
import { getActiveVariant } from 'ee_jest/integration/core/fixture_variant_schema';
import { buildUpdateResponse } from './fixtures_helper';
import './fixture_variants/get_work_items_count_only_ee';
import './fixture_variants/has_work_items';
import './fixture_variants/work_item_metadata';
import './fixture_variants/namespace_work_item_features';
import './fixture_variants/project_labels';
import './fixture_variants/project_milestones';
import './fixture_variants/work_item_agent_plan';
import './fixture_variants/work_item_notes_by_iid_features';
import './fixture_variants/work_item_linked_items_features';
import './fixture_variants/work_item_tree_query_features';
import './fixture_variants/create_work_item';
import './fixture_variants/get_work_item_notifications_by_id_features';
import './fixture_variants/get_duo_workflow_status_check';
import './fixture_variants/get_configured_flows';
import duoChatAvailableVariants from './fixture_variants/duo_chat_available';
import restWorkItemsListVariants from './fixture_variants/rest_work_items_list';

const FIXTURES_PATH = join('tmp/tests/frontend/fixtures-ee/graphql/work_items/integration/');

// The AI session widget is a Duo feature, so its fixture is generated alongside
// the other Duo ones, but the drawer is what queries it -- hence the handler
// lives here, where every work item spec already gets it.
const AI_PANEL_FIXTURES_PATH = join(
  'tmp/tests/frontend/fixtures-ee/graphql/ai_duo_panel/integration/',
);

const fixtures = loadFixturesMap(FIXTURES_PATH);
const aiPanelFixtures = loadFixturesMap(AI_PANEL_FIXTURES_PATH);

export const labelsResponse = fixtures.projectLabels;
export const autocompleteUsersResponse = fixtures.workspaceAutocompleteUsersSearch;
export const milestonesResponse = fixtures.projectMilestones;
export const baseUpdateResponse = fixtures.updateWorkItem;
export const workItemsSlimResponse = fixtures.getWorkItemsSlim;

const { id, name } = fixtures.getWorkItemsRest.data.namespace;

const GET_WORK_ITEMS_REST_GQL_MOCK = {
  data: {
    namespace: { id, fullPath: 'gitlab-org/gitlab', name, __typename: 'Namespace' },
  },
};

// The ids the list fixtures were recorded with, per fullPath the specs mount the list on.
const NAMESPACE_IDS_BY_PATH = {
  'gitlab-org/gitlab': fixtures.getWorkItemsSlim.data.namespace.id,
  'gitlab-org': fixtures.workItemMetadataGroup.data.namespace.id,
};

const currentUserTodosUpdateResponse = ({ workItemId, action }) => {
  const emptyTodos = { nodes: [], __typename: 'TodoConnection' };
  const todos =
    action === 'ADD'
      ? {
          nodes: [{ id: 'gid://gitlab/Todo/99', state: 'pending', __typename: 'Todo' }],
          __typename: 'TodoConnection',
        }
      : emptyTodos;

  return {
    data: {
      workItemUpdate: {
        __typename: 'WorkItemUpdatePayload',
        errors: [],
        workItem: {
          __typename: 'WorkItem',
          id: workItemId,
          features: {
            __typename: 'WorkItemFeatures',
            currentUserTodos: {
              __typename: 'WorkItemWidgetCurrentUserTodos',
              // The WorkItemCurrentUserTodos fragment selects `type`; without it the
              // write is incomplete and the widget reads a cache miss.
              type: 'CURRENT_USER_TODOS',
              currentUserTodos: todos,
            },
          },
        },
      },
    },
  };
};

export const GET_WORK_ITEMS_REST_ENDPOINT = {
  name: 'getWorkItemsRest',
  method: 'get',
  path: /\/api\/v4\/namespaces\/.*\/-\/work_items/,
  variants: restWorkItemsListVariants,
  headers: { 'x-next-cursor': '', 'x-prev-cursor': '' },
};

const OPERATION_NAME_OVERRIDES = {
  workItemMetadataEE: fixtures.workItemMetadata,
  EEgetWorkItemStateCounts: fixtures.getWorkItemStateCounts,
  getWorkItemsFullEE: fixtures.getWorkItemsFull,
  getWorkItemsSlimEE: fixtures.getWorkItemsSlim,
  getWorkItemsCountOnlyEE: fixtures.getWorkItemsCountOnly,
  getWorkItemsRestEE: GET_WORK_ITEMS_REST_GQL_MOCK,
};

// The token dropdowns these specs never open, so an empty project branch is enough.
function emptyProjectResponse(field) {
  const { id: projectId } = fixtures.projectLabels.data.namespace;

  return { data: { project: { id: projectId, __typename: 'Project', ...field } } };
}

// No __typename, or Apollo caches this as a real Group or Project and overwrites it.
function emptyCrmResponse(field) {
  const group = { id: 'gid://gitlab/Group/1', [field]: { nodes: [] } };

  return { data: { group, project: { id: 'gid://gitlab/Project/1', group } } };
}

// Creating a work item redirects to it, which re-fetches it by iid. Both sides are
// recorded captures of the same item, so the iid comes off the create fixture rather
// than being hard-coded here.
const CREATED_WORK_ITEM_IID = fixtures.createWorkItem.data.workItemCreate.workItem.iid;

// Each work item type carries its own allowed statuses, but a status update names only an id,
// so one flat list is enough to echo back the status the dropdown offered.
const ALLOWED_STATUSES = fixtures.namespaceWorkItemTypes.data.namespace.workItemTypes.nodes.flatMap(
  ({ widgetDefinitions = [] }) =>
    widgetDefinitions.find(({ type }) => type === 'STATUS')?.allowedStatuses ?? [],
);

// The assignees widget offers autocomplete users, and the update returns UserCore nodes, so
// this keeps the fields the two share.
const toUserCore = ({ id: userId, avatarUrl, name: userName, username, webUrl, webPath }) => ({
  id: userId,
  avatarUrl,
  name: userName,
  username,
  webUrl,
  webPath,
  __typename: 'UserCore',
});

const ASSIGNABLE_USERS = [
  ...fixtures.workspaceAutocompleteUsersSearch.data.namespace.users,
  fixtures.currentUser.data.currentUser,
].map((user) => toUserCore(user));

// Labels the create form has made, so the list it refetches afterwards includes them the way
// the server's would. Reset between tests via resetCreatedLabels().
let createdLabels = [];

export const resetCreatedLabels = () => {
  createdLabels = [];
};

const activeProjectLabels = () => {
  const response = cloneDeep(getActiveVariant('projectLabels') ?? fixtures.projectLabels);
  response.data.namespace.labels.nodes.push(...createdLabels);
  return response;
};

// Every label the dropdown can offer, so an update can echo back whichever of them it was
// asked to add.
const assignableLabels = () => activeProjectLabels().data.namespace.labels.nodes;

const STATIC_OPERATION_HANDLERS = mapStaticOperationHandlers({
  ...fixtures,
  ...OPERATION_NAME_OVERRIDES,
});

// The award-emoji body toggle resolves the cache from the server-returned
// `toggledOn`, so the handler tracks current-user reactions and flips per call.
// Reset between tests via resetAwardState().
let currentUserReactions = new Set();

export const resetAwardState = () => {
  currentUserReactions = new Set();
};

const awardEmojiMutationHandlers = {
  updateWorkItemAwardEmojiWidget: ({ variables }) => {
    const { awardableId, name: emojiName } = variables.input;
    const key = `${awardableId}:${emojiName}`;
    const toggledOn = !currentUserReactions.has(key);

    if (toggledOn) {
      currentUserReactions.add(key);
    } else {
      currentUserReactions.delete(key);
    }

    return {
      data: {
        awardEmojiToggle: { __typename: 'AwardEmojiTogglePayload', errors: [], toggledOn },
      },
    };
  },
  // Note reactions decide add-vs-remove and update the cache optimistically on the
  // client, so the acknowledgements are static.
  workItemNoteAddAwardEmoji: () => ({
    data: { awardEmojiAdd: { __typename: 'AwardEmojiAddPayload', errors: [] } },
  }),
  workItemNoteRemoveAwardEmoji: () => ({
    data: { awardEmojiRemove: { __typename: 'AwardEmojiRemovePayload', errors: [] } },
  }),
};

// These queries are recorded in the `features` shape under a `Features` suffix.
const featuresResponse = (operationName) => () => {
  const query = `${operationName}Features`;

  return { data: (getActiveVariant(query) ?? fixtures[query]).data };
};

const FEATURES_OPERATIONS = [
  'getWorkItemDesignList',
  'getWorkItemNotificationsById',
  'projectWorkItemAwardEmojis',
  'workItemCrmContacts',
  'workItemCurrentUserTodos',
  'workItemDevelopment',
  'workItemEmailParticipantsByIid',
  'workItemLinkedItems',
  'workItemLinkedResources',
  'workItemNotesByIid',
  'workItemParticipants',
  'workItemTimeTracking',
  'workItemTreeQuery',
  'workItemVulnerabilities',
];

const DYNAMIC_OPERATION_HANDLERS = {
  ...Object.fromEntries(FEATURES_OPERATIONS.map((op) => [op, featuresResponse(op)])),
  ...awardEmojiMutationHandlers,
  createWorkItemNote: () => fixtures.createWorkItemNote,

  // Resolves the requested thread from the active `features` notes variant.
  toggleWorkItemNoteResolveDiscussion: ({ variables }) => {
    const notes =
      getActiveVariant('workItemNotesByIidFeatures') ?? fixtures.workItemNotesByIidFeatures;
    const discussion = notes.data.namespace.workItem.features.notes.discussions.nodes.find(
      (node) => node.id === variables.id,
    );

    return {
      data: {
        discussionToggleResolve: {
          __typename: 'DiscussionToggleResolvePayload',
          discussion: {
            ...discussion,
            resolved: variables.resolve,
            resolvedBy: variables.resolve
              ? { __typename: 'UserCore', id: 'gid://gitlab/User/1', name: 'Administrator' }
              : null,
          },
          errors: [],
        },
      },
    };
  },

  // Resolves the requested decision from the decisions fixture, selecting the picked options.
  workItemDecisionResolve: ({ variables }) => {
    const { id: decisionId, selectedOptionIds = [] } = variables.input;
    const decision =
      fixtures.workItemDecisions.data.namespace.workItem.features.decisionLog.decisions.nodes.find(
        (node) => node.id === decisionId,
      );

    return {
      data: {
        workItemDecisionResolve: {
          __typename: 'WorkItemDecisionResolvePayload',
          decision: {
            ...decision,
            state: 'RESOLVED',
            resolvedAt: new Date(0).toISOString(),
            resolvedBy: decision.author,
            options: {
              ...decision.options,
              nodes: decision.options.nodes.map((option) => ({
                ...option,
                selected: selectedOptionIds.includes(option.id),
              })),
            },
          },
          errors: [],
        },
      },
    };
  },

  // Echoes the requested work item. Serving the fixture's own id verbatim would
  // write this response's `features` onto whichever work item happens to share
  // that id, and these suites read `features` back out of the Apollo cache.
  getDuoAgentSessionsOnWorkItem: ({ variables }) => {
    const fixture = cloneDeep(aiPanelFixtures.getDuoAgentSessionsOnWorkItem);
    fixture.data.workItem.id = variables?.id ?? fixture.data.workItem.id;

    return fixture;
  },

  duoChatAvailable: () => ({
    data: (getActiveVariant('duoChatAvailable') ?? duoChatAvailableVariants.BASE).data,
  }),

  // The iteration dropdown re-runs this query with the typed term. Only one search is
  // exercised ('plan'), so any non-empty term serves the filtered fixture; the empty
  // term is what the dropdown sends when it first opens.
  issueIterationsAliasedProject: ({ variables }) => ({
    data: variables.title ? fixtures.projectIterationsSearch.data : fixtures.projectIterations.data,
  }),

  projectLabels: () => ({ data: activeProjectLabels().data }),
  projectMilestones: () => ({
    data: (getActiveVariant('projectMilestones') ?? fixtures.projectMilestones).data,
  }),

  // Answers with the recorded clash when the title is one the dropdown already lists, and
  // with the recorded new label otherwise.
  createLabel: ({ variables }) => {
    const taken = activeProjectLabels().data.namespace.labels.nodes.some(
      ({ title }) => title === variables.title,
    );

    if (taken) {
      return { data: fixtures.createLabelDuplicateTitle.data };
    }

    createdLabels.push(fixtures.createLabel.data.labelCreate.label);
    return { data: fixtures.createLabel.data };
  },

  // `usersAutocomplete` is a shared operation name; other domains (for example boards)
  // register it too for their own fullPath. Falling through to `null` for a fullPath this
  // suite doesn't own lets that domain's handler answer instead of being shadowed here.
  usersAutocomplete: ({ variables }) =>
    ['gitlab-org/gitlab', 'gitlab-org'].includes(variables.fullPath)
      ? emptyProjectResponse({ autocompleteUsers: [] })
      : null,
  searchMilestones: () =>
    emptyProjectResponse({ milestones: { nodes: [], __typename: 'MilestoneConnection' } }),
  searchCrmOrganizations: () => emptyCrmResponse('organizations'),
  searchCrmContacts: () => emptyCrmResponse('contacts'),
  issueSuggestion: () =>
    emptyProjectResponse({ issues: { edges: [], __typename: 'IssueConnection' } }),

  namespaceWorkItem: ({ variables }) => {
    if (variables.iid === CREATED_WORK_ITEM_IID) {
      return { data: fixtures.namespaceWorkItemCreatedFeatures.data };
    }

    const activeVariant = getActiveVariant('namespaceWorkItemFeatures');
    return { data: (activeVariant ?? fixtures.namespaceWorkItemFeatures).data };
  },

  addLinkedItems: () => ({ data: fixtures.addLinkedItemsFeatures.data }),

  removeLinkedItems: () => ({ data: fixtures.removeLinkedItems.data }),

  // Uses the namespace id of the request's own fullPath so the write merges into the cached
  // namespace. Any other identity replaces `namespace(fullPath)`, and the list loses its `workItems`.
  savedViews: ({ variables }) => {
    const namespaceId =
      NAMESPACE_IDS_BY_PATH[variables.fullPath] ?? fixtures.getWorkItemsSlim.data.namespace.id;

    return {
      data: {
        namespace: {
          __typename: 'Namespace',
          id: namespaceId,
          savedViews: {
            nodes: [],
            pageInfo: {
              hasNextPage: false,
              hasPreviousPage: false,
              startCursor: null,
              endCursor: null,
            },
          },
        },
      },
    };
  },

  workItemUpdateCurrentUserTodos: ({ variables }) =>
    currentUserTodosUpdateResponse({
      workItemId: variables.input.id,
      action: variables.input.currentUserTodosWidget?.action,
    }),

  workItemSubscribe: ({ variables }) => {
    const notifications = {
      type: 'NOTIFICATIONS',
      subscribed: variables.input.subscribed,
      __typename: 'WorkItemWidgetNotifications',
    };

    return {
      data: {
        workItemSubscribe: {
          errors: [],
          workItem: {
            __typename: 'WorkItem',
            id: variables.input.id,
            features: { __typename: 'WorkItemFeatures', notifications },
          },
        },
      },
    };
  },

  updateWorkItemListUserPreference: ({ variables }) => ({
    data: {
      workItemUserPreferenceUpdate: {
        errors: [],
        userPreferences: {
          displaySettings: variables.displaySettings,
          sort: variables.sort || null,
        },
      },
    },
  }),

  updateWorkItemsDisplaySettings: ({ variables }) => ({
    data: {
      userPreferencesUpdate: {
        userPreferences: {
          workItemsDisplaySettings: variables.input?.workItemsDisplaySettings || {},
        },
      },
    },
  }),

  // The list refetch reads the post-edit state from the active restWorkItemsList variant,
  // set by the spec before calling the action that triggers this mutation.
  workItemBulkUpdate: ({ variables }) => ({
    data: {
      workItemBulkUpdate: {
        __typename: 'WorkItemBulkUpdatePayload',
        updatedWorkItemCount: variables.input.ids.length,
      },
    },
  }),

  workItemUpdate: ({ variables }) =>
    buildUpdateResponse({
      baseResponse: fixtures.updateWorkItem,
      milestoneFixture: fixtures.updateWorkItemMilestone,
      labelNodes: assignableLabels(),
      userNodes: ASSIGNABLE_USERS,
      iterationNodes: fixtures.projectIterations.data.namespace.attributes.nodes,
      statusNodes: ALLOWED_STATUSES,
      input: variables.input,
      featuresFixture:
        getActiveVariant('namespaceWorkItemFeatures') ?? fixtures.namespaceWorkItemFeatures,
    }),

  workItemAgentPlan: ({ variables }) => {
    const activeVariant = getActiveVariant('workItemAgentPlan');
    const content = activeVariant?.data?.content ?? '';
    const contentHtml = activeVariant?.data?.contentHtml ?? '';
    const aiPlanningEnabled = activeVariant?.data?.aiPlanningEnabled ?? true;
    const readinessScore = activeVariant?.data?.readinessScore ?? null;
    const agentPlan = buildAgentPlanWidgetMock({
      content,
      contentHtml,
      aiPlanningEnabled,
      readinessScore,
      generationStatus: activeVariant?.data?.generationStatus ?? null,
      openQuestionsCount: activeVariant?.data?.openQuestionsCount ?? null,
      questions: activeVariant?.data?.questions ?? null,
    });

    return {
      data: {
        workItem: {
          __typename: 'WorkItem',
          id: variables.id,
          iid: '1',
          features: { __typename: 'WorkItemFeatures', agentPlan },
        },
      },
    };
  },

  workItemAgentPlanContent: ({ variables }) => {
    const activeVariant = getActiveVariant('workItemAgentPlan');
    const agentPlan = {
      __typename: 'WorkItemWidgetAgentPlan',
      type: 'AGENT_PLAN',
      content: activeVariant?.data?.content ?? '',
      contentHtml: activeVariant?.data?.contentHtml ?? '',
    };

    return {
      data: {
        workItem: {
          __typename: 'WorkItem',
          id: variables.id,
          features: { __typename: 'WorkItemFeatures', agentPlan },
        },
      },
    };
  },

  workItemAgentPlanReadinessFeedback: ({ variables }) => {
    const agentPlan = {
      __typename: 'WorkItemWidgetAgentPlan',
      type: 'AGENT_PLAN',
      readinessScoreFeedbackHtml:
        getActiveVariant('workItemAgentPlan')?.data?.readinessScoreFeedbackHtml ?? null,
    };

    return {
      data: {
        workItem: {
          __typename: 'WorkItem',
          id: variables.id,
          features: { __typename: 'WorkItemFeatures', agentPlan },
        },
      },
    };
  },

  updateWorkItemAgentPlan: ({ variables }) => {
    const { content } = variables.input.agentPlanWidget;
    const agentPlan = buildAgentPlanWidgetMock({
      ...getActiveVariant('workItemAgentPlan')?.data,
      content,
      contentHtml: content ? `<p>${escape(content)}</p>` : '',
    });

    return {
      data: {
        workItemUpdate: {
          __typename: 'WorkItemUpdatePayload',
          errors: [],
          workItem: {
            __typename: 'WorkItem',
            id: variables.input.id,
            iid: '1',
            features: { __typename: 'WorkItemFeatures', agentPlan },
          },
        },
      },
    };
  },

  workplanFlowAvailability: () => buildWorkplanFlowAvailabilityResponse(),

  workItemGenerateWorkplan: () => ({
    data: {
      workItemGenerateWorkplan: {
        __typename: 'WorkItemGenerateWorkplanPayload',
        workflow: {
          __typename: 'DuoWorkflow',
          id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/1',
          status: 'RUNNING',
        },
        errors: [],
      },
    },
  }),

  workItemEnableAiPlanning: ({ variables }) => {
    const content = getActiveVariant('workItemAgentPlan')?.data?.content ?? '';
    const agentPlan = buildAgentPlanWidgetMock({ content, aiPlanningEnabled: true });

    return {
      data: {
        workItemEnableAiPlanning: {
          __typename: 'WorkItemEnableAiPlanningPayload',
          workItem: {
            __typename: 'WorkItem',
            id: variables.input.id,
            features: { __typename: 'WorkItemFeatures', agentPlan },
          },
          errors: [],
        },
      },
    };
  },
};

const OPERATION_HANDLERS = {
  ...STATIC_OPERATION_HANDLERS,
  ...DYNAMIC_OPERATION_HANDLERS,
};

export function handleWorkItemOperation({ operationName, variables }) {
  const handler = OPERATION_HANDLERS[operationName];

  if (!handler) {
    return null;
  }

  const payload = handler({ operationName, variables });

  // A handler can decline an operation it only partially owns (see `usersAutocomplete`),
  // so a null payload must fall through rather than resolve as a literal `null` response.
  if (!payload) {
    return null;
  }

  return HttpResponse.json(payload);
}

export const workItemRestEndpoints = [
  { method: 'get', path: /issues\/\d+\/can_create_branch/, response: fixtures.canCreateBranch },
  { method: 'get', path: /\/-\/autocomplete\/award_emojis/, response: [] },
  { method: 'get', path: /\/-\/releases\.json/, response: [] },
  GET_WORK_ITEMS_REST_ENDPOINT,
];
