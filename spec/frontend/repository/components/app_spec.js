import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import RepositoryApp from '~/repository/components/app.vue';
import FileTreeBrowser from '~/repository/file_tree_browser/file_tree_browser.vue';
import HeaderArea from '~/repository/components/header_area.vue';
import ForkInfo from '~/repository/components/fork_info.vue';
import LastCommit from '~/repository/components/last_commit.vue';
import BlobAuxiliaryViewer from '~/repository/components/blob_auxiliary_viewer.vue';
import { propsForkInfo } from '../mock_data';

describe('RepositoryApp', () => {
  let wrapper;

  const createComponent = ({ route = {}, props = {} } = {}) => {
    wrapper = shallowMountExtended(RepositoryApp, {
      propsData: {
        projectPath: 'group/project',
        projectId: '1',
        currentRef: 'main',
        refType: 'heads',
        historyLink: '/group/project/-/commits/main',
        ...props,
      },
      mocks: {
        $route: { name: 'treePath', path: '/', params: {}, query: {}, meta: {}, ...route },
      },
      stubs: { RouterView: { name: 'RouterView', render: (h) => h('div') } },
    });
  };

  const findFileTreeBrowser = () => wrapper.findComponent(FileTreeBrowser);
  const findHeaderArea = () => wrapper.findComponent(HeaderArea);
  const findForkInfo = () => wrapper.findComponent(ForkInfo);
  const findLastCommit = () => wrapper.findComponent(LastCommit);
  const findRouterView = () => wrapper.findComponent({ name: 'RouterView' });
  const findAuxiliaryViewer = () => wrapper.findComponent(BlobAuxiliaryViewer);

  it('renders the route content', () => {
    createComponent();

    expect(findRouterView().exists()).toBe(true);
  });

  it('passes the root props to the file tree browser and the header area', () => {
    createComponent();

    expect(findFileTreeBrowser().props()).toEqual({
      projectPath: 'group/project',
      currentRef: 'main',
      refType: 'heads',
    });
    expect(findHeaderArea().props()).toEqual({
      projectPath: 'group/project',
      projectId: '1',
      currentRef: 'main',
      refType: 'heads',
    });
  });

  it('hides the file tree browser on the project overview', () => {
    createComponent({ route: { name: 'projectRoot', meta: { refType: 'HEADS' } } });

    expect(findFileTreeBrowser().exists()).toBe(false);
    expect(findHeaderArea().exists()).toBe(true);
  });

  describe('fork info', () => {
    it('is not rendered without fork info', () => {
      createComponent();

      expect(findForkInfo().exists()).toBe(false);
    });

    it('is rendered with the fork info props', () => {
      createComponent({ props: { forkInfo: propsForkInfo } });

      expect(findForkInfo().props()).toMatchObject(propsForkInfo);
    });
  });

  describe('last commit', () => {
    it('passes the root path and history URL', () => {
      createComponent();

      expect(findLastCommit().props('currentPath')).toBe('/');
      expect(new URL(findLastCommit().props('historyUrl')).pathname).toBe(
        '/group/project/-/commits/main',
      );
    });

    it('passes the current path, ref type from the query, and history URL for that path', () => {
      createComponent({
        route: { params: { path: 'lib/utils' }, query: { ref_type: 'tags' } },
      });

      const historyUrl = new URL(findLastCommit().props('historyUrl'));

      expect(findLastCommit().props()).toMatchObject({
        currentPath: 'lib/utils',
        refType: 'tags',
      });
      expect(historyUrl.pathname).toBe('/group/project/-/commits/main/lib/utils');
      expect(historyUrl.searchParams.get('ref_type')).toBe('tags');
    });

    it('takes the ref type from the route meta first', () => {
      createComponent({
        route: { name: 'projectRoot', meta: { refType: 'HEADS' }, query: { ref_type: 'tags' } },
      });

      expect(findLastCommit().props('refType')).toBe('HEADS');
    });
  });

  describe('auxiliary viewer', () => {
    describe('on a blob route', () => {
      beforeEach(() => {
        createComponent({
          route: {
            name: 'blobPathDecoded',
            params: { path: 'LICENSE' },
            query: { ref_type: 'tags' },
          },
        });
      });

      it('passes the blob location', () => {
        expect(findAuxiliaryViewer().props()).toEqual({
          path: 'LICENSE',
          projectPath: 'group/project',
          currentRef: 'main',
          refType: 'tags',
        });
      });
    });

    describe('on a tree route', () => {
      beforeEach(() => {
        createComponent({ route: { name: 'treePath', params: { path: 'lib' } } });
      });

      it('is not rendered', () => {
        expect(findAuxiliaryViewer().exists()).toBe(false);
      });
    });

    describe('on the project overview', () => {
      beforeEach(() => {
        createComponent({ route: { name: 'projectRoot', meta: { refType: 'HEADS' } } });
      });

      it('is not rendered', () => {
        expect(findAuxiliaryViewer().exists()).toBe(false);
      });
    });
  });
});
