import htmlEventFilter from 'test_fixtures_static/event_filter.html';
import { setHTMLFixture, resetHTMLFixture } from 'helpers/fixtures';
import Activities from '~/activities';
import { InfiniteScroller } from '~/infinite_scroller';
import { setCookie } from '~/lib/utils/common_utils';
import axios from '~/lib/utils/axios_utils';
import { createAlert } from '~/alert';

jest.mock('~/infinite_scroller');
jest.mock('~/alert');

class FakeInfiniteScroller {
  eventTarget = new EventTarget();
  initialize = jest.fn();
  destroy = jest.fn();
  retry = jest.fn();
}

describe('Activities', () => {
  let activities;
  const filterIds = [
    'all_event_filter',
    'push_event_filter',
    'merged_event_filter',
    'comments_event_filter',
    'team_event_filter',
  ];

  beforeEach(() => {
    InfiniteScroller.mockImplementation((...args) => new FakeInfiniteScroller(...args));
    setHTMLFixture(`
      <div class="js-infinite-scrolling-root">
        <div class="js-infinite-scrolling-content">
          ${htmlEventFilter}
        </div>
        <div class="js-infinite-scrolling-page-end">
          <div class="js-infinite-scrolling-error"></div>
          <div class="js-infinite-scrolling-loading"></div>
        </div>
      </div>
    `);
    // this cookie is initially set by the server using 'set-cookie' header
    setCookie('event_filter', filterIds[0].split('_')[0]);
    activities = new Activities();
  });

  afterEach(() => {
    resetHTMLFixture();
  });

  describe.each(filterIds)("when selecting tab with an id '%s'", (id) => {
    beforeEach(() => {
      document.getElementById(id).click();
    });

    it('should highlight only the active tab', () => {
      filterIds.forEach((filterId) => {
        expect(document.getElementById(filterId).parentElement.classList.contains('active')).toBe(
          id === filterId,
        );
      });
    });
  });

  it('does not activate the tab twice', () => {
    document.getElementById(filterIds[0]).click();
    document.getElementById(filterIds[0]).click();
    expect(InfiniteScroller).toHaveBeenCalledTimes(1);
  });

  describe('loadActivities', () => {
    let fetchNextPage;
    let dismiss;
    let setPrimaryButtonLoading;

    beforeEach(() => {
      [[{ fetchNextPage }]] = InfiniteScroller.mock.calls;
      dismiss = jest.fn();
      setPrimaryButtonLoading = jest.fn();
      createAlert.mockReturnValue({ dismiss, setPrimaryButtonLoading });
      jest.spyOn(axios, 'get');
    });

    describe('when loading activity fails', () => {
      const error = new Error('Failed to load activity');
      let loadError;

      beforeEach(async () => {
        axios.get.mockRejectedValueOnce(error);
        loadError = await fetchNextPage(20, new AbortController().signal).catch(
          (failure) => failure,
        );
      });

      it('shows a nondismissible retry alert at the bottom of the timeline', () => {
        expect(loadError).toBe(error);
        expect(createAlert).toHaveBeenCalledTimes(1);
        expect(createAlert).toHaveBeenCalledWith(
          expect.objectContaining({
            containerSelector: '.js-infinite-scrolling-error',
            message: 'Failed to load more activity.',
            parent: document.querySelector('.js-infinite-scrolling-root'),
            dismissible: false,
            primaryButton: expect.objectContaining({ text: 'Retry', loading: false }),
          }),
        );
      });

      describe('when a subsequent request fails', () => {
        let subsequentError;

        beforeEach(async () => {
          axios.get.mockRejectedValueOnce(error);
          subsequentError = await fetchNextPage(20, new AbortController().signal).catch(
            (failure) => failure,
          );
        });

        it('keeps the existing alert visible', () => {
          expect(subsequentError).toBe(error);
          expect(createAlert).toHaveBeenCalledTimes(1);
          expect(dismiss).not.toHaveBeenCalled();
        });
      });

      describe('when the retry action is clicked', () => {
        let finishRetry;
        let retryClick;

        beforeEach(() => {
          activities.scroller.retry.mockImplementation(
            () =>
              new Promise((resolve) => {
                finishRetry = resolve;
              }),
          );
          const { primaryButton } = createAlert.mock.calls[0][0];
          retryClick = primaryButton.clickHandler();
        });

        afterEach(async () => {
          finishRetry();
          await retryClick;
        });

        it('shows the loading state', () => {
          expect(activities.scroller.retry).toHaveBeenCalledTimes(1);
          expect(setPrimaryButtonLoading).toHaveBeenCalledWith(true);
          expect(dismiss).not.toHaveBeenCalled();
        });

        describe('when the retry completes', () => {
          beforeEach(async () => {
            finishRetry();
            await retryClick;
          });

          it('clears the loading state', () => {
            expect(setPrimaryButtonLoading).toHaveBeenLastCalledWith(false);
          });
        });
      });

      describe('when a subsequent request is pending', () => {
        let controller;
        let request;
        let resolveRequest;
        const response = { data: { count: 0, html: '' } };

        beforeEach(() => {
          controller = new AbortController();
          axios.get.mockImplementationOnce(
            () =>
              new Promise((resolve) => {
                resolveRequest = resolve;
              }),
          );
          request = fetchNextPage(20, controller.signal);
        });

        afterEach(async () => {
          resolveRequest(response);
          await request;
        });

        it('keeps the existing alert visible', () => {
          expect(dismiss).not.toHaveBeenCalled();
        });

        describe('when the request succeeds', () => {
          beforeEach(async () => {
            resolveRequest(response);
            await request;
          });

          it('dismisses the alert', () => {
            expect(dismiss).toHaveBeenCalledTimes(1);
          });
        });

        describe('when the request succeeds after being aborted', () => {
          beforeEach(async () => {
            controller.abort();
            resolveRequest(response);
            await request;
          });

          it('ignores the response and keeps the existing alert visible', async () => {
            expect(createAlert).toHaveBeenCalledTimes(1);
            await expect(request).resolves.toBeNull();
            expect(dismiss).not.toHaveBeenCalled();
          });
        });
      });

      describe('when a different event filter is selected', () => {
        let previousScroller;

        beforeEach(() => {
          previousScroller = activities.scroller;
          document.getElementById('push_event_filter').click();
        });

        it('dismisses the alert and reloads activity', () => {
          expect(dismiss).toHaveBeenCalledTimes(1);
          expect(previousScroller.destroy).toHaveBeenCalledTimes(1);
          expect(InfiniteScroller).toHaveBeenCalledTimes(2);
          expect(activities.scroller.initialize).toHaveBeenCalledTimes(1);
        });
      });
    });

    describe('when the request is canceled', () => {
      beforeEach(() => {
        axios.get.mockRejectedValueOnce(new Error('Request canceled'));
        jest.spyOn(axios, 'isCancel').mockReturnValueOnce(true);
      });

      it('ignores the failure without showing an alert', async () => {
        await expect(fetchNextPage(20, new AbortController().signal)).resolves.toBeNull();
        expect(createAlert).not.toHaveBeenCalled();
      });
    });

    describe('when an aborted request fails', () => {
      let request;

      beforeEach(() => {
        const controller = new AbortController();
        let rejectRequest;
        axios.get.mockImplementationOnce(
          () =>
            new Promise((resolve, reject) => {
              rejectRequest = reject;
            }),
        );
        request = fetchNextPage(20, controller.signal);
        controller.abort();
        rejectRequest(new Error('Failed after abort'));
      });

      it('ignores the failure without showing an alert', async () => {
        await expect(request).resolves.toBeNull();
        expect(createAlert).not.toHaveBeenCalled();
      });
    });
  });
});
