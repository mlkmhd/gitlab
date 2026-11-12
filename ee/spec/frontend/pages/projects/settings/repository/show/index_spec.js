import mountGithubUpdates from 'ee/projects/settings/repository/github_updates';

jest.mock('ee/projects/settings/repository/github_updates');

describe('EE repository settings page', () => {
  it('mounts the GitHub updates settings', async () => {
    await import('ee/pages/projects/settings/repository/show');

    expect(mountGithubUpdates).toHaveBeenCalledTimes(1);
  });
});
