import HighlightWorker from '~/highlight_js/workers/highlight_worker?worker';

// Workers must be same-origin, so construction throws when the page origin differs from the
// asset origin (for example, proxies or sandboxed iframes). Viewers fall back without a worker.
export const createHighlightWorker = () => {
  try {
    return new HighlightWorker();
  } catch {
    return null;
  }
};
