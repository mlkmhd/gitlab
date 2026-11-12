import { GlLoadingIcon } from '@gitlab/ui';
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import MockAdapter from 'axios-mock-adapter';
import createMockApollo from 'helpers/mock_apollo_helper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_INTERNAL_SERVER_ERROR, HTTP_STATUS_OK } from '~/lib/utils/http_status';
import { captureException } from '~/sentry/sentry_browser_wrapper';
import BlobAuxiliaryViewer from '~/repository/components/blob_auxiliary_viewer.vue';
import blobAuxiliaryViewerQuery from '~/repository/queries/blob_auxiliary_viewer.query.graphql';

jest.mock('~/sentry/sentry_browser_wrapper');

Vue.use(VueApollo);

describe('BlobAuxiliaryViewer', () => {
  let wrapper;
  let mockAxios;
  let queryHandler;

  const webPath = '/group/project/-/blob/main/LICENSE';
  const viewerUrl = `${webPath}?format=json&viewer=auxiliary`;

  const createQueryResponse = (auxiliaryViewer) => ({
    data: {
      project: {
        __typename: 'Project',
        id: 'gid://gitlab/Project/1',
        repository: {
          __typename: 'Repository',
          blobs: {
            __typename: 'RepositoryBlobConnection',
            nodes: [
              {
                __typename: 'RepositoryBlob',
                id: 'gid://gitlab/Blob/1',
                webPath,
                auxiliaryViewer,
              },
            ],
          },
        },
      },
    },
  });

  const auxiliaryViewer = { __typename: 'BlobViewer', type: 'auxiliary' };

  const createComponent = ({
    handler = jest.fn().mockResolvedValue(createQueryResponse(auxiliaryViewer)),
  } = {}) => {
    queryHandler = handler;

    wrapper = shallowMountExtended(BlobAuxiliaryViewer, {
      apolloProvider: createMockApollo([[blobAuxiliaryViewerQuery, queryHandler]]),
      propsData: {
        path: 'LICENSE',
        projectPath: 'group/project',
        currentRef: 'main',
        refType: 'heads',
      },
    });
  };

  const findViewer = () => wrapper.findByTestId('blob-auxiliary-viewer');

  beforeEach(() => {
    mockAxios = new MockAdapter(axios);
  });

  afterEach(() => {
    mockAxios.restore();
  });

  describe('when the blob has an auxiliary viewer', () => {
    it('queries the auxiliary viewer for the current blob', async () => {
      mockAxios.onGet(viewerUrl).reply(HTTP_STATUS_OK, { html: '' });
      createComponent();
      await waitForPromises();

      expect(queryHandler).toHaveBeenCalledWith({
        projectPath: 'group/project',
        filePath: 'LICENSE',
        ref: 'main',
        refType: 'HEADS',
      });
    });

    describe('while the HTML loads', () => {
      beforeEach(async () => {
        mockAxios.onGet(viewerUrl).reply(() => new Promise(() => {}));
        createComponent();
        await waitForPromises();
      });

      it('shows a loading state', () => {
        expect(findViewer().findComponent(GlLoadingIcon).exists()).toBe(true);
        expect(findViewer().text()).toBe('Analyzing file…');
      });
    });

    describe('when the HTML loads', () => {
      beforeEach(async () => {
        mockAxios.onGet(viewerUrl).reply(HTTP_STATUS_OK, {
          html: '<p>This project is licensed under the MIT License.</p>',
        });
        createComponent();
        await waitForPromises();
      });

      it('renders the auxiliary viewer HTML', () => {
        expect(findViewer().findComponent(GlLoadingIcon).exists()).toBe(false);
        expect(findViewer().text()).toBe('This project is licensed under the MIT License.');
      });
    });

    describe('when the HTML fails to load', () => {
      beforeEach(async () => {
        mockAxios.onGet(viewerUrl).reply(HTTP_STATUS_INTERNAL_SERVER_ERROR);
        createComponent();
        await waitForPromises();
      });

      it('hides the auxiliary viewer', () => {
        expect(findViewer().exists()).toBe(false);
      });

      it('reports the error', () => {
        expect(captureException).toHaveBeenCalledWith(expect.any(Error), {
          tags: { vue_component: 'BlobAuxiliaryViewer' },
        });
      });
    });
  });

  describe('when the blob has no auxiliary viewer', () => {
    beforeEach(async () => {
      createComponent({ handler: jest.fn().mockResolvedValue(createQueryResponse(null)) });
      await waitForPromises();
    });

    it('does not render or fetch anything', () => {
      expect(findViewer().exists()).toBe(false);
      expect(mockAxios.history.get).toHaveLength(0);
    });
  });

  describe('when the query fails', () => {
    const error = new Error('GraphQL error');

    beforeEach(async () => {
      createComponent({ handler: jest.fn().mockRejectedValue(error) });
      await waitForPromises();
    });

    it('does not render or fetch anything', () => {
      expect(findViewer().exists()).toBe(false);
      expect(mockAxios.history.get).toHaveLength(0);
    });

    it('reports the error', () => {
      expect(captureException).toHaveBeenCalledWith(expect.any(Error), {
        tags: { vue_component: 'BlobAuxiliaryViewer' },
      });
    });
  });
});
