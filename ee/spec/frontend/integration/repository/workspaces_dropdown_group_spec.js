import userWorkspacesList from 'test_fixtures/graphql/repository/integration/user_workspaces_list.query.graphql.json';
import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import {
  getText,
  screen,
  waitAndClick,
  waitForAssertion,
  waitForElement,
  within,
} from 'ee_jest/integration/helpers/test_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { getWorkspacesNamespaceClusterAgents } from 'ee_jest/integration/repository/fixture_variants';
import {
  mountHeaderArea,
  mountBlobHeaderArea,
  findCodeDropdownToggle,
  findEnabledEditDropdownToggle,
  DEFAULT_BRANCH,
  PROJECT_FULL_PATH,
} from './test_setup';

const [WORKSPACE] = userWorkspacesList.data.currentUser.workspaces.nodes;
const NEW_WORKSPACE_PATH = `/-/remote_development/workspaces/new?project=${encodeURIComponent(PROJECT_FULL_PATH)}`;
const REMOTE_DEVELOPMENT = { glLicensedFeatures: { remoteDevelopment: true } };

const findWorkspaceLink = () => screen.queryByRole('link', { name: WORKSPACE.name });
const findStateIndicator = () => screen.queryByTestId('workspace-state-indicator');
const findNewWorkspaceButton = () => screen.queryByTestId('new-workspace-button');
const findNoWorkspacesMessage = () => screen.queryByTestId('no-workspaces-message');
const findTroubleshootingLink = () => screen.queryByTestId('workspaces-troubleshooting-doc-link');
const findWorkspaceActionsToggle = () => {
  const dropdown = screen.queryByTestId('workspace-actions-dropdown');
  return dropdown ? within(dropdown).queryByTestId('base-dropdown-toggle') : null;
};
const findStopAction = () => screen.queryByTestId('workspace-stop-button');
const findTerminateAction = () => screen.queryByTestId('workspace-terminate-button');

describe.each`
  page                  | mount                  | findToggle                       | newWorkspaceHref
  ${'project overview'} | ${mountHeaderArea}     | ${findCodeDropdownToggle}        | ${`${NEW_WORKSPACE_PATH}&gitRef=${DEFAULT_BRANCH}`}
  ${'blob'}             | ${mountBlobHeaderArea} | ${findEnabledEditDropdownToggle} | ${NEW_WORKSPACE_PATH}
`('Workspaces dropdown group on the $page page', ({ mount, findToggle, newWorkspaceHref }) => {
  beforeEach(async () => {
    await mount(REMOTE_DEVELOPMENT);
    await waitAndClick(findToggle);
  });

  it("lists the user's workspace and links to a new workspace for this project", async () => {
    const link = await waitForElement(findWorkspaceLink);

    expect(link.getAttribute('href')).toBe(WORKSPACE.url);
    expect(getText(findStateIndicator())).toBe('Running');
    expect(findNewWorkspaceButton().getAttribute('href')).toBe(newWorkspaceHref);
    expect(lastRequestVariables('userWorkspacesList').projectIds).toEqual([
      'gid://gitlab/Project/1',
    ]);
  });

  it('stops the workspace from its actions menu without a page reload', async () => {
    await waitAndClick(findWorkspaceActionsToggle);

    const stop = await waitForElement(findStopAction);
    expect(findTerminateAction()).not.toBe(null);

    stop.click();

    await waitForAssertion(() => {
      expect(getText(findStateIndicator())).toBe('Stopping');
    });
  });
});

describe('Workspaces dropdown group when no cluster agent is available', () => {
  beforeEach(async () => {
    setQueryVariant(getWorkspacesNamespaceClusterAgents).noAgents();
    await mountHeaderArea(REMOTE_DEVELOPMENT);
    await waitAndClick(findCodeDropdownToggle);
  });

  it('points to the troubleshooting docs instead of offering a new workspace', async () => {
    const message = await waitForElement(findNoWorkspacesMessage);

    expect(getText(message)).toContain('No agents available to create workspaces.');
    expect(findTroubleshootingLink()).not.toBe(null);
    expect(findNewWorkspaceButton()).toBe(null);
  });
});
