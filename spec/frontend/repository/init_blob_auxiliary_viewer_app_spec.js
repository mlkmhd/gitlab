import { createWrapper } from '@vue/test-utils';
import { unmountVueApp } from '~/lib/utils/vue3compat/init_vue_app';
import initBlobAuxiliaryViewerApp from '~/repository/init_blob_auxiliary_viewer_app';
import BlobAuxiliaryViewer from '~/repository/components/blob_auxiliary_viewer.vue';
import createRouter from '~/repository/router';

jest.mock('jh_else_ce/repository/components/tree_content.vue', () => ({
  name: 'TreeContent',
  template: '<div></div>',
}));
jest.mock('~/repository/components/blob_content_viewer.vue', () => ({
  name: 'BlobContentViewer',
  template: '<div></div>',
}));
jest.mock('~/repository/components/blob_auxiliary_viewer.vue', () => ({
  name: 'BlobAuxiliaryViewer',
  props: ['path', 'projectPath', 'currentRef', 'refType'],
  render: (h) => h('div'),
}));
jest.mock('~/repository/utils/dom');

describe('initBlobAuxiliaryViewerApp', () => {
  let app;
  let appPromise;
  let router;

  const serverHtml = '<div data-testid="server-auxiliary-viewer">MIT License</div>';

  const createComponent = async (path) => {
    router = createRouter('group/project', 'main', 'Project');
    await router.push(path).catch(() => {});
    appPromise = initBlobAuxiliaryViewerApp(router, { projectPath: 'group/project', ref: 'main' });
  };

  const navigateTo = async (path) => {
    await router.push(path);
    app = await appPromise;
  };

  const findServerViewer = () => document.querySelector('[data-testid="server-auxiliary-viewer"]');
  const findBlobAuxiliaryViewer = () => createWrapper(app).findComponent(BlobAuxiliaryViewer);

  afterEach(() => {
    if (app) unmountVueApp(app);
    app = null;
  });

  describe('without a mount point', () => {
    it('returns null instead of mounting', async () => {
      document.body.innerHTML = '';
      await createComponent('/');

      expect(appPromise).toBe(null);
    });
  });

  describe('with a server-rendered auxiliary viewer', () => {
    beforeEach(async () => {
      document.body.innerHTML = `<div id="js-blob-auxiliary-viewer">${serverHtml}</div>`;
      await createComponent('/-/blob/main/LICENSE');
    });

    it('keeps the server-rendered auxiliary viewer on page load', () => {
      expect(findServerViewer()).not.toBe(null);
    });

    describe('when only the query changes', () => {
      beforeEach(async () => {
        await router.push('/-/blob/main/LICENSE?ref_type=heads');
      });

      it('keeps the server-rendered auxiliary viewer', () => {
        expect(findServerViewer()).not.toBe(null);
      });
    });

    describe('when navigating to another blob', () => {
      beforeEach(async () => {
        await navigateTo('/-/blob/main/CHANGELOG?ref_type=heads');
      });

      it('replaces the server-rendered auxiliary viewer', () => {
        expect(findServerViewer()).toBe(null);
      });

      it('renders the auxiliary viewer for the new blob', () => {
        expect(findBlobAuxiliaryViewer().props()).toEqual({
          path: 'CHANGELOG',
          projectPath: 'group/project',
          currentRef: 'main',
          refType: 'heads',
        });
      });
    });

    describe('when navigating to a tree', () => {
      beforeEach(async () => {
        await navigateTo('/-/tree/main/lib');
      });

      it('removes the auxiliary viewer', () => {
        expect(findServerViewer()).toBe(null);
        expect(findBlobAuxiliaryViewer().exists()).toBe(false);
      });
    });
  });

  describe('on a tree page', () => {
    beforeEach(async () => {
      document.body.innerHTML = '<div id="js-blob-auxiliary-viewer"></div>';
      await createComponent('/-/tree/main/lib');
      await navigateTo('/-/blob/main/CHANGELOG');
    });

    it('renders the auxiliary viewer after navigating to a blob', () => {
      expect(findBlobAuxiliaryViewer().props('path')).toBe('CHANGELOG');
    });
  });
});
