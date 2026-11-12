import { parseRepositoryAppDataset } from '~/repository/utils/parse_repository_app_dataset';

describe('parseRepositoryAppDataset', () => {
  const baseDataset = {
    projectId: '1',
    projectPath: 'group/project',
    projectShortPath: 'project',
    fullName: 'Group / Project',
    resourceId: 'gid://gitlab/Project/1',
    ref: 'feature/#123',
    escapedRef: 'feature/%23123',
    refType: 'heads',
    suggestedTargetBranch: 'user-main-patch-1',
    historyLink: '/group/project/-/commits/feature/%23123',
    canDownloadCode: 'true',
    hasRevsFile: 'false',
    explainCodeAvailable: 'true',
    breadcrumbsCanCollaborate: 'true',
  };

  const forkDataset = {
    forked: 'true',
    sourceName: 'Upstream / Project',
    sourcePath: '/upstream/project',
    sourceDefaultBranch: 'main',
    canSyncBranch: 'true',
    aheadComparePath: '/ahead',
    behindComparePath: '/behind',
    createMrPath: '/create_mr',
  };

  it('returns the values the bootstrap needs', () => {
    expect(parseRepositoryAppDataset(baseDataset)).toMatchObject({
      projectPath: 'group/project',
      projectShortPath: 'project',
      fullName: 'Group / Project',
      ref: 'feature/#123',
      escapedRef: 'feature/%23123',
    });
  });

  it('returns the root props', () => {
    expect(parseRepositoryAppDataset(baseDataset).props).toEqual({
      projectPath: 'group/project',
      projectId: '1',
      currentRef: 'feature/#123',
      refType: 'heads',
      historyLink: '/group/project/-/commits/feature/%23123',
      forkInfo: null,
    });
  });

  it('merges the header area provide with the repository app keys', () => {
    expect(parseRepositoryAppDataset(baseDataset).provide).toMatchObject({
      resourceId: 'gid://gitlab/Project/1',
      explainCodeAvailable: true,
      canDownloadCode: true,
      hasRevsFile: false,
      originalBranch: 'feature/#123',
      selectedBranch: 'user-main-patch-1',
      canCollaborate: true,
      isReadmeView: false,
    });
  });

  it('returns fork info props with the plain ref when the fork keys are present', () => {
    expect(parseRepositoryAppDataset({ ...baseDataset, ...forkDataset }).props.forkInfo).toEqual({
      canSyncBranch: true,
      projectPath: 'group/project',
      selectedBranch: 'feature/#123',
      sourceName: 'Upstream / Project',
      sourcePath: '/upstream/project',
      sourceDefaultBranch: 'main',
      aheadComparePath: '/ahead',
      behindComparePath: '/behind',
      createMrPath: '/create_mr',
      viewMrPath: undefined,
    });
  });

  it('returns fork info props without source keys when the fork source is not visible', () => {
    expect(parseRepositoryAppDataset({ ...baseDataset, forked: 'true' }).props.forkInfo).toEqual(
      expect.objectContaining({
        projectPath: 'group/project',
        selectedBranch: 'feature/#123',
        sourceName: undefined,
        sourcePath: undefined,
      }),
    );
  });

  it('returns no fork info when the project is not a fork', () => {
    expect(parseRepositoryAppDataset({ ...baseDataset, forked: 'false' }).props.forkInfo).toBe(
      null,
    );
  });
});
