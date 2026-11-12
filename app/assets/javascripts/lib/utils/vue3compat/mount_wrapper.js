/**
 * Vue 2 `new Vue({ el })` REPLACES the mount element, while Vue 3
 * `createApp(...).mount(el)` renders INTO it. These helpers emulate the
 * Vue 2 replace semantics for Vue 3 mounts so that both runtimes produce
 * the same DOM: mount into a temporary `display: contents` wrapper, then
 * swap the target element with the rendered nodes.
 *
 * By default the wrapper is appended to the target element. With
 * `nextToTarget`, it is inserted before the target element instead, and the
 * rendered nodes are moved without resetting their state (see
 * `mountsNextToTarget` in ./init_vue_app.js).
 *
 * Used by the `new Vue` compat shim (./vue.js) and by `initVueApp`
 * (./init_vue_app.js). Keep every Vue 3 mount path on this single
 * implementation so the mount semantics cannot drift.
 */

/**
 * Creates the wrapper element the Vue 3 app should be mounted into.
 *
 * @param {Element} targetEl - The element the app root will eventually replace.
 * @param {Object} [options]
 * @param {boolean} [options.nextToTarget] - Insert the wrapper before the target element.
 * @returns {HTMLDivElement}
 */
export function createMountWrapper(targetEl, { nextToTarget = false } = {}) {
  const wrapperEl = document.createElement('div');
  wrapperEl.style.display = 'contents';
  wrapperEl.dataset.info = 'gitlab-vue3-compat-wrapper';
  if (nextToTarget && targetEl.parentElement) {
    targetEl.before(wrapperEl);
  } else {
    // We need to have it in real HTML otherwise accessing for example attached CSS vars might fail
    targetEl.appendChild(wrapperEl);
  }
  return wrapperEl;
}

function moveKeepingState(targetEl, wrapperEl) {
  const parentEl = targetEl.parentElement;
  if (parentEl.isConnected && 'moveBefore' in parentEl) {
    // moveBefore keeps the state of moved nodes, such as focus set while mounting.
    for (const node of [...wrapperEl.childNodes]) parentEl.moveBefore(node, targetEl);
    targetEl.remove();
  } else {
    const focusedEl = wrapperEl.contains(document.activeElement) ? document.activeElement : null;
    targetEl.replaceWith(...wrapperEl.childNodes);
    focusedEl?.focus({ preventScroll: true });
  }
  wrapperEl.remove();
}

/**
 * Replaces the target element with everything the app rendered into the
 * wrapper, marking rendered element roots with `data-gitlab-vue3-app`.
 *
 * @param {Element} targetEl - The element passed to createMountWrapper.
 * @param {Element} wrapperEl - The wrapper returned by createMountWrapper.
 * @param {string} [appName] - Name of the app, used for the data attribute.
 */
export function replaceWithMountWrapperContents(targetEl, wrapperEl, appName) {
  // Mark Vue 3 apps in production
  for (const node of wrapperEl.childNodes) {
    if (node.nodeType === Node.ELEMENT_NODE) {
      // Can be located with `document.querySelectorAll('[data-gitlab-vue3-app]')`
      node.dataset.gitlabVue3App = appName || '';
    }
  }

  if (wrapperEl.parentElement !== targetEl) {
    moveKeepingState(targetEl, wrapperEl);
    return;
  }

  const fragment = new DocumentFragment();
  fragment.replaceChildren(...wrapperEl.childNodes);
  targetEl.replaceWith(fragment);
}
