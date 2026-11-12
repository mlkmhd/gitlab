import { lazyCreateRapidDiffsApp } from '~/pages/projects/merge_requests/lazy_create_rapid_diffs_app';
import { createMergeRequestRapidDiffsApp } from 'ee_else_ce/rapid_diffs/merge_request_app';

jest.mock('ee_else_ce/rapid_diffs/merge_request_app', () => ({
  createMergeRequestRapidDiffsApp: jest.fn(),
}));

describe('lazyCreateRapidDiffsApp', () => {
  it('imports the merge request app and returns the created Rapid Diffs app', async () => {
    const app = {};
    createMergeRequestRapidDiffsApp.mockReturnValue(app);

    expect(await lazyCreateRapidDiffsApp()).toBe(app);
    expect(createMergeRequestRapidDiffsApp).toHaveBeenCalledTimes(1);
  });
});
