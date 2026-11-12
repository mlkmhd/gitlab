import mountGithubUpdates from 'ee/projects/settings/repository/github_updates';
import GithubUpdatesApp from 'ee/projects/settings/repository/github_updates/github_updates_app.vue';
import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';

jest.mock('~/lib/utils/vue3compat/init_vue_app');

describe('mountGithubUpdates', () => {
  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('returns null when the settings card is absent', () => {
    expect(mountGithubUpdates()).toBeNull();
    expect(initVueApp).not.toHaveBeenCalled();
  });

  it('mounts with the project-scoped endpoints and the raw project path', () => {
    document.body.innerHTML = `
      <div
        id="js-github-updates-settings"
        data-status-url="/group/project/-/github_updates/status"
        data-update-now-url="/group/project/-/github_updates/update_now"
        data-stop-url="/group/project/-/github_updates/stop"
        data-project-full-path="Group/Project"
        data-repository-name="octo-org/example"
        data-repository-url="https://github.com/octo-org/example"
        data-initial-status='{"state":"provider_canonical","data":{},"final_pass_incomplete":false}'
      ></div>
    `;

    mountGithubUpdates();

    expect(initVueApp).toHaveBeenCalledWith({
      el: document.getElementById('js-github-updates-settings'),
      name: 'GithubUpdatesSettingsRoot',
      component: GithubUpdatesApp,
      props: {
        statusUrl: '/group/project/-/github_updates/status',
        updateNowUrl: '/group/project/-/github_updates/update_now',
        stopUrl: '/group/project/-/github_updates/stop',
        projectFullPath: 'Group/Project',
        repositoryName: 'octo-org/example',
        repositoryUrl: 'https://github.com/octo-org/example',
        initialStatus: { state: 'provider_canonical', data: {}, final_pass_incomplete: false },
      },
    });
  });
});
