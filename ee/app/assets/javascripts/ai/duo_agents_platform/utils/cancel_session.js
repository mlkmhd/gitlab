import { createAlert } from '~/alert';
import { s__ } from '~/locale';
import { cancelWorkflow } from 'ee/rest_api';

/**
 * Cancels a Duo Agent Platform session and reports the outcome with an alert.
 *
 * Every place that cancels a session shows the same alerts, so they live here.
 * Resolves to `true` when the session was canceled and `false` when the request
 * failed, so callers only handle their own follow-up, such as refetching a query.
 *
 * Where the alerts are shown is tracked separately in
 * https://gitlab.com/gitlab-org/gitlab/-/work_items/629856.
 */
export const cancelSession = async (workflowId) => {
  try {
    await cancelWorkflow(workflowId);

    createAlert({
      message: s__('DuoAgentsPlatform|Session has been canceled successfully.'),
      variant: 'success',
    });

    return true;
  } catch (error) {
    createAlert({
      message:
        error.response?.data?.message ||
        s__('DuoAgentsPlatform|Failed to cancel session. Please try again.'),
      captureError: true,
      error,
      variant: 'danger',
    });

    return false;
  }
};
