import { GlIcon } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import RoleAccessSummary from 'ee/packages_and_registries/artifact_registry/repositories/detail/access/role_access_summary.vue';

describe('ArtifactRegistryRoleAccessSummary', () => {
  let wrapper;

  const texts = (wrappers) => wrappers.wrappers.map((w) => w.text().replace(/\s+/g, ' '));
  const findAllowed = () => texts(wrapper.findAllByTestId('allowed-permission'));
  const findDenied = () => texts(wrapper.findAllByTestId('denied-permission'));
  const findItems = () => wrapper.findAll('li');

  const createComponent = (role) => {
    wrapper = shallowMountExtended(RoleAccessSummary, { propsData: { role } });
  };

  it('is titled Permission summary', () => {
    createComponent('ARTIFACT_VIEWER');

    expect(wrapper.find('h3').text()).toBe('Permission summary');
  });

  it.each`
    role                      | allowed                                                                                                                                                                                                                     | denied
    ${'ARTIFACT_VIEWER'}      | ${['Allowed: View the list of artifacts in this repository', 'Allowed: View artifact metadata (tags, versions, size, upload date)', 'Allowed: Download or pull artifacts (for example, Docker pulls or package installs)']} | ${['Not allowed: Push, upload, or delete artifacts', 'Not allowed: Manage roles and settings']}
    ${'ARTIFACT_CONTRIBUTOR'} | ${['Allowed: Everything an Artifact Viewer can do', 'Allowed: Push and upload artifacts']}                                                                                                                                  | ${['Not allowed: Delete artifacts', 'Not allowed: Manage roles and settings']}
    ${'ARTIFACT_MANAGER'}     | ${['Allowed: Everything an Artifact Contributor can do', 'Allowed: Delete artifacts', 'Allowed: Configure this repository']}                                                                                                | ${['Not allowed: Delete this repository', 'Not allowed: Manage roles']}
    ${'ARTIFACT_ADMIN'}       | ${['Allowed: Everything an Artifact Manager can do', 'Allowed: Delete this repository', 'Allowed: Add members to this repository and change their roles', 'Allowed: Remove members from this repository']}                  | ${[]}
  `('lists what $role may and may not do', ({ role, allowed, denied }) => {
    createComponent(role);

    expect(findAllowed()).toEqual(allowed);
    expect(findDenied()).toEqual(denied);
  });

  it('lists the allowed permissions before the denied ones', () => {
    createComponent('ARTIFACT_MANAGER');

    expect(findItems().wrappers.map((li) => li.attributes('data-testid'))).toEqual([
      'allowed-permission',
      'allowed-permission',
      'allowed-permission',
      'denied-permission',
      'denied-permission',
    ]);
  });

  it('marks allowed with a check and denied with a cross, each spelled out for screen readers', () => {
    createComponent('ARTIFACT_MANAGER');

    const [allowed, , , denied] = findItems().wrappers;

    expect(allowed.findComponent(GlIcon).props('name')).toBe('check');
    expect(allowed.find('.gl-sr-only').text()).toBe('Allowed:');
    expect(denied.findComponent(GlIcon).props('name')).toBe('close');
    expect(denied.find('.gl-sr-only').text()).toBe('Not allowed:');
  });
});
