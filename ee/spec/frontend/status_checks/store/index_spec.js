import { createTestingPinia } from '@pinia/testing';
import MockAdapter from 'axios-mock-adapter';
import { useStatusChecks } from 'ee/status_checks/store';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import axios from '~/lib/utils/axios_utils';
import { convertObjectPropsToSnakeCase } from '~/lib/utils/common_utils';
import waitForPromises from 'helpers/wait_for_promises';
import { HTTP_STATUS_OK } from '~/lib/utils/http_status';

const statusChecksPath = '/api/v4/projects/1/external_status_checks';

describe('Status checks store', () => {
  let store;
  let mockAxios;

  const { bindInternalEventDocument } = useMockInternalEventsTracking();

  beforeEach(() => {
    createTestingPinia({ stubActions: false });
    store = useStatusChecks();
    mockAxios = new MockAdapter(axios);
  });

  afterEach(() => {
    mockAxios.restore();
  });

  it('has the expected default state', () => {
    expect(store.$state).toStrictEqual({
      settings: { projectId: null, statusChecksPath: null },
      statusChecks: [],
    });
  });

  describe('setSettings', () => {
    it('sets the settings', () => {
      const settings = { projectId: '12345', statusChecksPath };

      store.setSettings(settings);

      expect(store.settings).toStrictEqual(settings);
    });
  });

  describe('fetchStatusChecks', () => {
    beforeEach(() => {
      store.setSettings({ projectId: '1', statusChecksPath });
    });

    it('sets the status checks from the API response', async () => {
      const data = [{ name: 'Foo' }, { name: 'Bar' }];

      mockAxios.onGet(statusChecksPath).replyOnce(HTTP_STATUS_OK, data);

      await store.fetchStatusChecks();

      expect(store.statusChecks).toStrictEqual(data);
    });

    it('camelizes the API response', async () => {
      mockAxios
        .onGet(statusChecksPath)
        .replyOnce(HTTP_STATUS_OK, [{ name: 'Foo', external_url: 'https://foo.com' }]);

      await store.fetchStatusChecks();

      expect(store.statusChecks).toStrictEqual([{ name: 'Foo', externalUrl: 'https://foo.com' }]);
    });

    it('errors with a failed API response', async () => {
      mockAxios.onGet(statusChecksPath).networkError();

      await expect(store.fetchStatusChecks()).rejects.toThrow(new Error('Network Error'));

      expect(store.statusChecks).toStrictEqual([]);
    });
  });

  describe('when creating and updating a status check', () => {
    const defaultData = {
      name: 'Foo',
      externalUrl: 'https://bar.com',
      protectedBranchIds: [1],
    };

    beforeEach(() => {
      store.setSettings({ projectId: '1', statusChecksPath });
    });

    it.each`
      action                                     | axiosMethod | httpMethod | statusCheck                  | url
      ${(check) => store.postStatusCheck(check)} | ${'onPost'} | ${'post'}  | ${defaultData}               | ${statusChecksPath}
      ${(check) => store.putStatusCheck(check)}  | ${'onPut'}  | ${'put'}   | ${{ ...defaultData, id: 1 }} | ${`${statusChecksPath}/1`}
    `(
      'should $httpMethod to the API and then fetch the status checks',
      async ({ action, axiosMethod, httpMethod, statusCheck, url }) => {
        const { trackEventSpy } = bindInternalEventDocument();
        mockAxios[axiosMethod](url).replyOnce(HTTP_STATUS_OK);
        mockAxios.onGet(statusChecksPath).replyOnce(HTTP_STATUS_OK, [{ name: 'Foo' }]);
        jest.spyOn(store, 'fetchStatusChecks');

        await action(statusCheck);
        await waitForPromises();

        expect(JSON.parse(mockAxios.history[httpMethod][0].data)).toStrictEqual(
          convertObjectPropsToSnakeCase(statusCheck, { deep: true }),
        );
        expect(store.fetchStatusChecks).toHaveBeenCalledTimes(1);
        expect(store.statusChecks).toStrictEqual([{ name: 'Foo' }]);
        expect(trackEventSpy).toHaveBeenCalledWith('change_status_checks', {
          label: 'repository_settings',
        });
      },
    );

    it('resolves even when the status checks refetch fails', async () => {
      const refetch = Promise.reject(new Error('Network Error'));
      refetch.catch(() => {});
      mockAxios.onPost(statusChecksPath).replyOnce(HTTP_STATUS_OK);
      jest.spyOn(store, 'fetchStatusChecks').mockReturnValue(refetch);

      await expect(store.postStatusCheck(defaultData)).resolves.toBeUndefined();
    });
  });

  describe('deleteStatusCheck', () => {
    beforeEach(() => {
      store.setSettings({ projectId: '1', statusChecksPath });
    });

    it('should DELETE call the API and then fetch the status checks', async () => {
      const id = 1;
      const { trackEventSpy } = bindInternalEventDocument();

      mockAxios.onDelete(`${statusChecksPath}/${id}`).replyOnce(HTTP_STATUS_OK);
      mockAxios.onGet(statusChecksPath).replyOnce(HTTP_STATUS_OK, []);
      jest.spyOn(store, 'fetchStatusChecks');

      await store.deleteStatusCheck(id);

      expect(mockAxios.history.delete).toHaveLength(1);
      expect(store.fetchStatusChecks).toHaveBeenCalledTimes(1);
      expect(trackEventSpy).toHaveBeenCalledWith('change_status_checks', {
        label: 'repository_settings',
      });
    });
  });
});
