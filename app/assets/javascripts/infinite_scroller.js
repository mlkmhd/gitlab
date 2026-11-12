import { debounce } from 'lodash-es';

export class InfiniteScroller {
  static events = {
    htmlInserted: 'htmlInserted',
  };

  eventTarget = new EventTarget();

  #fetchNextPage = null;
  #root = null;
  #limit = null;
  #offset = null;
  #observer = null;
  #controller = null;
  #debouncedIntersectionHandler = null;
  #failed = false;

  constructor({ fetchNextPage, root, limit, startingOffset = 0 }) {
    this.#fetchNextPage = fetchNextPage;
    this.#root = root;
    this.#limit = limit;
    this.#offset = startingOffset;
    this.#debouncedIntersectionHandler = debounce(this.#handleIntersection.bind(this), 100);
  }

  initialize() {
    this.#observer = new IntersectionObserver(this.#debouncedIntersectionHandler, {
      root: document.querySelector('.js-static-panel-inner'),
    });
    this.#observer.observe(this.#getObservedElement());
  }

  destroy() {
    this.#debouncedIntersectionHandler.cancel();
    if (this.#controller) this.#controller.abort();
    if (this.#observer) {
      this.#observer.disconnect();
      this.#observer = null;
    }
  }

  setLoadingVisibility(visible) {
    const el = this.#root.querySelector('.js-infinite-scrolling-loading');
    el.style.visibility = visible ? '' : 'hidden';
  }

  async retry() {
    if (!this.#failed || !this.#observer) return false;
    this.#failed = false;
    return this.#retryLoadNextPage();
  }

  #insertPage(html, isEmptyPage) {
    const content = this.#root.querySelector('.js-infinite-scrolling-content');
    // empty page should only be inserted when there's no content
    if (content.innerHTML && isEmptyPage) return;
    // eslint-disable-next-line no-unsanitized/method
    content.insertAdjacentHTML('beforeend', html);
    this.eventTarget.dispatchEvent(new CustomEvent(InfiniteScroller.events.htmlInserted));
  }

  async #loadNextPage() {
    if (this.#controller) this.#controller.abort();
    this.setLoadingVisibility(true);
    const controller = new AbortController();
    this.#controller = controller;
    let result;
    let isCurrentRequest = false;
    try {
      result = await this.#fetchNextPage(this.#offset, controller.signal);
    } catch {
      if (this.#controller === controller && this.#observer) {
        this.setLoadingVisibility(false);
        this.#failed = true;
      }
      return false;
    } finally {
      isCurrentRequest = this.#controller === controller;
      if (isCurrentRequest) this.#controller = null;
    }
    if (!isCurrentRequest || !this.#observer || !result) return false;
    const { html, count } = result;
    this.#insertPage(html, count === 0);
    if (count !== this.#limit) {
      this.setLoadingVisibility(false);
      this.#observer?.disconnect();
      return false;
    }
    this.#offset += count;
    return true;
  }

  #getObservedElement() {
    return this.#root.querySelector('.js-infinite-scrolling-page-end');
  }

  async #retryLoadNextPage() {
    const loadNext = await this.#loadNextPage();
    if (loadNext) this.#observer?.observe(this.#getObservedElement());
    return loadNext;
  }

  async #handleIntersection([entry]) {
    if (!entry.isIntersecting || this.#failed) return;
    // we need to unobserve and observe again because
    // if the inserted content didn't move the observed element outside the viewport
    // then IntersectionObserver won't be triggered
    // so we trigger this manually
    this.#observer.unobserve(this.#getObservedElement());
    const loadNext = await this.#loadNextPage();
    if (loadNext) this.#observer?.observe(this.#getObservedElement());
  }
}
