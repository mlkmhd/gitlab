import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { GlButton } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import Table from '~/repository/components/table/index.vue';
import TableRow from '~/repository/components/table/row.vue';
import { observeElementsByIds } from '~/lib/utils/lazy_render_utils';
import refQuery from '~/repository/queries/ref.query.graphql';
import projectPathQuery from '~/repository/queries/project_path.query.graphql';
import createMockApollo from 'helpers/mock_apollo_helper';

let itemVisibilityCallback;

jest.mock('~/lib/utils/lazy_render_utils', () => ({
  ...jest.requireActual('~/lib/utils/lazy_render_utils'),
  createItemVisibilityObserver: jest.fn((cb) => {
    itemVisibilityCallback = cb;
    return { observe: jest.fn(), disconnect: jest.fn() };
  }),
  observeElementsByIds: jest.fn(),
}));

let wrapper;

const createMockApolloProvider = (ref) => {
  Vue.use(VueApollo);
  const apolloProver = createMockApollo([]);
  apolloProver.clients.defaultClient.cache.writeQuery({
    query: refQuery,
    data: { ref, escapedRef: ref },
  });
  apolloProver.clients.defaultClient.cache.writeQuery({
    query: projectPathQuery,
    data: { projectPath: 'gitlab-org/gitlab' },
  });

  return apolloProver;
};

const MOCK_BLOBS = [
  {
    id: '123abc',
    sha: '123abc',
    flatPath: 'blob',
    name: 'blob.md',
    type: 'blob',
    webPath: '/blob',
  },
  {
    id: '124abc',
    sha: '124abc',
    flatPath: 'blob2',
    name: 'blob2.md',
    type: 'blob',
    webUrl: 'http://test.com',
  },
  {
    id: '125abc',
    sha: '125abc',
    flatPath: 'blob3',
    name: 'blob3.md',
    type: 'blob',
    webUrl: 'http://test.com',
    mode: '120000',
  },
];

const MOCK_COMMITS = [
  {
    fileName: 'blob.md',
    filePath: 'test_dir/blob.md',
    type: 'blob',
    commit: {
      message: 'Updated blob.md',
    },
  },
  {
    fileName: 'blob2.md',
    filePath: 'test_dir/blob2.md',
    type: 'blob',
    commit: {
      message: 'Updated blob2.md',
    },
  },
  {
    fileName: 'blob3.md',
    filePath: 'test_dir/blob3.md',
    type: 'blob',
    commit: {
      message: 'Updated blob3.md',
    },
  },
  {
    fileName: 'root_blob.md',
    filePath: '/root_blob.md',
    type: 'blob',
    commit: {
      message: 'Updated root_blob.md',
    },
  },
];

const triggerAllIntersections = async () => {
  wrapper.element.querySelectorAll('[data-item-id]').forEach((el) => {
    itemVisibilityCallback(el.dataset.itemId);
  });
  await nextTick();
};

function factory({
  path,
  isLoading = false,
  hasMore = true,
  entries = {},
  commits = [],
  ref = 'main',
  listeners = {},
}) {
  wrapper = shallowMountExtended(Table, {
    listeners,
    propsData: {
      path,
      isLoading,
      entries,
      hasMore,
      commits,
    },
    apolloProvider: createMockApolloProvider(ref),
    data() {
      return {
        ref,
      };
    },
  });
}

async function factoryWithVisibleRows(options) {
  factory(options);
  await nextTick();
  triggerAllIntersections();
  await nextTick();
}

const findTableRows = () => wrapper.findAllComponents(TableRow);
const findShowMoreButton = () => wrapper.findComponent(GlButton);
const findLoadingIndicators = () => wrapper.findAllByTestId('loader');
const findPlaceholderRows = () => wrapper.findAll('tr.tree-item[data-item-id]');

describe('Repository table component', () => {
  it('signals once after the first real row is in the DOM', async () => {
    const seen = [];
    factory({
      path: '/',
      entries: { blobs: MOCK_BLOBS },
      listeners: { 'row-rendered': () => seen.push(findTableRows().length) },
    });
    await nextTick();

    expect(seen).toEqual([]);
    await triggerAllIntersections();
    await nextTick();

    expect(seen).toEqual([MOCK_BLOBS.length]);
    await triggerAllIntersections();
    await nextTick();
    expect(seen).toHaveLength(1);
  });

  it.each([false, true])(
    'signals once per mount when returning to a directory, same entry count: %s',
    async (sameSize) => {
      const otherBlobs = MOCK_BLOBS.slice(0, sameSize ? MOCK_BLOBS.length : 1).map((blob) => ({
        ...blob,
        flatPath: `other/${blob.flatPath}`,
      }));
      await factoryWithVisibleRows({ path: '/', entries: { blobs: MOCK_BLOBS } });
      expect(wrapper.emitted('row-rendered')).toHaveLength(1);

      const visitDirectory = async (path, blobs) => {
        wrapper.destroy();
        observeElementsByIds.mockClear();
        factory({ path, entries: { blobs } });
        await nextTick();

        expect(wrapper.emitted('row-rendered')).toBeUndefined();
        expect(findTableRows()).toHaveLength(0);
        expect(findPlaceholderRows()).toHaveLength(blobs.length);
        expect(observeElementsByIds).toHaveBeenCalledWith(
          wrapper.element,
          expect.any(Object),
          blobs.map((blob, index) => `${blob.flatPath}-${blob.id}-${index}`),
        );
        await triggerAllIntersections();
        expect(wrapper.emitted('row-rendered')).toHaveLength(1);
      };
      await visitDirectory('other', otherBlobs);
      await visitDirectory('/', MOCK_BLOBS);

      await triggerAllIntersections();
      expect(wrapper.emitted('row-rendered')).toHaveLength(1);
    },
  );

  it('observes added entries without signaling the first row again', async () => {
    await factoryWithVisibleRows({ path: '/', entries: { blobs: MOCK_BLOBS.slice(0, 1) } });
    observeElementsByIds.mockClear();

    await wrapper.setProps({ entries: { blobs: MOCK_BLOBS } });
    await nextTick();

    expect(observeElementsByIds).toHaveBeenCalledWith(
      wrapper.element,
      expect.any(Object),
      MOCK_BLOBS.slice(1).map((blob, index) => `${blob.flatPath}-${blob.id}-${index + 1}`),
    );
    await triggerAllIntersections();

    expect(findTableRows()).toHaveLength(MOCK_BLOBS.length);
    expect(wrapper.emitted('row-rendered')).toHaveLength(1);
  });

  it.each`
    path            | ref
    ${'/'}          | ${'main'}
    ${'app/assets'} | ${'main'}
    ${'/'}          | ${'test'}
  `('renders table caption for $ref in $path', async ({ path, ref }) => {
    factory({ path, ref });

    await nextTick();
    expect(wrapper.find('.table').attributes('aria-label')).toEqual(
      `Files, directories, and submodules in the path ${path} for commit reference ${ref}`,
    );
  });

  it('shows 3 loading indicators while loading', () => {
    factory({ path: '/', isLoading: true });

    expect(findLoadingIndicators()).toHaveLength(3);
  });

  it('renders table rows after items become visible', async () => {
    await factoryWithVisibleRows({
      path: 'test_dir',
      entries: { blobs: MOCK_BLOBS },
      commits: MOCK_COMMITS,
    });

    const rows = findTableRows();

    expect(rows).toHaveLength(3);
    expect(rows.at(2).attributes().mode).toEqual('120000');
    expect(rows.at(2).props().rowNumber).toBe(2);
    expect(rows.at(2).props().commitInfo).toEqual(MOCK_COMMITS[2]);
  });

  it('renders placeholder rows before items become visible', async () => {
    factory({
      path: 'test_dir',
      entries: { blobs: MOCK_BLOBS },
      commits: MOCK_COMMITS,
    });
    await nextTick();

    expect(findTableRows()).toHaveLength(0);
    expect(findPlaceholderRows()).toHaveLength(3);
  });

  it('renders correct commit info for blobs in the root', async () => {
    await factoryWithVisibleRows({
      path: '/',
      entries: {
        blobs: [
          {
            id: '126abc',
            sha: '126abc',
            flatPath: 'root_blob.md',
            name: 'root_blob.md',
            type: 'blob',
            webUrl: 'http://test.com',
            mode: '120000',
          },
        ],
      },
      commits: MOCK_COMMITS,
    });

    expect(findTableRows().at(0).props().commitInfo).toEqual(MOCK_COMMITS[3]);
  });

  describe('Show more button', () => {
    const showMoreButton = () => wrapper.findComponent(GlButton);

    it.each`
      hasMore  | expectButtonToExist
      ${true}  | ${true}
      ${false} | ${false}
    `('renders correctly', ({ hasMore, expectButtonToExist }) => {
      factory({ path: '/', hasMore });
      expect(showMoreButton().exists()).toBe(expectButtonToExist);
    });

    it('when is clicked, emits show-more event after a delay for better INP', async () => {
      factory({ path: '/' });

      showMoreButton().vm.$emit('click');
      await nextTick();

      expect(findShowMoreButton().props('loading')).toBe(true); // Show loader immediately
      expect(wrapper.emitted('show-more')).toBeUndefined(); // Event should not be emitted immediately

      jest.runAllTimers(); // Wait for the setTimeout to execute
      await nextTick();

      expect(wrapper.emitted('show-more')).toHaveLength(1); // Now the event should be emitted
      expect(findShowMoreButton().props('loading')).toBe(false); // Hide loader
    });
  });
});
