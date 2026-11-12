import { cloneDeep } from 'lodash-es';
import namespaceWorkItemFeaturesBase from 'test_fixtures/graphql/work_items/integration/namespace_work_item_features.query.graphql.json';
import namespaceWorkItemFeaturesStatusUnlicensed from 'test_fixtures/graphql/work_items/integration/namespace_work_item_features_status_unlicensed.query.graphql.json';
import namespaceWorkItemFeaturesHealthStatusUnlicensed from 'test_fixtures/graphql/work_items/integration/namespace_work_item_features_health_status_unlicensed.query.graphql.json';
import namespaceWorkItemFeaturesIterationUnlicensed from 'test_fixtures/graphql/work_items/integration/namespace_work_item_features_iteration_unlicensed.query.graphql.json';
import namespaceWorkItemFeaturesNonMember from 'test_fixtures/graphql/work_items/integration/namespace_work_item_non_member_features.query.graphql.json';
import namespaceWorkItemFeaturesAnonymous from 'test_fixtures/graphql/work_items/integration/namespace_work_item_anonymous_features.query.graphql.json';
import { WIDGET_TYPE_AI_SESSION, WIDGET_TYPE_WORKPLAN } from '~/work_items/constants';
import { defineFixtureVariants } from 'ee_jest/integration/core/fixture_variant_schema';
import { setFixtureData } from 'ee_jest/integration/core/fixture_utils';
import { withoutEditPermissions } from './edit_permissions';

const withAgentPlanFeature = (fixture, { aiPlanningEnabled = true, hasContent = false } = {}) => {
  const clone = cloneDeep(fixture);
  clone.data.namespace.workItem.features.agentPlan = {
    __typename: 'WorkItemWidgetAgentPlan',
    type: WIDGET_TYPE_WORKPLAN,
    aiPlanningEnabled,
    hasContent,
  };
  return clone;
};

const withAiSessionFeature = (fixture) => {
  const clone = cloneDeep(fixture);
  clone.data.namespace.workItem.features.aiSession = {
    __typename: 'WorkItemWidgetAiSession',
    type: WIDGET_TYPE_AI_SESSION,
  };
  return clone;
};

const asClosed = (fixture) =>
  setFixtureData(fixture, { path: 'namespace.workItem.state' }, 'CLOSED');

const withoutDates = (fixture) => {
  const clone = cloneDeep(fixture);
  Object.assign(clone.data.namespace.workItem.features.startAndDueDate, {
    startDate: null,
    dueDate: null,
  });
  return clone;
};

const withoutAssignees = (fixture) => {
  const clone = cloneDeep(fixture);
  clone.data.namespace.workItem.features.assignees.assignees.nodes = [];
  return clone;
};

const namespaceWorkItemFeaturesAiSession = withAiSessionFeature(namespaceWorkItemFeaturesBase);
const namespaceWorkItemFeaturesAgentPlan = withAgentPlanFeature(namespaceWorkItemFeaturesBase, {
  hasContent: true,
});
const namespaceWorkItemFeaturesEmptyAgentPlan = withAgentPlanFeature(namespaceWorkItemFeaturesBase);
const namespaceWorkItemFeaturesAgentPlanAiDisabled = withAgentPlanFeature(
  namespaceWorkItemFeaturesBase,
  { aiPlanningEnabled: false },
);

export default defineFixtureVariants({
  query: 'namespaceWorkItemFeatures',
  variants: {
    BASE: namespaceWorkItemFeaturesBase,
    WITH_AI_SESSION: namespaceWorkItemFeaturesAiSession,
    WITH_AGENT_PLAN: namespaceWorkItemFeaturesAgentPlan,
    WITH_EMPTY_AGENT_PLAN: namespaceWorkItemFeaturesEmptyAgentPlan,
    WITH_EMPTY_AGENT_PLAN_NO_UPDATE: setFixtureData(
      namespaceWorkItemFeaturesEmptyAgentPlan,
      'updateWorkItem',
      false,
    ),
    WITH_AGENT_PLAN_CLOSED: asClosed(namespaceWorkItemFeaturesAgentPlan),
    WITH_EMPTY_AGENT_PLAN_CLOSED: asClosed(namespaceWorkItemFeaturesEmptyAgentPlan),
    WITH_EMPTY_AGENT_PLAN_CLOSED_NO_UPDATE: asClosed(
      setFixtureData(namespaceWorkItemFeaturesEmptyAgentPlan, 'updateWorkItem', false),
    ),
    WITH_AGENT_PLAN_AI_DISABLED: namespaceWorkItemFeaturesAgentPlanAiDisabled,
    WITH_AGENT_PLAN_AI_DISABLED_CLOSED: asClosed(namespaceWorkItemFeaturesAgentPlanAiDisabled),
    WITH_AGENT_PLAN_AI_DISABLED_NO_UPDATE: setFixtureData(
      namespaceWorkItemFeaturesAgentPlanAiDisabled,
      'updateWorkItem',
      false,
    ),
    READ_ONLY: withoutEditPermissions(namespaceWorkItemFeaturesBase),
    NO_DATES: withoutDates(namespaceWorkItemFeaturesBase),
    ARCHIVED: setFixtureData(namespaceWorkItemFeaturesBase, 'archived', true),
    LOCKED: setFixtureData(namespaceWorkItemFeaturesBase, 'discussionLocked', true),
    NO_ASSIGNEES: withoutAssignees(namespaceWorkItemFeaturesBase),
    // Captured from a namespace without the status licence, so `features.status` is null
    // the same way a real unlicensed instance's would be.
    STATUS_UNLICENSED: namespaceWorkItemFeaturesStatusUnlicensed,
    HEALTH_STATUS_UNLICENSED: namespaceWorkItemFeaturesHealthStatusUnlicensed,
    ITERATION_UNLICENSED: namespaceWorkItemFeaturesIterationUnlicensed,
    NON_MEMBER: namespaceWorkItemFeaturesNonMember,
    ANONYMOUS: namespaceWorkItemFeaturesAnonymous,
  },
});
