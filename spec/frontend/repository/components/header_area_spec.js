import Vue, { nextTick, reactive } from 'vue';
import { RouterLinkStub } from '@vue/test-utils';
import { createTestingPinia } from '@pinia/testing';
import { PiniaVuePlugin } from 'pinia';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import RefSelector from '~/vue_shared/components/ref/components/ref_selector.vue';
import HeaderArea from '~/repository/components/header_area.vue';
import Breadcrumbs from '~/repository/components/header_area/breadcrumbs.vue';
import AddToTree from '~/repository/components/header_area/add_to_tree.vue';
import FileIcon from '~/vue_shared/components/file_icon.vue';
import RepositoryOverflowMenu from '~/repository/components/header_area/repository_overflow_menu.vue';
import BlobControls from '~/repository/components/header_area/blob_controls.vue';
import Shortcuts from '~/behaviors/shortcuts/shortcuts';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import { headerAppInjected } from 'ee_else_ce_jest/repository/mock_data';
import CompactCodeDropdown from 'ee_else_ce/repository/components/code_dropdown/compact_code_dropdown.vue';
import WebIdeLink from 'ee_else_ce/vue_shared/components/web_ide_link.vue';
import { useFileTreeBrowserVisibility } from '~/repository/stores/file_tree_browser_visibility';
import FileTreeBrowserToggle from '~/repository/file_tree_browser/components/file_tree_browser_toggle.vue';
import { keyboardShortcutsDisabled } from '~/behaviors/shortcuts/shortcuts_disabled';
import { Mousetrap } from '~/lib/mousetrap';
import { keysFor, TOGGLE_FILE_TREE_BROWSER_VISIBILITY } from '~/behaviors/shortcuts/keybindings';
import { EVENT_EXPAND_FILE_TREE_BROWSER_ON_REPOSITORY_PAGE } from '~/repository/constants';
import { queryToObject } from '~/lib/utils/url_utility';

jest.mock('~/behaviors/shortcuts/shortcuts_disabled');
jest.mock('~/panel_breakpoint_instance');

const defaultMockRoute = {
  params: {
    path: 'index.js',
  },
  meta: {
    refType: '',
  },
  query: {
    ref_type: '',
  },
};

const mockRootRef = 'root-ref';
const toggleHotkeys = keysFor(TOGGLE_FILE_TREE_BROWSER_VISIBILITY);

Vue.use(PiniaVuePlugin);

describe('HeaderArea', () => {
  let wrapper;
  let mockRoute;
  let pinia;
  let fileTreeBrowserStore;

  const findBreadcrumbs = () => wrapper.findComponent(Breadcrumbs);
  const findFileTreeToggle = () => wrapper.findComponent(FileTreeBrowserToggle);
  const findRefSelector = () => wrapper.findComponent(RefSelector);
  const findFindFileButton = () => wrapper.findComponentByTestId('tree-find-file-control');
  const findWebIdeButton = () => wrapper.findByTestId('js-tree-web-ide-link');
  const findWebIdeLink = () => wrapper.findComponent(WebIdeLink);
  const findCompactCodeDropdown = () => wrapper.findComponent(CompactCodeDropdown);
  const findAddToTreeDropdown = () => wrapper.findComponent(AddToTree);
  const findAllAddToTreeDropdowns = () => wrapper.findAllComponents(AddToTree).wrappers;
  const findPageHeading = () => wrapper.findByTestId('repository-heading');
  const findFileIcon = () => wrapper.findComponent(FileIcon);
  const findRepositoryOverflowMenu = () => wrapper.findComponent(RepositoryOverflowMenu);
  const findBlobControls = () => wrapper.findComponent(BlobControls);
  const findTreeControls = () => wrapper.findByTestId('tree-controls-container');
  const { bindInternalEventDocument } = useMockInternalEventsTracking();

  const createComponent = ({
    props = {},
    route = { name: 'blobPathDecoded' },
    provided = {
      rootRef: mockRootRef,
    },
  } = {}) => {
    // HeaderArea binds a global (singleton) Mousetrap shortcut on mount.
    // Clear any existing bindings before mounting so a shortcut bound by a
    // previously created component doesn't leak into this one.
    Mousetrap.reset();

    // Observable so specs can navigate by mutating it, like the real router does
    mockRoute = reactive({
      ...defaultMockRoute,
      ...route,
      params: {
        ...defaultMockRoute.params,
        ...(route.params || {}),
      },
    });

    return shallowMountExtended(HeaderArea, {
      provide: {
        ...headerAppInjected,
        ...provided,
      },
      propsData: {
        projectPath: 'test/project',
        historyLink: '/history',
        refType: 'branch',
        projectId: '123',
        currentRef: 'main',
        ...props,
      },
      stubs: {
        RouterLink: RouterLinkStub,
        CompactCodeDropdown,
        WebIdeLink: stubComponent(WebIdeLink),
        LockDirectoryButton: true,
      },
      mocks: {
        $route: mockRoute,
      },
      pinia,
    });
  };

  beforeEach(() => {
    pinia = createTestingPinia({ stubActions: false });
    fileTreeBrowserStore = useFileTreeBrowserVisibility();
    wrapper = createComponent();
  });

  it('renders the component', () => {
    expect(wrapper.exists()).toBe(true);
  });

  describe('File tree browser toggle', () => {
    it.each`
      isProjectOverview | isExpanded | isPeekOn | expectedToggleVisible
      ${false}          | ${false}   | ${false} | ${true}
      ${false}          | ${true}    | ${false} | ${false}
      ${false}          | ${false}   | ${true}  | ${true}
      ${true}           | ${false}   | ${false} | ${false}
    `(
      'toggles file tree visibility',
      ({ isExpanded, isPeekOn, isProjectOverview, expectedToggleVisible }) => {
        pinia = createTestingPinia({ stubActions: false });
        fileTreeBrowserStore = useFileTreeBrowserVisibility();
        fileTreeBrowserStore.setFileTreeBrowserIsExpanded(isExpanded);
        fileTreeBrowserStore.setFileTreeBrowserIsPeekOn(isPeekOn);

        const route = isProjectOverview ? { name: 'projectRoot' } : { name: 'blobPathDecoded' };
        wrapper = createComponent({ route });

        expect(findFileTreeToggle().isVisible()).toBe(expectedToggleVisible);
      },
    );

    it('initializes file tree browser store on mount', () => {
      pinia = createTestingPinia({ stubActions: false });
      fileTreeBrowserStore = useFileTreeBrowserVisibility();
      jest.spyOn(fileTreeBrowserStore, 'initializeFileTreeBrowser');

      wrapper = createComponent({
        route: { name: 'treePathDecoded' },
      });

      expect(fileTreeBrowserStore.initializeFileTreeBrowser).toHaveBeenCalled();
    });

    describe('shortcuts', () => {
      describe('toggle visibility', () => {
        beforeEach(() => {
          wrapper = createComponent();
        });

        it('toggles visibility on shortcut trigger', () => {
          keyboardShortcutsDisabled.mockReturnValue(false);
          createComponent();
          Mousetrap.trigger(toggleHotkeys[0]);
          expect(useFileTreeBrowserVisibility().toggleFileTreeBrowserIsExpanded).toHaveBeenCalled();
        });

        it('triggers a tracking event when the toggle button is clicked', () => {
          const { trackEventSpy } = bindInternalEventDocument(wrapper.element);
          keyboardShortcutsDisabled.mockReturnValue(false);
          fileTreeBrowserStore.setFileTreeBrowserIsExpanded(false);

          createComponent();
          Mousetrap.trigger(toggleHotkeys[0]);

          expect(trackEventSpy).toHaveBeenCalledWith(
            EVENT_EXPAND_FILE_TREE_BROWSER_ON_REPOSITORY_PAGE,
            { label: 'shortcut' },
            undefined,
          );

          Mousetrap.trigger(toggleHotkeys[0]);
          expect(trackEventSpy).toHaveBeenCalledWith(
            'collapse_file_tree_browser_on_repository_page',
            { label: 'shortcut' },
            undefined,
          );
        });

        it('does not toggle visibility on shortcut trigger after component is destroyed', () => {
          keyboardShortcutsDisabled.mockReturnValue(false);
          wrapper = createComponent();
          wrapper.destroy();
          Mousetrap.trigger(toggleHotkeys[0]);
          expect(
            useFileTreeBrowserVisibility().toggleFileTreeBrowserIsExpanded,
          ).not.toHaveBeenCalled();
        });
      });

      describe('toggle visibility when shortcuts are disabled', () => {
        it('does not toggle visibility on shortcut trigger', () => {
          keyboardShortcutsDisabled.mockReturnValue(true);
          wrapper = createComponent();
          Mousetrap.trigger(toggleHotkeys[0]);
          expect(
            useFileTreeBrowserVisibility().toggleFileTreeBrowserIsExpanded,
          ).not.toHaveBeenCalled();
        });
      });
    });
  });

  describe('Ref selector', () => {
    it('renders correctly', () => {
      expect(findRefSelector().props('defaultBranch')).toBe(mockRootRef);
    });

    it('renders correctly when branch names ending with .json', () => {
      createComponent({ props: { refSelectorValue: 'ends-with.json' } });
      expect(findRefSelector().exists()).toBe(true);
    });

    it('has fluidWidth attribute enabled', () => {
      expect(findRefSelector().attributes('fluid-width')).toBeDefined();
    });

    it('applies responsive max-width classes', () => {
      const refSelector = findRefSelector();

      expect(refSelector.classes()).toContain('gl-max-w-full');
      expect(refSelector.classes()).toContain('@sm/panel:gl-max-w-4/10');
      expect(refSelector.classes()).toContain('@md/panel:gl-max-w-xs');
    });
  });

  it('renders Breadcrumbs component', () => {
    expect(findBreadcrumbs().exists()).toBe(true);
  });

  it('renders PageHeading component', () => {
    expect(findPageHeading().exists()).toBe(true);
  });

  describe('showTreeControls', () => {
    it('should not render tree controls for blob view', () => {
      wrapper = createComponent({}, { name: 'blobPathDecoded' });
      expect(findTreeControls().exists()).toBe(false);
    });
  });

  describe('when rendered for tree view', () => {
    beforeEach(() => {
      wrapper = createComponent({
        route: { name: 'treePathDecoded', params: { path: 'project' } },
      });
    });

    describe('PageHeading', () => {
      it('displays correct directory name', () => {
        expect(findPageHeading().text()).toContain('project');
        expect(findFileIcon().props('fileName')).toBe('folder-open');
        expect(findFileIcon().props('folder')).toBe(true);
        expect(findFileIcon().classes('gl-text-subtle')).toBe(true);
      });
    });

    describe('Find file button', () => {
      it('renders Find file button', () => {
        expect(findFindFileButton().exists()).toBe(true);
      });

      it('triggers a `focusSearchFile` shortcut when the findFile button is clicked', () => {
        jest.spyOn(Shortcuts, 'focusSearchFile').mockResolvedValue();
        findFindFileButton().vm.$emit('click');

        expect(Shortcuts.focusSearchFile).toHaveBeenCalled();
      });

      it('emits a tracking event when the Find file button is clicked', () => {
        const { trackEventSpy } = bindInternalEventDocument(wrapper.element);
        jest.spyOn(Shortcuts, 'focusSearchFile').mockResolvedValue();

        findFindFileButton().vm.$emit('click');

        expect(trackEventSpy).toHaveBeenCalledWith(
          'click_find_file_button_on_repository_pages',
          {},
          undefined,
        );
      });
    });

    describe('Edit button', () => {
      it('renders WebIdeLink component', () => {
        expect(findWebIdeButton().exists()).toBe(true);
      });

      // Blob routes render BlobControls, so the tree controls never offer file edit actions
      it('does not offer file edit actions', () => {
        expect(findWebIdeLink().props()).toMatchObject({
          isBlob: false,
          showEditButton: false,
          showPipelineEditorButton: false,
        });
      });
    });

    describe('Add to tree dropdown', () => {
      it('renders AddToTree component', () => {
        expect(findAddToTreeDropdown().exists()).toBe(true);
      });
    });

    it('renders CompactCodeDropdown with correct props', () => {
      wrapper = createComponent({
        route: { name: 'treePathDecoded' },
        provided: {
          newWorkspacePath: '/workspaces/new',
          organizationId: '1',
        },
      });

      expect(findCompactCodeDropdown().exists()).toBe(true);
      expect(findCompactCodeDropdown().props()).toMatchObject({
        sshUrl: headerAppInjected.sshUrl,
        httpUrl: headerAppInjected.httpUrl,
        kerberosUrl: headerAppInjected.kerberosUrl,
        xcodeUrl: headerAppInjected.xcodeUrl,
        webIdeUrl: '/-/ide/project/test/project/edit/main/-/index.js/',
        gitpodUrl: 'https://app.ona.com/#http://test.host/test/project/-/tree/main/index.js',
        showWebIdeButton: headerAppInjected.showWebIdeButton,
        isGitpodEnabledForInstance: headerAppInjected.isGitpodEnabledForInstance,
        isGitpodEnabledForUser: headerAppInjected.isGitpodEnabledForUser,
        currentPath: defaultMockRoute.params.path,
        directoryDownloadLinks: headerAppInjected.downloadLinks,
      });
    });

    describe('RepositoryOverflowMenu', () => {
      it('renders RepositoryOverflowMenu component with correct props when on default branch', () => {
        wrapper = createComponent({
          route: { name: 'treePathDecoded' },
        });
        expect(findRepositoryOverflowMenu().props()).toStrictEqual({
          currentRef: 'main',
          fullPath: 'test/project',
          path: 'index.js',
        });
      });
    });
  });

  describe('server-built URLs that depend on the route', () => {
    const gitpodBaseUrl = 'https://gitpod.io/';
    const newBlobPath = '/test/project/-/new/main';

    // Shape of the URLs TreeHelper#breadcrumb_data_attributes and WebIdeButtonHelper#gitpod_url
    // build for the page-load path
    const serverUrls = ({ newBlobTo, fullPath, gitpodTarget }) => {
      const forkPath = (to, notice) =>
        `/test/project/-/forks?continue%5Bnotice%5D=${notice}&continue%5Bnotice_now%5D=Forking&continue%5Bto%5D=${encodeURIComponent(to)}&namespace_key=1`;

      return {
        newBlobPath,
        forkNewBlobPath: forkPath(newBlobTo, 'Forked.'),
        forkNewDirectoryPath: forkPath(fullPath, 'Forked.+Try+to+create+a+new+directory+again.'),
        forkUploadBlobPath: forkPath(fullPath, 'Forked.+Try+to+upload+a+file+again.'),
        gitpodUrl: `${gitpodBaseUrl}#http://test.host${gitpodTarget}`,
      };
    };

    const continueToOf = (path) => queryToObject(path.split('?')[1])['continue[to]'];

    const findForkContinueTos = () =>
      findAllAddToTreeDropdowns().map((addToTree) => ({
        newBlob: continueToOf(addToTree.props('forkNewBlobPath')),
        newDirectory: continueToOf(addToTree.props('forkNewDirectoryPath')),
        uploadBlob: continueToOf(addToTree.props('forkUploadBlobPath')),
      }));

    const findGitpodUrls = () => [
      findWebIdeLink().props('gitpodUrl'),
      findCompactCodeDropdown().props('gitpodUrl'),
    ];

    const navigateTo = async (route) => {
      Object.assign(mockRoute, route);
      await nextTick();
    };

    const expectRouteUrls = ({ newBlobTo, treePath }) => {
      expect(findForkContinueTos()).toEqual([
        { newBlob: newBlobTo, newDirectory: treePath, uploadBlob: treePath },
        { newBlob: newBlobTo, newDirectory: treePath, uploadBlob: treePath },
      ]);
      expect(findGitpodUrls()).toEqual([
        `${gitpodBaseUrl}#http://test.host${treePath.split('?')[0]}`,
        `${gitpodBaseUrl}#http://test.host${treePath.split('?')[0]}`,
      ]);
    };

    describe('on first load of a tree route', () => {
      const injected = serverUrls({
        newBlobTo: '/test/project/-/new/main/docs/old',
        fullPath: '/test/project/-/tree/main/docs/old?ref_type=heads',
        gitpodTarget: '/test/project/-/tree/main/docs/old',
      });

      beforeEach(() => {
        wrapper = createComponent({
          route: {
            name: 'treePathDecoded',
            params: { path: 'docs/old' },
            query: { ref_type: 'heads' },
          },
          provided: { rootRef: mockRootRef, ...injected },
        });
      });

      it('matches the server values', () => {
        expect(findForkContinueTos()[0]).toEqual({
          newBlob: continueToOf(injected.forkNewBlobPath),
          newDirectory: continueToOf(injected.forkNewDirectoryPath),
          uploadBlob: continueToOf(injected.forkUploadBlobPath),
        });
        expect(findGitpodUrls()).toEqual([injected.gitpodUrl, injected.gitpodUrl]);
      });

      it('keeps the other fork params', () => {
        const { 'continue[to]': _, ...otherParams } = queryToObject(
          findAddToTreeDropdown().props('forkNewDirectoryPath').split('?')[1],
        );

        expect(otherParams).toEqual({
          'continue[notice]': 'Forked. Try to create a new directory again.',
          'continue[notice_now]': 'Forking',
          namespace_key: '1',
        });
      });

      describe('after navigating to another directory', () => {
        beforeEach(async () => {
          await navigateTo({ params: { path: 'docs/new dir#1' } });
        });

        it('points the fork links and Gitpod URL at the new directory', () => {
          expectRouteUrls({
            newBlobTo: '/test/project/-/new/main/docs/new%20dir%231',
            treePath: '/test/project/-/tree/main/docs/new%20dir%231?ref_type=heads',
          });
        });
      });
    });

    describe('after navigating from a blob route to a tree route', () => {
      beforeEach(async () => {
        wrapper = createComponent({
          route: { name: 'blobPathDecoded', params: { path: 'docs/README.md' }, query: {} },
          provided: {
            rootRef: mockRootRef,
            ...serverUrls({
              newBlobTo: '/test/project/-/new/main/docs/README.md',
              fullPath: '/test/project/-/blob/main/docs/README.md',
              gitpodTarget: '/test/project/-/tree/main/docs/README.md',
            }),
          },
        });

        await navigateTo({ name: 'treePathDecoded', params: { path: 'docs' } });
      });

      it('points the fork links and Gitpod URL at the directory', () => {
        expectRouteUrls({
          newBlobTo: '/test/project/-/new/main/docs',
          treePath: '/test/project/-/tree/main/docs',
        });
      });
    });

    describe('on first load of the project overview', () => {
      const injected = serverUrls({
        newBlobTo: '/test/project/-/new/main',
        fullPath: '/test/project',
        gitpodTarget: '/test/project/-/tree/main/',
      });

      beforeEach(() => {
        wrapper = createComponent({
          route: { name: 'projectRoot', params: { path: undefined }, query: {} },
          provided: { rootRef: mockRootRef, ...injected },
        });
      });

      it('returns the fork links to the project overview', () => {
        expect(findForkContinueTos()[0]).toEqual({
          newBlob: '/test/project/-/new/main',
          newDirectory: continueToOf(injected.forkNewDirectoryPath),
          uploadBlob: continueToOf(injected.forkUploadBlobPath),
        });
      });
    });

    describe('when Gitpod is unavailable and the user cannot fork', () => {
      beforeEach(() => {
        wrapper = createComponent({
          route: { name: 'treePathDecoded', params: { path: 'docs' } },
          provided: {
            rootRef: mockRootRef,
            forkNewBlobPath: undefined,
            forkNewDirectoryPath: undefined,
            forkUploadBlobPath: undefined,
            gitpodUrl: '',
          },
        });
      });

      it('keeps the values empty', () => {
        expect(findAddToTreeDropdown().props()).toMatchObject({
          forkNewBlobPath: null,
          forkNewDirectoryPath: null,
          forkUploadBlobPath: null,
        });
        expect(findGitpodUrls()).toEqual(['', '']);
      });
    });
  });

  describe('when rendered for blob view', () => {
    describe('showBlobControls', () => {
      it('should not render blob controls when filePath does not exist', () => {
        wrapper = createComponent({ route: { name: 'blobPathDecoded', params: { path: null } } });
        expect(findBlobControls().exists()).toBe(false);
      });

      it.each`
        routeName
        ${'blobPath'}
        ${'blobPathDecoded'}
        ${'blobPathEncoded'}
        ${'blobPathEncodedSlashes'}
      `('should render blob controls when route name is $routeName', ({ routeName }) => {
        wrapper = createComponent({
          route: { name: routeName, params: { path: '/some/file.js' } },
        });
        expect(findBlobControls().exists()).toBe(true);
      });

      it('should not render blob controls for non-blob routes', () => {
        wrapper = createComponent({
          route: { name: 'treePathDecoded', params: { path: 'some/dir' } },
        });
        expect(findBlobControls().exists()).toBe(false);
      });
    });

    it('renders BlobControls component with correct props', () => {
      wrapper = createComponent({ props: { refType: 'branch' } });
      expect(findBlobControls().exists()).toBe(true);
      expect(findBlobControls().props('projectPath')).toBe('test/project');
      expect(findBlobControls().props('refType')).toBe('');
    });

    it('does not render AddToTree component', () => {
      expect(findAddToTreeDropdown().exists()).toBe(false);
    });

    it('displays correct file name and icon', () => {
      expect(findPageHeading().text()).toContain('index.js');
      expect(findFileIcon().props('fileName')).toBe('index.js');
      expect(findFileIcon().props('folder')).toBe(false);
      expect(findFileIcon().classes('gl-text-subtle')).toBe(false);
    });
  });

  describe('when rendered for readme project overview', () => {
    beforeEach(() => {
      pinia = createTestingPinia({ stubActions: false });
      fileTreeBrowserStore = useFileTreeBrowserVisibility();
      jest.spyOn(fileTreeBrowserStore, 'initializeFileTreeBrowser');
      keyboardShortcutsDisabled.mockReturnValue(false);

      wrapper = createComponent({
        route: { name: 'treePathDecoded' },
        provided: {
          newWorkspacePath: '/workspaces/new',
          organizationId: '1',
          isReadmeView: true,
        },
      });
    });

    it('does render CompactCodeDropdown', () => {
      expect(findCompactCodeDropdown().exists()).toBe(true);
    });

    it('does not render directory name and icon', () => {
      expect(findPageHeading().exists()).toBe(false);
      expect(findFileIcon().exists()).toBe(false);
    });

    it('does not render RefSelector or Breadcrumbs', () => {
      expect(findRefSelector().exists()).toBe(false);
      expect(findBreadcrumbs().exists()).toBe(false);
    });

    it('does not render AddToTree component', () => {
      expect(findAddToTreeDropdown().exists()).toBe(false);
    });

    describe('file tree browser', () => {
      it('does not render FileTreeBrowserToggle', () => {
        expect(findFileTreeToggle().exists()).toBe(false);
      });

      it('does not initialize file tree browser store to avoid Pinia errors', () => {
        expect(fileTreeBrowserStore.initializeFileTreeBrowser).not.toHaveBeenCalled();
      });

      it('does not bind keyboard shortcuts', () => {
        Mousetrap.trigger(toggleHotkeys[0]);
        expect(fileTreeBrowserStore.toggleFileTreeBrowserIsExpanded).not.toHaveBeenCalled();
      });
    });
  });

  describe('when rendered for full project overview', () => {
    beforeEach(() => {
      wrapper = createComponent({ route: { name: 'projectRoot' } });
    });

    it('does not render directory name and icon', () => {
      expect(findPageHeading().exists()).toBe(false);
      expect(findFileIcon().exists()).toBe(false);
    });

    it('renders refSelector, breadcrumbs and tree controls with correct layout', () => {
      expect(wrapper.find('section').classes()).toEqual([
        'gl-flex',
        'gl-flex-wrap',
        'gl-items-center',
        'gl-justify-between',
        'gl-gap-3',
        'gl-pt-3',
      ]);
    });
  });
});
