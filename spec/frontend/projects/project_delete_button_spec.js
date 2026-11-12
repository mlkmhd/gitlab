import { initVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import initProjectDeleteButton from '~/projects/project_delete_button';
import DeleteButton from '~/projects/components/shared/delete_button.vue';

jest.mock('~/lib/utils/vue3compat/init_vue_app');

describe('initProjectDeleteButton', () => {
  const datasetAttributes = `
    data-confirm-phrase="group/project"
    data-name-with-namespace="Group / Project"
    data-form-path="/group/project"
    data-is-fork="false"
    data-issues-count="1"
    data-merge-requests-count="2"
    data-forks-count="3"
    data-stars-count="4"
    data-button-text="Delete project"
    data-marked-for-deletion="false"
    data-permanent-deletion-date="2026-12-02"`;

  const mount = (extraAttributes = '') => {
    document.body.innerHTML = `<div id="js-project-delete-button" ${datasetAttributes} ${extraAttributes}></div>`;
    initProjectDeleteButton();
  };

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('does not mount without a mount point', () => {
    initProjectDeleteButton();

    expect(initVueApp).not.toHaveBeenCalled();
  });

  it('mounts DeleteButton with the parsed dataset and the default location', () => {
    mount();

    expect(initVueApp).toHaveBeenCalledWith(
      expect.objectContaining({
        el: document.getElementById('js-project-delete-button'),
        component: DeleteButton,
        provide: { triggerDeleteLocation: 'setting' },
        props: {
          confirmPhrase: 'group/project',
          nameWithNamespace: 'Group / Project',
          formPath: '/group/project',
          isFork: false,
          issuesCount: 1,
          mergeRequestsCount: 2,
          forksCount: 3,
          starsCount: 4,
          buttonText: 'Delete project',
          buttonCategory: undefined,
          markedForDeletion: false,
          permanentDeletionDate: '2026-12-02',
        },
      }),
    );
  });

  it('passes the button category and location from the dataset', () => {
    mount('data-button-category="tertiary" data-trigger-delete-location="no_repository"');

    expect(initVueApp).toHaveBeenCalledWith(
      expect.objectContaining({
        provide: { triggerDeleteLocation: 'no_repository' },
        props: expect.objectContaining({ buttonCategory: 'tertiary' }),
      }),
    );
  });
});
