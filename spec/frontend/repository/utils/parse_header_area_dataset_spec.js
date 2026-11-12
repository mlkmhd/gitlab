import * as Sentry from '~/sentry/sentry_browser_wrapper';
import { parseHeaderAreaProvide } from '~/repository/utils/parse_header_area_dataset';

jest.mock('~/sentry/sentry_browser_wrapper');

describe('parseHeaderAreaProvide', () => {
  const dataset = {
    ref: 'feature/#123',
    rootRef: 'main',
    projectRootPath: '/group/project',
    comparePath: '/group/project/-/compare',
    sshUrl: 'ssh://git@gitlab.com/group/project.git',
    showNoSshKeyMessage: 'true',
    isBinary: 'false',
    breadcrumbsCanCollaborate: 'true',
    breadcrumbsCanEditTree: 'false',
    breadcrumbsCanPushCode: 'true',
    breadcrumbsCanPushToBranch: 'false',
    breadcrumbsNewBlobPath: '/group/project/-/new/main',
    breadcrumbsUploadPath: '/group/project/-/create/main',
    webIdeButtonOptions: JSON.stringify({
      is_blob: false,
      show_web_ide_button: true,
      show_gitpod_button: false,
      gitpod_enabled: true,
      gitpod_url: 'https://ona.example.com#https://gitlab.com/group/project/-/tree/main',
      show_edit_button: true,
      show_pipeline_editor_button: true,
      web_ide_url: '/-/ide/project/group/project/edit/main/-/file.js',
      edit_url: '/group/project/-/edit/main/file.js',
      pipeline_editor_url: '/group/project/-/ci/editor?branch_name=main',
    }),
    downloadLinks: JSON.stringify([{ text: 'zip', path: '/archive.zip' }]),
    customCodeDropdownClients: JSON.stringify([{ display_name: 'Client', url_template: 'x' }]),
  };

  const reportedKeys = () => Sentry.captureException.mock.calls.map(([, { extra }]) => extra.key);

  it('maps the dataset to the provided keys and parses booleans', () => {
    expect(parseHeaderAreaProvide(dataset)).toMatchObject({
      originalBranch: 'feature/#123',
      rootRef: 'main',
      canCollaborate: true,
      canEditTree: false,
      canPushCode: true,
      canPushToBranch: false,
      newBlobPath: '/group/project/-/new/main',
      uploadPath: '/group/project/-/create/main',
      projectRootPath: '/group/project',
      comparePath: '/group/project/-/compare',
      sshUrl: 'ssh://git@gitlab.com/group/project.git',
      showNoSshKeyMessage: true,
      isReadmeView: false,
    });
  });

  it('passes the selected branch and readme view through', () => {
    expect(
      parseHeaderAreaProvide(dataset, { selectedBranch: 'user-main-patch-1', isReadmeView: true }),
    ).toMatchObject({ selectedBranch: 'user-main-patch-1', isReadmeView: true });
  });

  it('parses the JSON values without reporting errors', () => {
    expect(parseHeaderAreaProvide(dataset)).toMatchObject({
      showWebIdeButton: true,
      isGitpodEnabledForInstance: false,
      isGitpodEnabledForUser: true,
      gitpodUrl: 'https://ona.example.com#https://gitlab.com/group/project/-/tree/main',
      downloadLinks: [{ text: 'zip', path: '/archive.zip' }],
      customCodeDropdownClients: [{ displayName: 'Client', urlTemplate: 'x' }],
    });
    expect(Sentry.captureException).not.toHaveBeenCalled();
  });

  // They describe the page-load file and go stale after client-side navigation.
  // Blob routes get them from the blob controls query instead.
  it.each([
    'showEditButton',
    'showPipelineEditorButton',
    'webIdeUrl',
    'editUrl',
    'pipelineEditorUrl',
  ])('does not provide the page-load %s', (key) => {
    expect(parseHeaderAreaProvide(dataset)).not.toHaveProperty(key);
  });

  const ALL_JSON_KEYS = ['webIdeButtonOptions', 'downloadLinks', 'customCodeDropdownClients'];

  it.each`
    description    | value          | expectedReportedKeys
    ${'missing'}   | ${undefined}   | ${[]}
    ${'malformed'} | ${'{not json'} | ${ALL_JSON_KEYS}
    ${'null'}      | ${'null'}      | ${ALL_JSON_KEYS}
    ${'a string'}  | ${'"text"'}    | ${ALL_JSON_KEYS}
  `(
    'falls back without throwing when the JSON values are $description',
    ({ value, expectedReportedKeys }) => {
      const provide = parseHeaderAreaProvide({
        ...dataset,
        webIdeButtonOptions: value,
        downloadLinks: value,
        customCodeDropdownClients: value,
      });

      expect(provide).toMatchObject({
        showWebIdeButton: false,
        gitpodUrl: undefined,
        downloadLinks: null,
        customCodeDropdownClients: [],
      });
      expect(reportedKeys()).toEqual(expectedReportedKeys);
    },
  );

  it('falls back and reports when array values are objects', () => {
    const provide = parseHeaderAreaProvide({
      ...dataset,
      downloadLinks: '{}',
      customCodeDropdownClients: '{}',
    });

    expect(provide).toMatchObject({ downloadLinks: null, customCodeDropdownClients: [] });
    expect(reportedKeys()).toEqual(['downloadLinks', 'customCodeDropdownClients']);
  });
});
