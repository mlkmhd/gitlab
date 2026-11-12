import MockAdapter from 'axios-mock-adapter';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import testAction from 'helpers/vuex_action_helper';
import * as actions from '~/emoji/awards_app/store/actions';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_INTERNAL_SERVER_ERROR, HTTP_STATUS_OK } from '~/lib/utils/http_status';
import { EMOJI_THUMBS_UP, EMOJI_THUMBS_DOWN } from '~/emoji/constants';

jest.mock('~/sentry/sentry_browser_wrapper');
jest.mock('~/vue_shared/plugins/global_toast');

describe('Awards app actions', () => {
  describe('setInitialData', () => {
    it('commits SET_INITIAL_DATA', async () => {
      await testAction(
        actions.setInitialData,
        { path: 'https://gitlab.com' },
        {},
        [{ type: 'SET_INITIAL_DATA', payload: { path: 'https://gitlab.com' } }],
        [],
      );
    });
  });

  describe('fetchAwards', () => {
    let mock;

    beforeEach(() => {
      mock = new MockAdapter(axios);
    });

    afterEach(() => {
      mock.restore();
    });

    describe('success', () => {
      describe.each`
        relativeRootUrl
        ${null}
        ${'/gitlab'}
      `('with relative_root_url as $relativeRootUrl', ({ relativeRootUrl }) => {
        beforeEach(() => {
          window.gon = { relative_url_root: relativeRootUrl };
          mock
            .onGet(`${relativeRootUrl || ''}/awards`, { params: { per_page: 100, page: '1' } })
            .reply(HTTP_STATUS_OK, [EMOJI_THUMBS_UP], { 'x-next-page': '2' });
          mock
            .onGet(`${relativeRootUrl || ''}/awards`, { params: { per_page: 100, page: '2' } })
            .reply(HTTP_STATUS_OK, [EMOJI_THUMBS_DOWN]);
        });

        it('commits FETCH_AWARDS_SUCCESS', async () => {
          await testAction(
            actions.fetchAwards,
            '1',
            { path: '/awards' },
            [{ type: 'FETCH_AWARDS_SUCCESS', payload: [EMOJI_THUMBS_UP] }],
            [{ type: 'fetchAwards', payload: '2' }],
          );
        });
      });
    });

    describe('error', () => {
      beforeEach(() => {
        mock.onGet('/awards').reply(HTTP_STATUS_INTERNAL_SERVER_ERROR);
      });

      it('calls Sentry.captureException', async () => {
        await testAction(actions.fetchAwards, null, { path: '/awards' }, [], []);
        expect(Sentry.captureException).toHaveBeenCalled();
      });
    });
  });

  describe('toggleAward', () => {
    let mock;

    const optimisticAwardId = Number.MAX_SAFE_INTEGER - 1;
    const makeOptimisticAddMutation = (
      id = optimisticAwardId,
      name = null,
      userId = window.gon.current_user_id,
    ) => ({
      type: 'ADD_NEW_AWARD',
      payload: {
        id,
        name,
        user: {
          id: userId,
        },
      },
    });
    const makeOptimisticRemoveMutation = (id = optimisticAwardId) => ({
      type: 'REMOVE_AWARD',
      payload: id,
    });

    beforeEach(() => {
      mock = new MockAdapter(axios);
    });

    afterEach(() => {
      mock.restore();
    });

    describe.each`
      relativeRootUrl
      ${null}
      ${'/gitlab'}
    `('with relative_root_url as $relativeRootUrl', ({ relativeRootUrl }) => {
      beforeEach(() => {
        window.gon = { relative_url_root: relativeRootUrl };
      });

      describe('adding new award', () => {
        describe('success', () => {
          beforeEach(() => {
            mock.onPost(`${relativeRootUrl || ''}/awards`).reply(HTTP_STATUS_OK, { id: 1 });
          });

          it('adds an optimistic award, removes it, and then commits ADD_NEW_AWARD', () => {
            testAction(actions.toggleAward, null, { path: '/awards', awards: [] }, [
              makeOptimisticAddMutation(),
              makeOptimisticRemoveMutation(),
              { type: 'ADD_NEW_AWARD', payload: { id: 1 } },
            ]);
          });
        });

        describe('error', () => {
          beforeEach(() => {
            mock.onPost(`${relativeRootUrl || ''}/awards`).reply(HTTP_STATUS_INTERNAL_SERVER_ERROR);
          });

          it('calls Sentry.captureException', async () => {
            await testAction(
              actions.toggleAward,
              null,
              { path: '/awards', awards: [] },
              [makeOptimisticAddMutation(), makeOptimisticRemoveMutation()],
              [],
            );
            expect(Sentry.captureException).toHaveBeenCalled();
          });
        });
      });

      describe('adding another tone of an emoji the user reacted with', () => {
        const ownAward = { id: 7, name: EMOJI_THUMBS_UP, user: { id: 1 } };
        const otherUsersAward = { id: 8, name: 'thumbsup_tone1', user: { id: 2 } };

        const state = { path: '/awards', currentUserId: 1, awards: [ownAward, otherUsersAward] };

        beforeEach(() => {
          window.gon = { relative_url_root: relativeRootUrl, emoji_skin_tone: 'medium' };
        });

        it("drops the user's other tones with the add, as the server does", () => {
          mock.onPost(`${relativeRootUrl || ''}/awards`).reply(HTTP_STATUS_OK, { id: 9 });

          return testAction(actions.toggleAward, 'thumbsup_tone3', state, [
            makeOptimisticRemoveMutation(7),
            makeOptimisticAddMutation(6, 'thumbsup_tone3', undefined),
            makeOptimisticRemoveMutation(6),
            { type: 'ADD_NEW_AWARD', payload: { id: 9 } },
          ]);
        });

        it("restores the user's other tones when the add fails", async () => {
          mock.onPost(`${relativeRootUrl || ''}/awards`).reply(HTTP_STATUS_INTERNAL_SERVER_ERROR);

          await testAction(actions.toggleAward, 'thumbsup_tone3', state, [
            makeOptimisticRemoveMutation(7),
            makeOptimisticAddMutation(6, 'thumbsup_tone3', undefined),
            { type: 'ADD_NEW_AWARD', payload: ownAward },
            makeOptimisticRemoveMutation(6),
          ]);
          expect(Sentry.captureException).toHaveBeenCalled();
        });
      });

      describe('removing an award', () => {
        const mockData = { id: 1, name: EMOJI_THUMBS_UP, user: { id: 1 } };

        describe('success', () => {
          beforeEach(() => {
            mock.onDelete(`${relativeRootUrl || ''}/awards/1`).reply(HTTP_STATUS_OK);
          });

          it('commits REMOVE_AWARD', () => {
            testAction(
              actions.toggleAward,
              EMOJI_THUMBS_UP,
              {
                path: '/awards',
                currentUserId: 1,
                awards: [mockData],
              },
              [{ type: 'REMOVE_AWARD', payload: 1 }],
            );
          });
        });

        describe('error', () => {
          const currentUserId = 1;
          const name = EMOJI_THUMBS_UP;

          beforeEach(() => {
            mock
              .onDelete(`${relativeRootUrl || ''}/awards/1`)
              .reply(HTTP_STATUS_INTERNAL_SERVER_ERROR);
          });

          it('calls Sentry.captureException', async () => {
            await testAction(
              actions.toggleAward,
              name,
              {
                path: '/awards',
                currentUserId,
                awards: [mockData],
              },
              [makeOptimisticRemoveMutation(1), makeOptimisticAddMutation(1, name, currentUserId)],
              [],
            );
            expect(Sentry.captureException).toHaveBeenCalled();
          });
        });
      });
    });
  });
});
