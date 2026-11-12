import { toISOStringWithoutMilliseconds } from '~/lib/utils/datetime_utility';
import { updateGlobalTodoCount } from '~/sidebar/utils';
import snoozeTodoMutation from './components/mutations/snooze_todo.mutation.graphql';
import {
  TODO_ACTION_TYPE_REVIEW_SUBMITTED,
  TODO_ACTION_TYPE_REVIEW_APPROVED,
  TODO_ACTION_TYPE_REVIEW_CHANGES_REQUESTED,
} from './constants';

// The decision values are sent only once the flag is on: during a rolling
// deploy an older web node rejects a query that names them.
export function reviewSubmittedActions() {
  return gon.features?.reviewDecisionTodoActions
    ? [
        TODO_ACTION_TYPE_REVIEW_SUBMITTED,
        TODO_ACTION_TYPE_REVIEW_APPROVED,
        TODO_ACTION_TYPE_REVIEW_CHANGES_REQUESTED,
      ]
    : [TODO_ACTION_TYPE_REVIEW_SUBMITTED];
}

export function snoozeTodo(apolloClient, todo, until) {
  /**
   * The API responds with the datetime in ISO 8601 format, without milliseconds. We therefore need
   * to strip the milliseconds client-side as well so that the optimistic response matches the
   * actual response. Mismatching date formats would invalidate the Apollo cache, in turn causing
   * the todos to be re-fetched unexpectedly.
   */
  const snoozedUntilISOString = toISOStringWithoutMilliseconds(until);

  return apolloClient.mutate({
    mutation: snoozeTodoMutation,
    variables: {
      todoId: todo.id,
      snoozeUntil: snoozedUntilISOString,
    },
    optimisticResponse: () => {
      updateGlobalTodoCount(-1);

      return {
        todoSnooze: {
          todo: {
            id: todo.id,
            snoozedUntil: snoozedUntilISOString,
            __typename: 'Todo',
          },
          errors: [],
        },
      };
    },
  });
}
