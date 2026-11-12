import { createTestingPinia } from '@pinia/testing';
import MockAdapter from 'axios-mock-adapter';
import { TEST_HOST } from 'spec/test_constants';
import { INITIAL_PAGE, GROUP_BADGE, PAGE_SIZE, PROJECT_BADGE } from '~/badges/constants';
import createEmptyBadge from '~/badges/empty_badge';
import { transformBackendBadge, useBadgeSettings } from '~/badges/store';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_INTERNAL_SERVER_ERROR, HTTP_STATUS_OK } from '~/lib/utils/http_status';
import { createDummyBadge, createDummyBadgeResponse } from '../dummy_badge';
import { MOCK_PAGINATION, MOCK_PAGINATION_HEADERS } from '../mock_data';

describe('Badges store', () => {
  const dummyEndpointUrl = `${TEST_HOST}/badges/endpoint`;
  const emptyPagination = {
    perPage: null,
    page: null,
    total: null,
    totalPages: null,
    nextPage: null,
    previousPage: null,
  };

  let axiosMock;
  let store;
  let dummyBadge;
  let dummyBadges;

  beforeEach(() => {
    createTestingPinia({ stubActions: false });
    store = useBadgeSettings();
    axiosMock = new MockAdapter(axios);
    dummyBadge = createDummyBadge();
    dummyBadges = [
      { ...createDummyBadge(), id: 5 },
      { ...createDummyBadge(), id: 6 },
    ];
    store.$patch({
      apiEndpointUrl: dummyEndpointUrl,
      badges: dummyBadges,
      pagination: MOCK_PAGINATION,
    });
  });

  afterEach(() => {
    axiosMock.restore();
  });

  describe('setInitialState', () => {
    it('sets the kind and the API endpoint', () => {
      store.setInitialState({ kind: GROUP_BADGE, apiEndpointUrl: '/groups/foo/-/badges' });

      expect(store.kind).toBe(GROUP_BADGE);
      expect(store.apiEndpointUrl).toBe('/groups/foo/-/badges');
    });
  });

  describe('addBadge', () => {
    let badgeInAddForm;
    let endpointMock;

    beforeEach(() => {
      endpointMock = axiosMock.onPost(dummyEndpointUrl);
      badgeInAddForm = createDummyBadge();
      store.badgeInAddForm = badgeInAddForm;
      store.renderedBadge = createDummyBadge();
      jest.spyOn(store, 'loadBadges').mockResolvedValue();
    });

    it('sets isSaving, resets the add form and loads the current page on successful response', async () => {
      endpointMock.replyOnce((req) => {
        expect(req.data).toBe(
          JSON.stringify({
            name: badgeInAddForm.name,
            image_url: badgeInAddForm.imageUrl,
            link_url: badgeInAddForm.linkUrl,
          }),
        );
        expect(store.isSaving).toBe(true);

        return [HTTP_STATUS_OK, createDummyBadgeResponse()];
      });

      await store.addBadge();

      expect(store.isSaving).toBe(false);
      expect(store.badgeInAddForm).toEqual(createEmptyBadge());
      expect(store.renderedBadge).toBe(null);
      expect(store.loadBadges).toHaveBeenCalledWith({ page: MOCK_PAGINATION.page });
    });

    it('sets isSaving back to false and throws an error on error response', async () => {
      endpointMock.replyOnce((req) => {
        expect(req.data).toBe(
          JSON.stringify({
            name: badgeInAddForm.name,
            image_url: badgeInAddForm.imageUrl,
            link_url: badgeInAddForm.linkUrl,
          }),
        );
        expect(store.isSaving).toBe(true);

        return [HTTP_STATUS_INTERNAL_SERVER_ERROR, 'mock_new_badge_error'];
      });

      await expect(store.addBadge()).rejects.toMatchObject({
        response: { status: HTTP_STATUS_INTERNAL_SERVER_ERROR, data: 'mock_new_badge_error' },
      });

      expect(store.isSaving).toBe(false);
      expect(store.badgeInAddForm).toEqual(badgeInAddForm);
      expect(store.loadBadges).not.toHaveBeenCalled();
    });
  });

  describe('deleteBadge', () => {
    let badgeId;
    let endpointMock;

    beforeEach(() => {
      badgeId = dummyBadges[0].id;
      endpointMock = axiosMock.onDelete(`${dummyEndpointUrl}/${badgeId}`);
      jest.spyOn(store, 'loadBadges').mockResolvedValue();
    });

    it('sets isDeleting and loads the current page on successful response', async () => {
      endpointMock.replyOnce((req) => {
        expect(req.url).toBe(`${dummyEndpointUrl}/${badgeId}`);
        expect(store.badges[0].isDeleting).toBe(true);
        expect(store.badges[1].isDeleting).toBe(false);

        return [HTTP_STATUS_OK, ''];
      });

      await store.deleteBadge(dummyBadges[0]);

      expect(store.loadBadges).toHaveBeenCalledWith({ page: MOCK_PAGINATION.page });
    });

    it('resets isDeleting and throws an error on error response', async () => {
      endpointMock.replyOnce((req) => {
        expect(req.url).toBe(`${dummyEndpointUrl}/${badgeId}`);
        expect(store.badges[0].isDeleting).toBe(true);

        return [HTTP_STATUS_INTERNAL_SERVER_ERROR, 'mock_delete_badge_error'];
      });

      await expect(store.deleteBadge(dummyBadges[0])).rejects.toMatchObject({
        response: { status: HTTP_STATUS_INTERNAL_SERVER_ERROR, data: 'mock_delete_badge_error' },
      });

      expect(store.badges[0].isDeleting).toBe(false);
      expect(store.loadBadges).not.toHaveBeenCalled();
    });
  });

  describe('setBadgeIsDeleting', () => {
    beforeEach(() => {
      store.badges = [
        { ...dummyBadge, id: dummyBadge.id - 1, isDeleting: false },
        { ...dummyBadge, isDeleting: false },
        { ...dummyBadge, id: dummyBadge.id + 1, isDeleting: true },
      ];
    });

    it('sets isDeleting to true on the given badge only', () => {
      store.setBadgeIsDeleting(dummyBadge.id, true);

      expect(store.badges).toHaveLength(3);
      expect(store.badges[0].isDeleting).toBe(false);
      expect(store.badges[1].isDeleting).toBe(true);
      expect(store.badges[2].isDeleting).toBe(true);
    });

    it('sets isDeleting to false on the given badge only', () => {
      store.badges = store.badges.map((badge) => ({ ...badge, isDeleting: true }));

      store.setBadgeIsDeleting(dummyBadge.id, false);

      expect(store.badges).toHaveLength(3);
      expect(store.badges[0].isDeleting).toBe(true);
      expect(store.badges[1].isDeleting).toBe(false);
      expect(store.badges[2].isDeleting).toBe(true);
    });
  });

  describe('editBadge', () => {
    beforeEach(() => {
      store.badgeInEditForm = 'dummy value';
      store.isEditing = false;
      store.renderedBadge = 'dummy value';
    });

    it('initializes the edit form', () => {
      store.editBadge(dummyBadge);

      expect(store.isEditing).toBe(true);
      expect(store.badgeInEditForm).toEqual(dummyBadge);
      expect(store.renderedBadge).toEqual(dummyBadge);
    });
  });

  describe('loadBadges', () => {
    let endpointMock;

    beforeEach(() => {
      endpointMock = axiosMock.onGet(dummyEndpointUrl);
      store.$patch({ pagination: emptyPagination });
    });

    it('sets the badges and the pagination on successful response', async () => {
      const dummyResponse = [
        createDummyBadgeResponse(),
        createDummyBadgeResponse(),
        createDummyBadgeResponse(),
      ];

      endpointMock.replyOnce((req) => {
        expect(req.params).toStrictEqual({
          page: INITIAL_PAGE,
          per_page: PAGE_SIZE,
        });
        expect(store.isLoading).toBe(true);

        return [HTTP_STATUS_OK, dummyResponse, MOCK_PAGINATION_HEADERS];
      });

      await store.loadBadges({ page: INITIAL_PAGE });

      expect(store.isLoading).toBe(false);
      expect(store.badges).toStrictEqual(
        dummyResponse.map((badge) => transformBackendBadge(badge)),
      );
      expect(store.pagination).toStrictEqual(MOCK_PAGINATION);
    });

    it('orders group badges before project badges, then by id', async () => {
      const response = [
        { ...createDummyBadgeResponse(), id: 3, kind: PROJECT_BADGE },
        { ...createDummyBadgeResponse(), id: 2, kind: GROUP_BADGE },
        { ...createDummyBadgeResponse(), id: 1, kind: PROJECT_BADGE },
        { ...createDummyBadgeResponse(), id: 4, kind: GROUP_BADGE },
      ];
      endpointMock.replyOnce(HTTP_STATUS_OK, response, MOCK_PAGINATION_HEADERS);

      await store.loadBadges({ page: INITIAL_PAGE });

      expect(store.badges.map(({ id, kind }) => [id, kind])).toEqual([
        [2, GROUP_BADGE],
        [4, GROUP_BADGE],
        [1, PROJECT_BADGE],
        [3, PROJECT_BADGE],
      ]);
    });

    it('sets isLoading back to false and throws an error on error response', async () => {
      endpointMock.replyOnce((req) => {
        expect(req.params).toStrictEqual({
          page: INITIAL_PAGE,
          per_page: PAGE_SIZE,
        });
        expect(store.isLoading).toBe(true);

        return [HTTP_STATUS_INTERNAL_SERVER_ERROR, 'mock_load_badges_error'];
      });

      await expect(store.loadBadges({ page: INITIAL_PAGE })).rejects.toMatchObject({
        response: { status: HTTP_STATUS_INTERNAL_SERVER_ERROR, data: 'mock_load_badges_error' },
      });

      expect(store.isLoading).toBe(false);
      expect(store.pagination).toEqual(emptyPagination);
    });
  });

  describe('requestRenderedBadge', () => {
    it('sets isRendering to true', () => {
      store.isRendering = false;

      store.requestRenderedBadge();

      expect(store.isRendering).toBe(true);
    });
  });

  describe('receiveRenderedBadge', () => {
    it('sets renderedBadge and isRendering', () => {
      store.isRendering = true;
      store.renderedBadge = 'dummy value';

      store.receiveRenderedBadge(dummyBadge);

      expect(store.isRendering).toBe(false);
      expect(store.renderedBadge).toStrictEqual(dummyBadge);
    });
  });

  describe('receiveRenderedBadgeError', () => {
    it('sets isRendering to false', () => {
      store.isRendering = true;

      store.receiveRenderedBadgeError();

      expect(store.isRendering).toBe(false);
    });
  });

  describe('renderBadge', () => {
    let endpointMock;
    let badgeInForm;

    beforeEach(() => {
      badgeInForm = createDummyBadge();
      store.badgeInAddForm = badgeInForm;
      const urlParameters = [
        `link_url=${encodeURIComponent(badgeInForm.linkUrl)}`,
        `image_url=${encodeURIComponent(badgeInForm.imageUrl)}`,
      ].join('&');
      endpointMock = axiosMock.onGet(`${dummyEndpointUrl}/render?${urlParameters}`);
      jest.spyOn(axios, 'get');
    });

    it.each(['imageUrl', 'linkUrl'])('returns immediately if %s is empty', async (field) => {
      store.badgeInAddForm = { ...badgeInForm, [field]: '' };

      await store.renderBadge();

      expect(axios.get).not.toHaveBeenCalled();
      expect(store.requestRenderedBadge).not.toHaveBeenCalled();
    });

    it.each(['imageUrl', 'linkUrl'])('returns immediately if %s is invalid', async (field) => {
      store.badgeInAddForm = { ...badgeInForm, [field]: 'foo' };

      await store.renderBadge();

      expect(axios.get).not.toHaveBeenCalled();
      expect(store.requestRenderedBadge).not.toHaveBeenCalled();
    });

    it('renders the badge in the edit form when editing', async () => {
      const badgeInEditForm = createDummyBadge();
      store.isEditing = true;
      store.badgeInEditForm = badgeInEditForm;
      axiosMock
        .onGet(
          `${dummyEndpointUrl}/render?link_url=${encodeURIComponent(
            badgeInEditForm.linkUrl,
          )}&image_url=${encodeURIComponent(badgeInEditForm.imageUrl)}`,
        )
        .replyOnce(HTTP_STATUS_OK, createDummyBadgeResponse());

      await store.renderBadge();

      expect(store.receiveRenderedBadge).toHaveBeenCalledTimes(1);
    });

    it('escapes user input', async () => {
      axios.get.mockResolvedValue({ data: createDummyBadgeResponse() });
      store.badgeInAddForm = {
        ...badgeInForm,
        imageUrl: "https://example.com?param=<script>alert('XSS')</script>",
        linkUrl: "https://example.com?param=<script>alert('XSS')</script>",
      };

      await store.renderBadge();

      expect(axios.get.mock.calls).toHaveLength(1);
      const url = axios.get.mock.calls[0][0];

      expect(url).toContain(
        "/render?link_url=https%3A%2F%2Fexample.com%3Fparam%3D%3Cscript%3Ealert('XSS')%3C%2Fscript%3E&image_url=https%3A%2F%2Fexample.com%3Fparam%3D%3Cscript%3Ealert('XSS')%3C%2Fscript%3E",
      );
    });

    it('calls requestRenderedBadge and receiveRenderedBadge for successful response', async () => {
      const dummyResponse = createDummyBadgeResponse();
      endpointMock.replyOnce(() => {
        expect(store.requestRenderedBadge).toHaveBeenCalledTimes(1);
        expect(store.receiveRenderedBadge).not.toHaveBeenCalled();
        expect(store.isRendering).toBe(true);
        return [HTTP_STATUS_OK, dummyResponse];
      });

      await store.renderBadge();

      expect(store.receiveRenderedBadge).toHaveBeenCalledWith(transformBackendBadge(dummyResponse));
      expect(store.receiveRenderedBadgeError).not.toHaveBeenCalled();
      expect(store.isRendering).toBe(false);
      expect(store.renderedBadge).toEqual(transformBackendBadge(dummyResponse));
    });

    it('calls requestRenderedBadge and receiveRenderedBadgeError for error response', async () => {
      endpointMock.replyOnce(() => {
        expect(store.requestRenderedBadge).toHaveBeenCalledTimes(1);
        expect(store.receiveRenderedBadgeError).not.toHaveBeenCalled();
        return [HTTP_STATUS_INTERNAL_SERVER_ERROR, ''];
      });

      await expect(store.renderBadge()).rejects.toThrow();

      expect(store.receiveRenderedBadgeError).toHaveBeenCalledTimes(1);
      expect(store.receiveRenderedBadge).not.toHaveBeenCalled();
      expect(store.isRendering).toBe(false);
    });
  });

  describe('requestUpdatedBadge', () => {
    it('sets isSaving to true', () => {
      store.isSaving = false;

      store.requestUpdatedBadge();

      expect(store.isSaving).toBe(true);
    });
  });

  describe('receiveUpdatedBadge', () => {
    beforeEach(() => {
      store.badges = [
        { ...dummyBadge, id: dummyBadge.id - 1 },
        dummyBadge,
        { ...dummyBadge, id: dummyBadge.id + 1 },
      ];
      store.badgeInEditForm = createDummyBadge();
      store.isEditing = true;
      store.isSaving = true;
      store.renderedBadge = createDummyBadge();
    });

    it('resets the edit form', () => {
      store.receiveUpdatedBadge(dummyBadge);

      expect(store.badgeInEditForm).toEqual(createEmptyBadge());
      expect(store.isEditing).toBe(false);
      expect(store.isSaving).toBe(false);
      expect(store.renderedBadge).toBe(null);
    });

    it('replaces the updated badge', () => {
      const badgeCount = store.badges.length;
      const badgeIndex = store.badges.findIndex(({ id }) => id === dummyBadge.id);
      const newBadge = { id: dummyBadge.id, dummy: 'value' };

      store.receiveUpdatedBadge(newBadge);

      expect(store.badges).toHaveLength(badgeCount);
      expect(store.badges[badgeIndex]).toStrictEqual(newBadge);
    });
  });

  describe('receiveUpdatedBadgeError', () => {
    it('sets isSaving to false', () => {
      store.isSaving = true;

      store.receiveUpdatedBadgeError();

      expect(store.isSaving).toBe(false);
    });
  });

  describe('saveBadge', () => {
    let badgeInEditForm;
    let endpointMock;

    beforeEach(() => {
      badgeInEditForm = createDummyBadge();
      store.badgeInEditForm = badgeInEditForm;
      endpointMock = axiosMock.onPut(`${dummyEndpointUrl}/${badgeInEditForm.id}`);
    });

    it('calls requestUpdatedBadge and receiveUpdatedBadge for successful response', async () => {
      const dummyResponse = createDummyBadgeResponse();

      endpointMock.replyOnce((req) => {
        expect(req.data).toBe(
          JSON.stringify({
            name: 'TestBadge',
            image_url: badgeInEditForm.imageUrl,
            link_url: badgeInEditForm.linkUrl,
          }),
        );

        expect(store.requestUpdatedBadge).toHaveBeenCalledTimes(1);
        expect(store.receiveUpdatedBadge).not.toHaveBeenCalled();
        return [HTTP_STATUS_OK, dummyResponse];
      });

      await store.saveBadge();

      expect(store.receiveUpdatedBadge).toHaveBeenCalledWith(transformBackendBadge(dummyResponse));
      expect(store.receiveUpdatedBadgeError).not.toHaveBeenCalled();
    });

    it('calls requestUpdatedBadge and receiveUpdatedBadgeError for error response', async () => {
      endpointMock.replyOnce((req) => {
        expect(req.data).toBe(
          JSON.stringify({
            name: 'TestBadge',
            image_url: badgeInEditForm.imageUrl,
            link_url: badgeInEditForm.linkUrl,
          }),
        );

        expect(store.requestUpdatedBadge).toHaveBeenCalledTimes(1);
        expect(store.receiveUpdatedBadgeError).not.toHaveBeenCalled();
        return [HTTP_STATUS_INTERNAL_SERVER_ERROR, ''];
      });

      await expect(store.saveBadge()).rejects.toThrow();

      expect(store.receiveUpdatedBadgeError).toHaveBeenCalledTimes(1);
      expect(store.receiveUpdatedBadge).not.toHaveBeenCalled();
      expect(store.isSaving).toBe(false);
    });
  });

  describe('stopEditing', () => {
    it('resets the edit form', () => {
      store.badgeInEditForm = 'dummy value';
      store.isEditing = true;
      store.renderedBadge = 'dummy value';

      store.stopEditing();

      expect(store.isEditing).toBe(false);
      expect(store.badgeInEditForm).toEqual(createEmptyBadge());
      expect(store.renderedBadge).toBe(null);
    });
  });

  describe('updateBadgeInForm', () => {
    beforeEach(() => {
      store.badgeInAddForm = 'dummy value';
      store.badgeInEditForm = 'dummy value';
    });

    it('sets badgeInEditForm if isEditing is true', () => {
      store.isEditing = true;

      store.updateBadgeInForm(dummyBadge);

      expect(store.badgeInEditForm).toStrictEqual(dummyBadge);
      expect(store.badgeInAddForm).toBe('dummy value');
    });

    it('sets badgeInAddForm if isEditing is false', () => {
      store.isEditing = false;

      store.updateBadgeInForm(dummyBadge);

      expect(store.badgeInAddForm).toStrictEqual(dummyBadge);
      expect(store.badgeInEditForm).toBe('dummy value');
    });
  });

  describe('resetBadgeInForm', () => {
    it('resets the add form to an empty badge', () => {
      store.isEditing = false;
      store.badgeInAddForm = dummyBadge;

      store.resetBadgeInForm();

      expect(store.badgeInAddForm).toEqual(createEmptyBadge());
    });
  });

  describe('updateBadgeInModal', () => {
    it('sets badgeInModal', () => {
      store.badgeInModal = 'dummy value';

      store.updateBadgeInModal(dummyBadge);

      expect(store.badgeInModal).toStrictEqual(dummyBadge);
    });
  });
});
