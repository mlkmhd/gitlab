import { TYPENAME_AI_DUO_WORKFLOW } from '~/graphql_shared/constants';
import { convertToGraphQLId } from '~/graphql_shared/utils';
import { fetchPolicies } from '~/lib/graphql';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import getAgentSessionLocation from 'ee/ai/duo_agents_platform/graphql/queries/get_agent_session_location.query.graphql';

export const sessionLocationQuery = (idKey) => ({
  query: getAgentSessionLocation,
  fetchPolicy: fetchPolicies.CACHE_ONLY,
  skip() {
    return !this[idKey];
  },
  variables() {
    return {
      workflowId: convertToGraphQLId(TYPENAME_AI_DUO_WORKFLOW, this[idKey]),
    };
  },
  update(data) {
    return data?.duoWorkflowWorkflows?.edges?.[0]?.node || {};
  },
  error(err) {
    Sentry.captureException(err);
  },
});
