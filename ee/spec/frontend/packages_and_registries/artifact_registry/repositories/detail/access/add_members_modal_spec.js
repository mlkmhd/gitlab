import {
  GlAvatar,
  GlAvatarLabeled,
  GlFormGroup,
  GlModal,
  GlSprintf,
  GlTokenSelector,
} from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { RENDER_ALL_SLOTS_TEMPLATE, stubComponent } from 'helpers/stub_component';
import waitForPromises from 'helpers/wait_for_promises';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import RoleSelector from '~/members/components/role_selector.vue';
import { DEFAULT_DEBOUNCE_AND_THROTTLE_MS } from '~/lib/utils/constants';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import bulkGrantRepositoryRolesMutation from 'ee/packages_and_registries/artifact_registry/graphql/mutations/bulk_grant_repository_roles.mutation.graphql';
import getOrganizationMembersQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_organization_members.query.graphql';
import getRepositoryRoleAssignmentsQuery from 'ee/packages_and_registries/artifact_registry/graphql/queries/get_repository_role_assignments.query.graphql';
import AddMembersModal from 'ee/packages_and_registries/artifact_registry/repositories/detail/access/add_members_modal.vue';
import RoleAccessSummary from 'ee/packages_and_registries/artifact_registry/repositories/detail/access/role_access_summary.vue';
import {
  ORGANIZATION_GID,
  REPOSITORY_ID,
  mockBulkGrantRolesResponse,
  mockOrganizationMembers,
  mockOrganizationMembersResponse,
  mockRoleAssignmentsLastPage,
} from '../../../mock_data';

jest.mock('~/sentry/sentry_browser_wrapper');

Vue.use(VueApollo);

const [morgan, alix, ali] = mockOrganizationMembers.map(({ user }) => user);
const token = ({ id, name, username, avatarUrl }) => ({ id, name, username, avatarUrl });

const assignmentsVariables = { resourceId: REPOSITORY_ID, first: 100 };
const assignmentsResponse = {
  data: { artifactRegistryRoleAssignments: mockRoleAssignmentsLastPage },
};

describe('ArtifactRegistryAddMembersModal', () => {
  let wrapper;
  const hideModal = jest.fn();
  let mockApollo;
  let searchHandler;
  let grantHandler;
  let assignmentsHandler;
  let mockToast;

  const findModal = () => wrapper.findComponent(GlModal);
  const findIntro = () => wrapper.findByTestId('add-members-intro');
  const findErrors = () => wrapper.findComponentByTestId('add-members-errors');
  const findErrorLines = () =>
    findErrors()
      .findAll('li')
      .wrappers.map((li) => li.text());
  const findMembersGroup = () => wrapper.findAllComponents(GlFormGroup).at(0);
  const findRoleGroup = () => wrapper.findAllComponents(GlFormGroup).at(1);
  const findPicker = () => wrapper.findComponent(GlTokenSelector);
  const findNoResults = () => findPicker();
  const findRoleSelect = () => wrapper.findComponent(RoleSelector);
  const findSummary = () => wrapper.findComponent(RoleAccessSummary);
  const findAnnouncement = () => wrapper.findByTestId('member-search-announcement');
  const findPrimaryAttributes = () => findModal().props('actionPrimary').attributes;

  const createComponent = ({
    visible = true,
    repositoryName = 'payment-core',
    excludedMemberIds = [],
    returnFocus = null,
  } = {}) => {
    mockApollo = createMockApollo([
      [getOrganizationMembersQuery, searchHandler],
      [bulkGrantRepositoryRolesMutation, grantHandler],
      [getRepositoryRoleAssignmentsQuery, assignmentsHandler],
    ]);

    wrapper = shallowMountExtended(AddMembersModal, {
      apolloProvider: mockApollo,
      provide: { organizationGid: ORGANIZATION_GID },
      propsData: {
        visible,
        repositoryId: REPOSITORY_ID,
        repositoryName,
        excludedMemberIds,
        returnFocus,
      },
      stubs: {
        GlModal: stubComponent(GlModal, {
          template: RENDER_ALL_SLOTS_TEMPLATE,
          methods: { hide: hideModal },
        }),
        GlSprintf,
        GlTokenSelector: stubComponent(GlTokenSelector, {
          template: `<div>
            <input v-bind="textInputAttrs" aria-expanded="false" @keydown.stop />
            <div v-for="token in selectedTokens" :key="token.id">
              <slot name="token-content" :token="token"></slot>
            </div>
            <div v-for="item in dropdownItems" :key="item.id">
              <slot name="dropdown-item-content" :dropdown-item="item"></slot>
            </div>
            <slot name="no-results-content"></slot>
          </div>`,
        }),
      },
      mocks: { $toast: mockToast },
    });
  };

  const typeWithoutWaiting = async (term) => {
    findPicker().vm.$emit('text-input', term);
    await nextTick();
  };

  const type = async (term) => {
    await typeWithoutWaiting(term);
    jest.advanceTimersByTime(DEFAULT_DEBOUNCE_AND_THROTTLE_MS);
  };

  const search = async (term) => {
    await type(term);
    await waitForPromises();
  };

  const select = async (users) => {
    findPicker().vm.$emit(
      'input',
      users.map((user) => token(user)),
    );
    await nextTick();
  };

  // Stands in for the Direct members card, which keeps the assignments query active.
  const watchAssignments = async () => {
    mockApollo.defaultClient
      .watchQuery({ query: getRepositoryRoleAssignmentsQuery, variables: assignmentsVariables })
      .subscribe(() => {});
    await waitForPromises();
  };

  const submit = async () => {
    const event = { preventDefault: jest.fn() };
    findModal().vm.$emit('primary', event);
    await waitForPromises();

    return event;
  };

  beforeEach(() => {
    searchHandler = jest.fn().mockResolvedValue(mockOrganizationMembersResponse());
    grantHandler = jest.fn().mockResolvedValue(mockBulkGrantRolesResponse());
    assignmentsHandler = jest.fn().mockResolvedValue(assignmentsResponse);
    mockToast = { show: jest.fn() };
  });

  describe('the dialog', () => {
    beforeEach(() => {
      createComponent();
    });

    it('is titled Add members, with Add and Cancel actions', () => {
      expect(findModal().props()).toMatchObject({
        visible: true,
        title: 'Add members',
        actionCancel: { text: 'Cancel' },
      });
      expect(findModal().props('actionPrimary')).toMatchObject({
        text: 'Add',
        attributes: { variant: 'confirm' },
      });
    });

    it('stays open on an overlay click', () => {
      expect(findModal().attributes()).toHaveProperty('no-close-on-backdrop');
    });

    it('returns focus to the control it is given once it closes', () => {
      const trigger = document.createElement('button');
      createComponent({ returnFocus: trigger });

      expect(findModal().vm.$attrs['return-focus']).toBe(trigger);
    });

    it('names the repository in its intro', () => {
      expect(findIntro().text()).toBe("You're adding members to the payment-core repository.");
    });

    it('bolds the repository name in its intro', () => {
      expect(findIntro().find('strong').text()).toBe('payment-core');
    });

    it('does not escape the repository name, which renders as text', () => {
      createComponent({ repositoryName: 'a&b' });

      expect(findIntro().text()).toBe("You're adding members to the a&b repository.");
    });

    it('disables Add until a member is selected', async () => {
      expect(findPrimaryAttributes()).toMatchObject({ disabled: true, loading: false });

      await select([alix]);

      expect(findPrimaryAttributes()).toMatchObject({ disabled: false, loading: false });
    });

    it('relays visibility changes to its owner', () => {
      findModal().vm.$emit('change', false);

      expect(wrapper.emitted('change')).toEqual([[false]]);
    });
  });

  describe('the member picker', () => {
    it('closes the modal on Esc in the search input', async () => {
      createComponent();

      await wrapper.findByTestId('member-search').trigger('keydown.esc');

      expect(hideModal).toHaveBeenCalled();
    });

    it('leaves the modal open on Esc while the dropdown is open', async () => {
      createComponent();
      const input = wrapper.findByTestId('member-search');
      input.element.setAttribute('aria-expanded', 'true');

      await input.trigger('keydown.esc');

      expect(hideModal).not.toHaveBeenCalled();
    });

    it('is labeled Organization members with the helper text, and labels the search input', () => {
      createComponent();

      expect(findMembersGroup().attributes()).toMatchObject({
        label: 'Organization members',
        description: 'Select from GitLab usernames.',
      });
      expect(findMembersGroup().attributes('label-for')).toBe(
        findPicker().props('textInputAttrs').id,
      );
    });

    it('does not search below three characters, and offers nothing', async () => {
      createComponent();

      await search('al');

      expect(searchHandler).not.toHaveBeenCalled();
      expect(findPicker().props('dropdownItems')).toEqual([]);
      expect(findPicker().props('hideDropdownWithNoItems')).toBe(true);
    });

    it('drops the previous matches once the term is shorter than three characters', async () => {
      createComponent();

      await search('ali');
      await search('al');

      expect(findPicker().props('dropdownItems')).toEqual([]);
    });

    it('does not offer the previous matches while the next search is pending', async () => {
      createComponent();

      await search('ali');
      await typeWithoutWaiting('');
      await typeWithoutWaiting('mor');

      expect(findPicker().props('dropdownItems')).toEqual([]);
    });

    it('searches for the trimmed term, and ignores spaces when counting characters', async () => {
      createComponent();

      await search('  al  ');

      expect(searchHandler).not.toHaveBeenCalled();

      await search(' ali ');

      expect(searchHandler).toHaveBeenCalledTimes(1);
      expect(searchHandler).toHaveBeenCalledWith(expect.objectContaining({ search: 'ali' }));
    });

    it('waits for typing to pause before it searches', async () => {
      createComponent();

      await typeWithoutWaiting('ali');
      jest.advanceTimersByTime(DEFAULT_DEBOUNCE_AND_THROTTLE_MS - 1);
      await typeWithoutWaiting('alix');
      jest.advanceTimersByTime(DEFAULT_DEBOUNCE_AND_THROTTLE_MS - 1);
      await waitForPromises();

      expect(searchHandler).not.toHaveBeenCalled();

      jest.advanceTimersByTime(1);
      await waitForPromises();

      expect(searchHandler).toHaveBeenCalledTimes(1);
      expect(searchHandler).toHaveBeenCalledWith(expect.objectContaining({ search: 'alix' }));
    });

    it('searches the organization for the term once it is long enough', async () => {
      createComponent();

      await search('ali');

      expect(searchHandler).toHaveBeenCalledTimes(1);
      expect(searchHandler).toHaveBeenCalledWith({
        organizationId: ORGANIZATION_GID,
        search: 'ali',
        first: 20,
      });
      expect(findPicker().props('hideDropdownWithNoItems')).toBe(false);
      expect(findPicker().props('loading')).toBe(false);
    });

    it('shows the picker as loading while the search is in flight', async () => {
      createComponent();

      await type('ali');
      await nextTick();

      expect(findPicker().props('loading')).toBe(true);
    });

    it('offers the matches, excluding members the Direct card has loaded', async () => {
      createComponent({ excludedMemberIds: [morgan.id] });

      await search('ali');

      expect(findPicker().props('dropdownItems')).toEqual([token(alix), token(ali)]);
    });

    it('shows each match with its avatar, name, and username', async () => {
      createComponent({ excludedMemberIds: [morgan.id, ali.id] });

      await search('ali');

      expect(wrapper.findComponent(GlAvatarLabeled).props()).toMatchObject({
        src: alix.avatarUrl,
        entityName: alix.name,
        label: alix.name,
        subLabel: `@${alix.username}`,
      });
    });

    it('shows an avatar on a selected member token only when the member has one', async () => {
      createComponent();

      await select([alix, { ...ali, avatarUrl: null }]);

      const avatars = wrapper.findAllComponents(GlAvatar);
      expect(avatars).toHaveLength(1);
      expect(avatars.at(0).props('src')).toBe(alix.avatarUrl);
    });

    it('offers and counts only the members not already selected', async () => {
      createComponent();

      await select([alix]);
      await search('ali');

      expect(findPicker().props('dropdownItems')).toEqual([token(morgan), token(ali)]);
      expect(findAnnouncement().text()).toBe('2 members found.');
    });

    it('announces the result count through a live region', async () => {
      createComponent({ excludedMemberIds: [morgan.id] });

      expect(findAnnouncement().attributes()).toMatchObject({
        'aria-live': 'polite',
        'aria-atomic': 'true',
      });

      await search('ali');

      expect(findAnnouncement().text()).toBe('2 members found.');

      searchHandler.mockResolvedValue(
        mockOrganizationMembersResponse([mockOrganizationMembers[2]]),
      );
      await search('ali ahmed');

      expect(findAnnouncement().text()).toBe('1 member found.');
    });

    it('tells the user when nothing matches', async () => {
      searchHandler.mockResolvedValue(mockOrganizationMembersResponse([]));
      createComponent();

      await search('zzz');

      expect(findPicker().props('dropdownItems')).toEqual([]);
      expect(findNoResults().text()).toBe('No matches found.');
      expect(findAnnouncement().text()).toBe('0 members found.');
    });

    it('reports a failed search in place of the results', async () => {
      searchHandler.mockRejectedValue(new Error('offline'));
      createComponent();

      await search('ali');

      expect(findNoResults().text()).toBe('Members could not be loaded.');
    });

    it('drops the previous matches when a later search fails', async () => {
      createComponent();
      await search('ali');

      searchHandler.mockRejectedValue(new Error('offline'));
      await search('alix');

      expect(findPicker().props('dropdownItems')).toEqual([]);
      expect(findNoResults().text()).toBe('Members could not be loaded.');
      expect(findAnnouncement().text()).toBe('Members could not be loaded.');
    });

    it('shows the matches again once a search succeeds after a failure', async () => {
      searchHandler.mockRejectedValueOnce(new Error('offline'));
      createComponent();
      await search('ali');

      await search('alix');

      expect(findPicker().props('dropdownItems')).toEqual([token(morgan), token(alix), token(ali)]);
      expect(findNoResults().text()).toBe('No matches found.');
    });
  });

  describe('the role', () => {
    beforeEach(() => {
      createComponent();
    });

    it('is labeled Role, defaults to Artifact Viewer, and summarizes that role', () => {
      expect(findRoleGroup().attributes('label')).toBe('Role');
      expect(findRoleGroup().attributes('label-for')).toBe(findRoleSelect().props('toggleId'));
      expect(findRoleSelect().props('value')).toMatchObject({ value: 'ARTIFACT_VIEWER' });
      expect(findSummary().props('role')).toBe('ARTIFACT_VIEWER');
    });

    it('offers the four roles, Admin first, each with its description', () => {
      expect(findRoleSelect().props('roles').formatted).toEqual([
        {
          value: 'ARTIFACT_ADMIN',
          text: 'Artifact Admin',
          description: 'Manage repository configuration and access.',
        },
        {
          value: 'ARTIFACT_MANAGER',
          text: 'Artifact Manager',
          description: 'Manage artifacts and repository configuration.',
        },
        {
          value: 'ARTIFACT_CONTRIBUTOR',
          text: 'Artifact Contributor',
          description: 'Publish artifacts (for example, CI jobs).',
        },
        {
          value: 'ARTIFACT_VIEWER',
          text: 'Artifact Viewer',
          description: 'Pull and browse artifacts.',
        },
      ]);
    });

    it('summarizes the role as the selection changes', async () => {
      findRoleSelect().vm.$emit('input', { value: 'ARTIFACT_ADMIN' });
      await nextTick();

      expect(findRoleSelect().props('value')).toMatchObject({ value: 'ARTIFACT_ADMIN' });
      expect(findSummary().props('role')).toBe('ARTIFACT_ADMIN');
    });
  });

  describe('adding the selected members', () => {
    beforeEach(async () => {
      createComponent();
      await watchAssignments();
      await select([alix, ali]);
      findRoleSelect().vm.$emit('input', { value: 'ARTIFACT_MANAGER' });
      await nextTick();
    });

    it('keeps the dialog in charge of closing', async () => {
      const event = await submit();

      expect(event.preventDefault).toHaveBeenCalled();
    });

    it('grants the chosen role to every selected member in one request', async () => {
      await submit();

      expect(grantHandler).toHaveBeenCalledTimes(1);
      expect(grantHandler).toHaveBeenCalledWith({
        input: {
          assignments: [
            { assigneeId: alix.id, resourceId: REPOSITORY_ID, role: 'ARTIFACT_MANAGER' },
            { assigneeId: ali.id, resourceId: REPOSITORY_ID, role: 'ARTIFACT_MANAGER' },
          ],
        },
      });
    });

    it('shows Add as loading while the grant is in flight', async () => {
      grantHandler.mockReturnValue(new Promise(() => {}));

      findModal().vm.$emit('primary', { preventDefault: jest.fn() });
      await nextTick();

      expect(findPrimaryAttributes()).toMatchObject({ loading: true });
    });

    it('stays open while the grant is in flight', async () => {
      grantHandler.mockReturnValue(new Promise(() => {}));
      findModal().vm.$emit('primary', { preventDefault: jest.fn() });
      await nextTick();
      const hideEvent = { preventDefault: jest.fn() };

      findModal().vm.$emit('hide', hideEvent);

      expect(hideEvent.preventDefault).toHaveBeenCalled();
    });

    it('can close when no grant is in flight', () => {
      const hideEvent = { preventDefault: jest.fn() };

      findModal().vm.$emit('hide', hideEvent);

      expect(hideEvent.preventDefault).not.toHaveBeenCalled();
    });

    describe('on success', () => {
      beforeEach(async () => {
        await submit();
      });

      it('toasts the count and role, with the propagation notice', () => {
        expect(mockToast.show).toHaveBeenCalledWith(
          '2 members added as Artifact Manager. Changes might not take effect right away.',
        );
      });

      it('closes', () => {
        expect(wrapper.emitted('change')).toEqual([[false]]);
        expect(findErrors().exists()).toBe(false);
      });

      it('refetches the assignments so the Direct card lists the new members', () => {
        expect(assignmentsHandler).toHaveBeenCalledTimes(2);
        expect(assignmentsHandler).toHaveBeenLastCalledWith(assignmentsVariables);
      });

      it('can close once the grant settles', () => {
        const hideEvent = { preventDefault: jest.fn() };

        findModal().vm.$emit('hide', hideEvent);

        expect(hideEvent.preventDefault).not.toHaveBeenCalled();
      });
    });

    it('keeps the cached assignments while the refetch is in flight', async () => {
      assignmentsHandler.mockReturnValue(new Promise(() => {}));

      await submit();

      expect(
        mockApollo.defaultClient.readQuery({
          query: getRepositoryRoleAssignmentsQuery,
          variables: assignmentsVariables,
        }),
      ).toEqual(assignmentsResponse.data);
    });

    it('uses the singular for one member', async () => {
      await select([alix]);
      await submit();

      expect(mockToast.show).toHaveBeenCalledWith(
        '1 member added as Artifact Manager. Changes might not take effect right away.',
      );
    });

    describe('on payload errors', () => {
      beforeEach(async () => {
        grantHandler.mockResolvedValue(
          mockBulkGrantRolesResponse([
            `Assignment 1 on resource ${REPOSITORY_ID}: User is not a member of the organization.\nAssignment 2 on resource ${REPOSITORY_ID}: User could not be found.`,
          ]),
        );

        await submit();
      });

      it('lists each error line as an item in a danger alert', () => {
        expect(findErrors().props()).toMatchObject({ variant: 'danger', dismissible: false });
        expect(findErrorLines()).toEqual([
          `Assignment 1 on resource ${REPOSITORY_ID}: User is not a member of the organization.`,
          `Assignment 2 on resource ${REPOSITORY_ID}: User could not be found.`,
        ]);
      });

      it('stays open with the selection, and shows no toast', () => {
        expect(wrapper.emitted('change')).toBeUndefined();
        expect(mockToast.show).not.toHaveBeenCalled();
        expect(findPicker().props('selectedTokens')).toEqual([token(alix), token(ali)]);
        expect(findPrimaryAttributes()).toMatchObject({ disabled: false, loading: false });
      });

      it('does not refetch the assignments', () => {
        expect(assignmentsHandler).toHaveBeenCalledTimes(1);
      });

      it('clears the alert on the next attempt', async () => {
        grantHandler.mockResolvedValue(mockBulkGrantRolesResponse());

        await submit();

        expect(findErrors().exists()).toBe(false);
        expect(wrapper.emitted('change')).toEqual([[false]]);
      });
    });

    describe('when the request fails', () => {
      const error = new Error('offline');

      beforeEach(async () => {
        grantHandler.mockRejectedValue(error);

        await submit();
      });

      it('shows a generic error and stays open', () => {
        expect(findErrorLines()).toEqual(['Something went wrong. Please try again.']);
        expect(wrapper.emitted('change')).toBeUndefined();
        expect(mockToast.show).not.toHaveBeenCalled();
      });

      it('reports the failure', () => {
        expect(Sentry.captureException).toHaveBeenCalledWith(error);
      });

      it('can close once the grant settles', () => {
        const hideEvent = { preventDefault: jest.fn() };

        findModal().vm.$emit('hide', hideEvent);

        expect(hideEvent.preventDefault).not.toHaveBeenCalled();
      });
    });
  });

  describe('once hidden', () => {
    beforeEach(async () => {
      grantHandler.mockResolvedValue(mockBulkGrantRolesResponse(['Not allowed.']));
      createComponent();
      await search('ali');
      await select([alix]);
      findRoleSelect().vm.$emit('input', { value: 'ARTIFACT_ADMIN' });
      await submit();

      findModal().vm.$emit('hidden');
      await nextTick();
    });

    it('forgets the selection, role, search, and errors', () => {
      expect(findPicker().props('selectedTokens')).toEqual([]);
      expect(findRoleSelect().props('value')).toMatchObject({ value: 'ARTIFACT_VIEWER' });
      expect(findErrors().exists()).toBe(false);
      expect(findAnnouncement().text()).toBe('');
      expect(findPicker().props('dropdownItems')).toEqual([]);
    });
  });

  it('forgets a failed search once hidden', async () => {
    searchHandler.mockRejectedValue(new Error('offline'));
    createComponent();
    await search('ali');

    findModal().vm.$emit('hidden');
    await nextTick();

    expect(findNoResults().text()).toBe('No matches found.');
  });
});
