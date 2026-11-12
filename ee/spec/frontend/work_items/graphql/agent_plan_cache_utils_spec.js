import {
  buildAgentPlanContentWidget,
  buildAgentPlanWidget,
  writeAgentPlanToCache,
} from 'ee/work_items/graphql/cache_utils';
import workItemAgentPlanQuery from 'ee/work_items/graphql/work_item_agent_plan.query.graphql';
import workItemAgentPlanContentQuery from 'ee/work_items/graphql/work_item_agent_plan_content.query.graphql';
import workItemAgentPlanReadinessFeedbackQuery from 'ee/work_items/graphql/work_item_agent_plan_readiness_feedback.query.graphql';
import { WIDGET_TYPE_WORKPLAN } from 'ee/work_items/constants';
import { createIssuableCache, expectCacheHit } from 'helpers/apollo_cache_helper';
import { findWorkplanWidget } from 'ee/work_items/utils';

const QUESTIONS = {
  __typename: 'WorkItemAgentPlanQuestionConnection',
  nodes: [
    { __typename: 'WorkItemAgentPlanQuestion', noteId: 'gid://gitlab/Note/1', answered: false },
  ],
};

const UPDATED_AT = '2026-01-02T12:00:00Z';

describe('agent plan cache utils', () => {
  const workItemId = 'gid://gitlab/WorkItem/1';
  const workItemIid = '1';

  describe('when the plan is cached', () => {
    const useWorkItemFeatures = true;

    describe('after feedback has been loaded', () => {
      let cache;
      const feedbackVariables = { id: workItemId, useWorkItemFeatures };
      const readFeedback = () =>
        findWorkplanWidget(
          cache.readQuery({
            query: workItemAgentPlanReadinessFeedbackQuery,
            variables: feedbackVariables,
          }).workItem,
        ).readinessScoreFeedbackHtml;

      beforeEach(() => {
        cache = createIssuableCache();
        writeAgentPlanToCache({
          cache,
          workItemId,
          workItemIid,
          content: 'a plan',
          contentHtml: '<p>a plan</p>',
          readinessScore: 72,
          useWorkItemFeatures,
          includeReadinessScore: true,
        });
        const agentPlan = {
          __typename: 'WorkItemWidgetAgentPlan',
          type: WIDGET_TYPE_WORKPLAN,
          readinessScoreFeedbackHtml: '<p>Add acceptance criteria</p>',
        };
        cache.writeQuery({
          query: workItemAgentPlanReadinessFeedbackQuery,
          variables: feedbackVariables,
          data: {
            workItem: {
              __typename: 'WorkItem',
              id: workItemId,
              features: { __typename: 'WorkItemFeatures', agentPlan },
            },
          },
        });
      });

      it('preserves feedback through a save', () => {
        writeAgentPlanToCache({
          cache,
          workItemId,
          workItemIid,
          content: 'edited plan',
          contentHtml: '<p>edited plan</p>',
          readinessScore: 72,
          useWorkItemFeatures,
          includeReadinessScore: true,
        });

        expectCacheHit(cache, {
          query: workItemAgentPlanReadinessFeedbackQuery,
          variables: feedbackVariables,
        });
        expect(readFeedback()).toBe('<p>Add acceptance criteria</p>');
        expect(
          findWorkplanWidget(
            cache.readQuery({
              query: workItemAgentPlanContentQuery,
              variables: { id: workItemId },
            }).workItem,
          ),
        ).toMatchObject({ content: 'edited plan' });
      });
    });

    describe('after a save', () => {
      let cache;
      const contentVariables = { id: workItemId };
      const readWidget = (query, variables) =>
        findWorkplanWidget(cache.readQuery({ query, variables }).workItem);

      beforeEach(() => {
        cache = createIssuableCache();
        writeAgentPlanToCache({
          cache,
          workItemId,
          workItemIid,
          content: 'a plan',
          contentHtml: '<p>a plan</p>',
          useWorkItemFeatures,
        });
      });

      it('marks the plan as having content', () => {
        expect(
          readWidget(workItemAgentPlanQuery, {
            id: workItemId,
            useWorkItemFeatures,
            includeReadinessScore: false,
          }),
        ).toMatchObject({ hasContent: true });
      });

      it('satisfies the content query without refetching', () => {
        expectCacheHit(cache, {
          query: workItemAgentPlanContentQuery,
          variables: contentVariables,
        });
        expect(readWidget(workItemAgentPlanContentQuery, contentVariables)).toMatchObject({
          content: 'a plan',
          contentHtml: '<p>a plan</p>',
        });
      });

      describe('when the plan is deleted', () => {
        beforeEach(() => {
          writeAgentPlanToCache({
            cache,
            workItemId,
            workItemIid,
            content: '',
            contentHtml: '',
            useWorkItemFeatures,
          });
        });

        it('marks the plan as having no content', () => {
          expect(
            readWidget(workItemAgentPlanQuery, {
              id: workItemId,
              useWorkItemFeatures,
              includeReadinessScore: false,
            }),
          ).toMatchObject({ hasContent: false });
          expect(readWidget(workItemAgentPlanContentQuery, contentVariables)).toMatchObject({
            content: '',
            contentHtml: '',
          });
        });
      });
    });

    describe.each([false, true])('with score gate %s', (includeReadinessScore) => {
      let cache;
      const variables = { id: workItemId, useWorkItemFeatures, includeReadinessScore };

      beforeEach(() => {
        cache = createIssuableCache();
        writeAgentPlanToCache({
          cache,
          workItemId,
          workItemIid,
          content: 'a plan',
          contentHtml: '<p>a plan</p>',
          readinessScore: 72,
          useWorkItemFeatures,
          includeReadinessScore,
        });
      });

      it('satisfies the query without refetching', () => {
        expectCacheHit(cache, { query: workItemAgentPlanQuery, variables });
      });

      it('never writes feedback, which has its own query', () => {
        const { workItem } = cache.readQuery({ query: workItemAgentPlanQuery, variables });
        expect(findWorkplanWidget(workItem)).not.toHaveProperty('readinessScoreFeedbackHtml');
      });
    });
  });

  describe('buildAgentPlanWidget', () => {
    it('builds the agent plan widget shape', () => {
      expect(
        buildAgentPlanWidget({
          hasContent: true,
          aiPlanningEnabled: true,
          readinessScore: 72,
          generationStatus: 'NEEDS_INPUT',
          openQuestionsCount: 2,
          questions: QUESTIONS,
          updatedAt: UPDATED_AT,
        }),
      ).toEqual({
        type: 'AGENT_PLAN',
        hasContent: true,
        updatedAt: UPDATED_AT,
        aiPlanningEnabled: true,
        readinessScore: 72,
        generationStatus: 'NEEDS_INPUT',
        openQuestionsCount: 2,
        questions: QUESTIONS,
        __typename: 'WorkItemWidgetAgentPlan',
      });
    });

    it('defaults the readiness score to null', () => {
      expect(buildAgentPlanWidget({ hasContent: true }).readinessScore).toBe(null);
    });

    it('defaults the generation status to null', () => {
      expect(buildAgentPlanWidget({ hasContent: true }).generationStatus).toBe(null);
    });

    it('defaults the open questions count to null', () => {
      expect(buildAgentPlanWidget({ hasContent: true }).openQuestionsCount).toBe(null);
    });

    it('defaults the questions to null', () => {
      expect(buildAgentPlanWidget({ hasContent: true }).questions).toBe(null);
    });

    it('defaults the update time to null', () => {
      expect(buildAgentPlanWidget({ hasContent: true })).toMatchObject({
        updatedAt: null,
      });
    });
  });

  describe('buildAgentPlanContentWidget', () => {
    it('builds the agent plan content widget shape', () => {
      expect(
        buildAgentPlanContentWidget({ content: 'some plan', contentHtml: '<p>some plan</p>' }),
      ).toEqual({
        type: 'AGENT_PLAN',
        content: 'some plan',
        contentHtml: '<p>some plan</p>',
        __typename: 'WorkItemWidgetAgentPlan',
      });
    });
  });

  describe('writeAgentPlanToCache', () => {
    let cache;

    beforeEach(() => {
      cache = { writeQuery: jest.fn() };
    });

    describe('when the plan is written', () => {
      beforeEach(() => {
        writeAgentPlanToCache({
          cache,
          workItemId,
          workItemIid,
          content: 'features plan',
          contentHtml: '<p>features plan</p>',
          aiPlanningEnabled: true,
          useWorkItemFeatures: true,
        });
      });

      it('writes the features shape', () => {
        expect(cache.writeQuery).toHaveBeenCalledWith({
          query: workItemAgentPlanQuery,
          variables: {
            id: workItemId,
            useWorkItemFeatures: true,
            includeReadinessScore: false,
          },
          data: {
            workItem: {
              __typename: 'WorkItem',
              id: workItemId,
              iid: workItemIid,
              features: {
                __typename: 'WorkItemFeatures',
                agentPlan: buildAgentPlanWidget({ hasContent: true, aiPlanningEnabled: true }),
              },
            },
          },
        });
        expect(cache.writeQuery).toHaveBeenCalledWith({
          query: workItemAgentPlanContentQuery,
          variables: { id: workItemId },
          data: {
            workItem: {
              __typename: 'WorkItem',
              id: workItemId,
              features: {
                __typename: 'WorkItemFeatures',
                agentPlan: buildAgentPlanContentWidget({
                  content: 'features plan',
                  contentHtml: '<p>features plan</p>',
                }),
              },
            },
          },
        });
      });
    });

    describe('when includeReadinessScore is true', () => {
      beforeEach(() => {
        writeAgentPlanToCache({
          cache,
          workItemId,
          workItemIid,
          content: 'scored plan',
          contentHtml: '<p>scored plan</p>',
          aiPlanningEnabled: true,
          readinessScore: 85,
          useWorkItemFeatures: true,
          includeReadinessScore: true,
        });
      });

      it('requests the readiness score in the written selection set', () => {
        expect(cache.writeQuery).toHaveBeenCalledWith(
          expect.objectContaining({
            variables: {
              id: workItemId,
              useWorkItemFeatures: true,
              includeReadinessScore: true,
            },
          }),
        );
      });

      it('preserves the readiness score alongside the content flag', () => {
        const { data } = cache.writeQuery.mock.calls[0][0];

        expect(data.workItem.features.agentPlan).toMatchObject({
          hasContent: true,
          readinessScore: 85,
        });
      });
    });

    describe('when the plan carries an open questions count', () => {
      beforeEach(() => {
        writeAgentPlanToCache({
          cache,
          workItemId,
          workItemIid,
          content: 'paused plan',
          contentHtml: '<p>paused plan</p>',
          generationStatus: 'NEEDS_INPUT',
          openQuestionsCount: 2,
          questions: QUESTIONS,
          useWorkItemFeatures: true,
        });
      });

      it('preserves the count and questions alongside the content flag', () => {
        const { data } = cache.writeQuery.mock.calls[0][0];

        expect(data.workItem.features.agentPlan).toMatchObject({
          hasContent: true,
          openQuestionsCount: 2,
          questions: QUESTIONS,
        });
      });
    });

    describe('when the plan carries an update time', () => {
      beforeEach(() => {
        writeAgentPlanToCache({
          cache,
          workItemId,
          workItemIid,
          content: 'dated plan',
          contentHtml: '<p>dated plan</p>',
          updatedAt: UPDATED_AT,
          useWorkItemFeatures: true,
        });
      });

      it('writes the update time alongside the content flag', () => {
        const { data } = cache.writeQuery.mock.calls[0][0];

        expect(data.workItem.features.agentPlan).toMatchObject({
          hasContent: true,
          updatedAt: UPDATED_AT,
        });
      });
    });
  });
});
