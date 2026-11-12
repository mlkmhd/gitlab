import { getBaseURL, mergeUrlParams, relativePathToAbsolute } from '~/lib/utils/url_utility';

/**
 * Whether the route renders a blob (as opposed to a tree or the project root)
 *
 * @param {Object} route - A Vue Router route
 * @returns {Boolean}
 */
export const isBlobRoute = (route) => Boolean(route?.name?.startsWith('blobPath'));

/**
 * Points a server-built fork path at a new `continue[to]` destination,
 * keeping its other params (namespace, notices) as they are
 *
 * @param {String} forkPath - A fork path with a `continue` param
 * @param {String} to - Where the fork should continue to
 * @returns {String}
 */
export const withContinueTo = (forkPath, to) => {
  if (!forkPath) return forkPath;

  return mergeUrlParams({ 'continue[to]': to }, forkPath);
};

/**
 * Points a server-built Gitpod URL at a new target URL. The target is everything
 * after the last `#`, because the server percent-encodes `#` in the target path.
 *
 * @param {String} gitpodUrl - `<gitpod instance url>#<target url>`, or empty if Gitpod is unavailable
 * @param {String} targetUrl - The absolute URL Gitpod should open
 * @returns {String}
 */
export const withGitpodTarget = (gitpodUrl, targetUrl) => {
  if (!gitpodUrl) return '';

  const separatorIndex = gitpodUrl.lastIndexOf('#');
  const gitpodBaseUrl = separatorIndex === -1 ? gitpodUrl : gitpodUrl.slice(0, separatorIndex);

  return `${gitpodBaseUrl}#${targetUrl}`;
};

/**
 * Generates an absolute permalink path with proper handling of URL hash
 *
 * @param {String} permalinkPath - The relative permalink path
 * @param {String} hash - The URL hash (after #)
 * @param {Object} queryParams - Additional query parameters to preserve (e.g., { blame: '1' })
 * @returns {String} - The absolute permalink path with hash handling
 */
export const getAbsolutePermalinkPath = (permalinkPath, inputHash, queryParams = {}) => {
  const baseAbsolutePath = relativePathToAbsolute(permalinkPath, getBaseURL());

  const hash = inputHash || '';

  const params = Object.fromEntries(
    Object.entries(queryParams).filter(([, v]) => v !== undefined && v !== null && v !== ''),
  );

  // Ensure hash starts with # if it doesn't already
  let normalizedHash = '';
  if (hash.trim()) {
    normalizedHash = hash.startsWith('#') ? hash : `#${hash}`;
  }

  const hasParams = Object.keys(params).length > 0;
  const url = hasParams
    ? mergeUrlParams(params, `${baseAbsolutePath}${normalizedHash}`)
    : `${baseAbsolutePath}${normalizedHash}`;

  return url;
};
