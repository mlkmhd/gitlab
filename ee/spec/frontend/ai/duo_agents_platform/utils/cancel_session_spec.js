import { cancelSession } from 'ee/ai/duo_agents_platform/utils/cancel_session';
import { cancelWorkflow } from 'ee/rest_api';
import { createAlert } from '~/alert';

jest.mock('ee/rest_api');
jest.mock('~/alert');

describe('cancelSession', () => {
  const workflowId = '42';

  describe('when the request succeeds', () => {
    beforeEach(() => {
      cancelWorkflow.mockResolvedValue({});
    });

    it('cancels the workflow and resolves to true', async () => {
      await expect(cancelSession(workflowId)).resolves.toBe(true);

      expect(cancelWorkflow).toHaveBeenCalledWith(workflowId);
    });

    it('shows a success alert', async () => {
      await cancelSession(workflowId);

      expect(createAlert).toHaveBeenCalledWith({
        message: 'Session has been canceled successfully.',
        variant: 'success',
      });
    });
  });

  describe('when the request fails', () => {
    it('resolves to false and shows the message from the response', async () => {
      const error = {
        response: { status: 422, data: { message: 'Session is already finished' } },
      };
      cancelWorkflow.mockRejectedValue(error);

      await expect(cancelSession(workflowId)).resolves.toBe(false);

      expect(createAlert).toHaveBeenCalledWith({
        message: 'Session is already finished',
        captureError: true,
        error,
        variant: 'danger',
      });
    });

    it('falls back to a generic message when the response has none', async () => {
      const error = new Error('Network error');
      cancelWorkflow.mockRejectedValue(error);

      await expect(cancelSession(workflowId)).resolves.toBe(false);

      expect(createAlert).toHaveBeenCalledWith({
        message: 'Failed to cancel session. Please try again.',
        captureError: true,
        error,
        variant: 'danger',
      });
    });
  });
});
