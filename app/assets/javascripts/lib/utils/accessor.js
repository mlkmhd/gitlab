function canAccessProperty(base, property) {
  let safe;

  try {
    safe = Boolean(base[property]);
  } catch (error) {
    safe = false;
  }

  return safe;
}

function canCallFunction(base, functionName, ...args) {
  let safe = true;

  try {
    base[functionName](...args);
  } catch (error) {
    safe = false;
  }

  return safe;
}

function canUseStorage(storageName, testKey) {
  if (!canAccessProperty(window, storageName)) return false;

  const safe = canCallFunction(window[storageName], 'setItem', testKey, 'true');

  if (safe) window[storageName].removeItem(testKey);

  return safe;
}

/**
 * Determines if `window.localStorage` is available and
 * can be written to and read from.
 *
 * Important: This is not a guarantee that
 * `localStorage.setItem` will work in all cases.
 *
 * `setItem` can still throw exceptions and should be
 * surrounded with a try/catch where used.
 *
 * See: https://developer.mozilla.org/en-US/docs/Web/API/Storage/setItem#exceptions
 */
function canUseLocalStorage() {
  return canUseStorage('localStorage', 'canUseLocalStorage');
}

/**
 * Determines if `window.sessionStorage` is available and
 * can be written to and read from. The same caveats as
 * `canUseLocalStorage` apply.
 */
function canUseSessionStorage() {
  return canUseStorage('sessionStorage', 'canUseSessionStorage');
}

/**
 * Determines if `window.crypto` is available.
 */
function canUseCrypto() {
  return window.crypto?.subtle !== undefined;
}

const AccessorUtilities = {
  canUseLocalStorage,
  canUseSessionStorage,
  canUseCrypto,
};

export default AccessorUtilities;
