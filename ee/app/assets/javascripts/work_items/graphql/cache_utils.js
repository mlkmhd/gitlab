import { WIDGET_TYPE_WORKPLAN } from 'ee/work_items/constants';
import workItemAgentPlanQuery from './work_item_agent_plan.query.graphql';
import workItemAgentPlanContentQuery from './work_item_agent_plan_content.query.graphql';

export const buildAgentPlanWidget = ({
  hasContent,
  aiPlanningEnabled = true,
  readinessScore = null,
  generationStatus = null,
  openQuestionsCount = null,
  questions = null,
  updatedAt = null,
}) => ({
  type: WIDGET_TYPE_WORKPLAN,
  hasContent,
  updatedAt,
  aiPlanningEnabled,
  readinessScore,
  generationStatus,
  openQuestionsCount,
  questions,
  __typename: 'WorkItemWidgetAgentPlan',
});

export const buildAgentPlanContentWidget = ({ content, contentHtml }) => ({
  type: WIDGET_TYPE_WORKPLAN,
  content,
  contentHtml,
  __typename: 'WorkItemWidgetAgentPlan',
});

const buildWorkItemData = ({ workItemId, agentPlan, useWorkItemFeatures }) => ({
  __typename: 'WorkItem',
  id: workItemId,
  ...(useWorkItemFeatures
    ? { features: { __typename: 'WorkItemFeatures', agentPlan } }
    : { widgets: [agentPlan] }),
});

export const writeAgentPlanToCache = ({
  cache,
  workItemId,
  workItemIid,
  content,
  contentHtml,
  aiPlanningEnabled,
  readinessScore,
  generationStatus,
  openQuestionsCount,
  questions,
  updatedAt,
  useWorkItemFeatures,
  includeReadinessScore = false,
}) => {
  const agentPlan = buildAgentPlanWidget({
    hasContent: Boolean(content),
    updatedAt,
    aiPlanningEnabled,
    readinessScore,
    generationStatus,
    openQuestionsCount,
    questions,
  });

  cache.writeQuery({
    query: workItemAgentPlanQuery,
    variables: { id: workItemId, useWorkItemFeatures, includeReadinessScore },
    data: {
      workItem: {
        ...buildWorkItemData({ workItemId, agentPlan, useWorkItemFeatures }),
        iid: workItemIid,
      },
    },
  });

  cache.writeQuery({
    query: workItemAgentPlanContentQuery,
    variables: { id: workItemId },
    data: {
      workItem: buildWorkItemData({
        workItemId,
        agentPlan: buildAgentPlanContentWidget({ content, contentHtml }),
        useWorkItemFeatures: true,
      }),
    },
  });
};
