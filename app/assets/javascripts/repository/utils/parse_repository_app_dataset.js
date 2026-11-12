import { parseBoolean } from '@gitlab/frontend-utils';
import { parseHeaderAreaProvide } from './parse_header_area_dataset';

const parseForkInfo = (dataset, { projectPath, ref }) => {
  // Fork keys are omitted when the source is not visible, but ForkInfo still renders the
  // "inaccessible project" notice for those forks, so gate on `forked` instead.
  if (!parseBoolean(dataset.forked)) return null;

  return {
    canSyncBranch: parseBoolean(dataset.canSyncBranch),
    projectPath,
    selectedBranch: ref,
    sourceName: dataset.sourceName,
    sourcePath: dataset.sourcePath,
    sourceDefaultBranch: dataset.sourceDefaultBranch,
    aheadComparePath: dataset.aheadComparePath,
    behindComparePath: dataset.behindComparePath,
    createMrPath: dataset.createMrPath,
    viewMrPath: dataset.viewMrPath,
  };
};

// Parses the `#js-repository-app` dataset (TreeHelper#vue_repository_app_data)
// once into the root `props` and the single `provide`.
export const parseRepositoryAppDataset = (dataset) => {
  const {
    projectId,
    projectPath,
    projectShortPath,
    fullName,
    resourceId,
    ref,
    escapedRef,
    refType,
    historyLink,
    canDownloadCode,
    hasRevsFile,
    explainCodeAvailable,
  } = dataset;

  return {
    projectPath,
    projectShortPath,
    fullName,
    ref,
    escapedRef,
    props: {
      projectPath,
      projectId,
      currentRef: ref,
      refType,
      historyLink,
      forkInfo: parseForkInfo(dataset, { projectPath, ref }),
    },
    provide: {
      ...parseHeaderAreaProvide(dataset, { selectedBranch: dataset.suggestedTargetBranch }),
      resourceId,
      explainCodeAvailable: parseBoolean(explainCodeAvailable),
      canDownloadCode: parseBoolean(canDownloadCode),
      hasRevsFile: parseBoolean(hasRevsFile),
    },
  };
};
