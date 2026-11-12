import {
  initOrganizationAccess,
  initOrganizationAccessArtifactRegistry,
} from 'ee/organizations/access';
import { resetHTMLFixture, setHTMLFixture } from 'helpers/fixtures';
import waitForPromises from 'helpers/wait_for_promises';

describe('initOrganizationAccess', () => {
  afterEach(() => {
    resetHTMLFixture();
  });

  it('returns false when the mount element is missing', () => {
    expect(initOrganizationAccess()).toBe(false);
  });

  it('mounts the app with the organization path', async () => {
    setHTMLFixture('<div id="js-organization-access" data-organization-path="my-org"></div>');

    initOrganizationAccess();
    await waitForPromises();

    expect(document.body.textContent).toContain('Organization access');
    expect(document.body.textContent).toContain('5 members');
    expect(document.body.textContent).toContain('Alex Garcia');
    expect(document.querySelector('a[href="/o/my-org/-/access/artifact-registry"]')).not.toBeNull();
  });
});

describe('initOrganizationAccessArtifactRegistry', () => {
  afterEach(() => {
    resetHTMLFixture();
  });

  it('returns false when the mount element is missing', () => {
    expect(initOrganizationAccessArtifactRegistry()).toBe(false);
  });

  describe('with an Artifact Registry', () => {
    const ORGANIZATION_GID = 'gid://gitlab/Organizations::Organization/1';
    const originalFetch = global.fetch;

    const responseFor = ({ operationName }) =>
      operationName === 'getOrganizationAccessArtifactRegistry'
        ? {
            organization: {
              __typename: 'Organization',
              id: ORGANIZATION_GID,
              artifactRegistry: { __typename: 'ArtifactRegistry', id: 'namespace-1' },
            },
          }
        : {
            artifactRegistryRoleAssignments: {
              __typename: 'ArtifactRegistryRoleAssignmentConnection',
              nodes: [],
              pageInfo: { __typename: 'PageInfo', hasNextPage: false, endCursor: null },
            },
          };

    beforeEach(() => {
      global.fetch = jest.fn().mockImplementation((_url, { body }) =>
        Promise.resolve({
          ok: true,
          status: 200,
          headers: new Map(),
          text: () => Promise.resolve(JSON.stringify({ data: responseFor(JSON.parse(body)) })),
        }),
      );
    });

    afterEach(() => {
      global.fetch = originalFetch;
    });

    it.each`
      dataAttribute                         | shown
      ${' data-can-invite-members="true"'}  | ${true}
      ${' data-can-invite-members="false"'} | ${false}
      ${''}                                 | ${false}
    `(
      'shows the Invite members button: $shown, with "$dataAttribute"',
      async ({ dataAttribute, shown }) => {
        setHTMLFixture(
          `<div id="js-organization-access-artifact-registry" data-organization-path="my-org" data-organization-gid="${ORGANIZATION_GID}"${dataAttribute}></div>`,
        );

        initOrganizationAccessArtifactRegistry();
        await waitForPromises();

        const registryRequest = global.fetch.mock.calls
          .map(([, { body }]) => JSON.parse(body))
          .find(({ operationName }) => operationName === 'getOrganizationAccessArtifactRegistry');
        expect(registryRequest.variables).toEqual({ organizationId: ORGANIZATION_GID });
        expect(document.body.textContent.includes('Invite members')).toBe(shown);
      },
    );
  });
});
