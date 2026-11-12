import { parseBoolean } from '@gitlab/frontend-utils';
import { convertObjectPropsToCamelCase } from '~/lib/utils/common_utils';
import { isObject } from '~/lib/utils/type_utility';
import * as Sentry from '~/sentry/sentry_browser_wrapper';

// One malformed value must not stop the header from mounting, so JSON values
// fall back instead of throwing. The backend always sends valid values, so a
// parse failure or wrong shape is a backend bug worth reporting.
const parseJSON = (value, { key, fallback, isValid }) => {
  if (!value) return fallback;

  try {
    const parsed = JSON.parse(value);
    if (!isValid(parsed)) throw new TypeError(`Unexpected ${key} in the repository dataset`);
    return parsed;
  } catch (error) {
    Sentry.captureException(error, { extra: { key } });
    return fallback;
  }
};

const parseWebIdeButtonOptions = (value) =>
  convertObjectPropsToCamelCase(
    parseJSON(value, { key: 'webIdeButtonOptions', fallback: {}, isValid: isObject }),
  );

const parseDownloadLinks = (value) =>
  parseJSON(value, { key: 'downloadLinks', fallback: null, isValid: Array.isArray });

export const parseCustomCodeDropdownClients = (value) =>
  parseJSON(value, { key: 'customCodeDropdownClients', fallback: [], isValid: Array.isArray }).map(
    (client) => convertObjectPropsToCamelCase(client),
  );

// The `provide` of HeaderArea, shared by the readme view, the legacy repository
// pages and RepositoryApp. They send the target branch for new files under
// different dataset keys, so callers pass it as `selectedBranch`.
export const parseHeaderAreaProvide = (dataset, { selectedBranch, isReadmeView = false } = {}) => {
  const {
    ref,
    rootRef,
    projectRootPath,
    comparePath,
    sshUrl,
    httpUrl,
    xcodeUrl,
    kerberosUrl,
    showNoSshKeyMessage,
    userSettingsSshKeysPath,
    newWorkspacePath,
    organizationId,
    breadcrumbsCanCollaborate,
    breadcrumbsCanEditTree,
    breadcrumbsCanPushCode,
    breadcrumbsCanPushToBranch,
    breadcrumbsNewBranchPath,
    breadcrumbsNewTagPath,
    breadcrumbsNewBlobPath,
    breadcrumbsForkNewBlobPath,
    breadcrumbsForkNewDirectoryPath,
    breadcrumbsForkUploadBlobPath,
    breadcrumbsUploadPath,
    breadcrumbsNewDirPath,
  } = dataset;

  const {
    isFork,
    needsToFork,
    gitpodEnabled,
    showWebIdeButton,
    showGitpodButton,
    gitpodUrl,
    userPreferencesGitpodPath,
    userProfileEnableGitpodPath,
  } = parseWebIdeButtonOptions(dataset.webIdeButtonOptions);

  return {
    canCollaborate: parseBoolean(breadcrumbsCanCollaborate),
    canEditTree: parseBoolean(breadcrumbsCanEditTree),
    canPushCode: parseBoolean(breadcrumbsCanPushCode),
    canPushToBranch: parseBoolean(breadcrumbsCanPushToBranch),
    originalBranch: ref,
    selectedBranch,
    newBranchPath: breadcrumbsNewBranchPath,
    newTagPath: breadcrumbsNewTagPath,
    newBlobPath: breadcrumbsNewBlobPath,
    forkNewBlobPath: breadcrumbsForkNewBlobPath,
    forkNewDirectoryPath: breadcrumbsForkNewDirectoryPath,
    forkUploadBlobPath: breadcrumbsForkUploadBlobPath,
    uploadPath: breadcrumbsUploadPath,
    newDirPath: breadcrumbsNewDirPath,
    projectRootPath,
    comparePath,
    isReadmeView,
    isFork: parseBoolean(isFork),
    needsToFork: parseBoolean(needsToFork),
    isGitpodEnabledForUser: parseBoolean(gitpodEnabled),
    showWebIdeButton: parseBoolean(showWebIdeButton),
    isGitpodEnabledForInstance: parseBoolean(showGitpodButton),
    gitpodUrl,
    userPreferencesGitpodPath,
    userProfileEnableGitpodPath,
    httpUrl,
    xcodeUrl,
    sshUrl,
    kerberosUrl,
    newWorkspacePath,
    downloadLinks: parseDownloadLinks(dataset.downloadLinks),
    showNoSshKeyMessage: parseBoolean(showNoSshKeyMessage),
    userSettingsSshKeysPath,
    rootRef,
    organizationId,
    customCodeDropdownClients: parseCustomCodeDropdownClients(dataset.customCodeDropdownClients),
  };
};
