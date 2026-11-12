import { useMockIntersectionObserver } from 'helpers/mock_dom_observer';
import { InfiniteScroller } from '~/infinite_scroller';
import { resetHTMLFixture, setHTMLFixture } from 'helpers/fixtures';
import waitForPromises from 'helpers/wait_for_promises';

describe('Infinite scroller', () => {
  let fetchNextPage;
  let rejectNextPage;
  let resolveNextPage;
  let resolveLastPage;
  let limit;
  let scroller;
  let startingOffset;
  let signal;
  const { trigger: triggerIntersection } = useMockIntersectionObserver();

  const getRoot = () => document.querySelector('.js-infinite-scrolling-root');
  const getContent = () => document.querySelector('.js-infinite-scrolling-content');
  const getPageEnd = () => document.querySelector('.js-infinite-scrolling-page-end');
  const getLoading = () => document.querySelector('.js-infinite-scrolling-loading');

  const createScroller = () => {
    scroller = new InfiniteScroller({
      fetchNextPage,
      root: getRoot(),
      limit,
      startingOffset,
    });
    scroller.initialize();
  };

  const triggerNextPage = () => {
    triggerIntersection(getPageEnd(), { entry: { isIntersecting: true } });
  };

  beforeEach(() => {
    startingOffset = undefined;
    limit = 20;
    fetchNextPage = jest.fn((offset, abortSignal) => {
      signal = abortSignal;
      return new Promise((resolve, reject) => {
        rejectNextPage = reject;
        resolveNextPage = (nextPage = { count: limit, html: `<div>content</div>` }) =>
          resolve(nextPage);
        resolveLastPage = (nextPage = { count: 0, html: `<div>empty</div>` }) => resolve(nextPage);
      });
    });
    setHTMLFixture(`
      <div class="js-infinite-scrolling-root">
        <div class="js-infinite-scrolling-content"></div>
        <div class="js-infinite-scrolling-page-end">
          <div class="js-infinite-scrolling-loading"></div>
        </div>
      </div>
    `);
  });

  afterEach(() => {
    scroller?.destroy();
    resetHTMLFixture();
  });

  it('loads initial page', async () => {
    createScroller();
    triggerNextPage();
    await resolveNextPage();
    expect(getContent().textContent).toBe('content');
    expect(fetchNextPage).toHaveBeenCalledWith(0, expect.any(AbortSignal));
    resolveLastPage();
  });

  it('loads initial page with starting offset', async () => {
    startingOffset = 20;
    createScroller({ startingOffset });
    triggerNextPage();
    await resolveNextPage();
    expect(getContent().textContent).toBe('content');
    expect(fetchNextPage).toHaveBeenCalledWith(startingOffset, expect.any(AbortSignal));
    resolveLastPage();
  });

  it('loads page after page', async () => {
    createScroller();
    triggerNextPage();
    await resolveNextPage();
    triggerNextPage();
    await resolveNextPage();
    triggerNextPage();
    await resolveNextPage();
    expect(getContent().textContent).toBe('contentcontentcontent');
    expect(fetchNextPage).toHaveBeenNthCalledWith(1, 0, expect.any(AbortSignal));
    expect(fetchNextPage).toHaveBeenNthCalledWith(2, limit, expect.any(AbortSignal));
    expect(fetchNextPage).toHaveBeenNthCalledWith(3, limit * 2, expect.any(AbortSignal));
    resolveLastPage();
  });

  it('cancels previous request on repeated intersection', () => {
    createScroller();
    const abort = jest.fn();
    triggerNextPage();
    signal.addEventListener('abort', abort);
    triggerNextPage();
    expect(abort).toHaveBeenCalled();
    resolveLastPage();
  });

  it('does not cancel finalized request on repeated intersection', async () => {
    createScroller();
    const abort = jest.fn();
    triggerNextPage();
    await resolveNextPage();
    signal.addEventListener('abort', abort);
    triggerNextPage();
    expect(abort).not.toHaveBeenCalled();
    resolveLastPage();
  });

  it('stops loading on partial page', async () => {
    createScroller();
    triggerNextPage();
    await resolveNextPage();
    triggerNextPage();
    await resolveNextPage({ count: limit / 2, html: `<div>content</div>` });
    triggerNextPage();
    await resolveNextPage();
    expect(getContent().textContent).toBe('contentcontent');
  });

  it('stops loading on empty page', async () => {
    createScroller();
    triggerNextPage();
    await resolveNextPage();
    triggerNextPage();
    await resolveLastPage();
    triggerNextPage();
    await resolveNextPage();
    expect(getContent().textContent).toBe('content');
  });

  it('shows empty message when content is empty', async () => {
    createScroller();
    triggerNextPage();
    await resolveLastPage();
    expect(getContent().textContent).toBe('empty');
  });

  it('shows loading element when loading starts', () => {
    createScroller();
    triggerNextPage();
    expect(getLoading().style.visibility).toBe('');
    resolveLastPage();
  });

  it('hides loading element when loading ends', async () => {
    createScroller();
    triggerNextPage();
    await resolveLastPage();
    expect(getLoading().style.visibility).toBe('hidden');
  });

  describe('when loading fails', () => {
    beforeEach(async () => {
      createScroller();
      triggerNextPage();
      rejectNextPage(new Error('Failed to load page'));
      await waitForPromises();
    });

    it('hides the loading element', () => {
      expect(getLoading().style.visibility).toBe('hidden');
    });

    it('does not retry on intersection', () => {
      triggerNextPage();
      expect(fetchNextPage).toHaveBeenCalledTimes(1);
    });

    describe('when a retry is requested', () => {
      let retry;

      beforeEach(() => {
        retry = scroller.retry();
      });

      afterEach(async () => {
        resolveLastPage();
        await retry;
      });

      it('shows the loading element', () => {
        expect(getLoading().style.visibility).toBe('');
      });

      it('requests the same page', () => {
        expect(fetchNextPage).toHaveBeenNthCalledWith(2, 0, expect.any(AbortSignal));
      });

      it('does not start a duplicate request', async () => {
        await scroller.retry();
        expect(fetchNextPage).toHaveBeenCalledTimes(2);
      });

      describe('when the retry fails', () => {
        beforeEach(async () => {
          rejectNextPage(new Error('Failed again'));
          await retry;
        });

        it('hides the loading element', () => {
          expect(getLoading().style.visibility).toBe('hidden');
        });

        it('allows another retry of the same page', async () => {
          const secondRetry = scroller.retry();
          expect(fetchNextPage).toHaveBeenNthCalledWith(3, 0, expect.any(AbortSignal));
          resolveLastPage();
          await secondRetry;
        });
      });
    });
  });

  describe('when a request is superseded', () => {
    let requests;

    beforeEach(() => {
      requests = [];
      fetchNextPage.mockImplementation(
        (offset, abortSignal) =>
          new Promise((resolve, reject) => {
            requests.push({ abortSignal, offset, reject, resolve });
          }),
      );
      createScroller();
      triggerNextPage();
      triggerNextPage();
    });

    afterEach(async () => {
      requests.forEach(({ resolve }) => resolve({ count: 0, html: '<div>empty</div>' }));
      await waitForPromises();
    });

    describe('when the previous request fails', () => {
      beforeEach(async () => {
        requests[0].reject(new Error('Failed to load page'));
        await waitForPromises();
      });

      it('keeps the active request available for cancellation', async () => {
        triggerNextPage();
        expect(requests[1].abortSignal.aborted).toBe(true);
        requests[1].reject(new Error('Request cancelled'));
        requests[2].resolve({ count: 0, html: '<div>empty</div>' });
        await waitForPromises();
      });
    });

    describe('when the previous request fails after the current request succeeds', () => {
      beforeEach(async () => {
        requests[1].resolve({ count: limit, html: '<div>content</div>' });
        await waitForPromises();
        requests[0].reject(new Error('Failed to load page'));
        await waitForPromises();
      });

      it('continues loading from the next offset', () => {
        triggerNextPage();
        expect(requests[2].offset).toBe(limit);
      });
    });

    describe('when the previous request succeeds', () => {
      beforeEach(async () => {
        requests[0].resolve({ count: limit, html: '<div>stale content</div>' });
        await waitForPromises();
      });

      it('discards the stale content', () => {
        expect(getContent().textContent).toBe('');
      });

      describe('when the current request succeeds', () => {
        beforeEach(async () => {
          requests[1].resolve({ count: limit, html: '<div>content</div>' });
          await waitForPromises();
        });

        it('inserts the current content', () => {
          expect(getContent().textContent).toBe('content');
        });

        it('advances the offset only once', () => {
          triggerNextPage();
          expect(requests[2].offset).toBe(limit);
        });
      });
    });
  });

  it('emits htmlInserted event', async () => {
    createScroller();
    const callback = jest.fn();
    scroller.eventTarget.addEventListener('htmlInserted', callback);
    triggerNextPage();
    await resolveNextPage();
    expect(callback).toHaveBeenCalled();
    resolveLastPage();
  });

  it('can be destroyed', async () => {
    createScroller();
    triggerNextPage();
    await resolveNextPage();
    scroller.destroy();
    triggerNextPage();
    await resolveNextPage();
    expect(getContent().textContent).toBe('content');
  });

  it('cancels the request on destroy', () => {
    createScroller();
    const abort = jest.fn();
    triggerNextPage();
    signal.addEventListener('abort', abort);
    scroller.destroy();
    expect(abort).toHaveBeenCalled();
  });

  describe('when a request fails after destruction', () => {
    let observe;

    beforeEach(async () => {
      createScroller();
      const observer = IntersectionObserver.mock.results[0].value;
      observe = jest.spyOn(observer, 'observe');
      triggerNextPage();
      scroller.destroy();
      rejectNextPage(new Error('Failed to load page'));
      await waitForPromises();
    });

    it('does not resume observing', () => {
      triggerNextPage();
      expect(observe).not.toHaveBeenCalled();
      expect(fetchNextPage).toHaveBeenCalledTimes(1);
    });
  });
});
