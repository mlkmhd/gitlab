import { GlDisclosureDropdown, GlDrawer } from '@gitlab/ui';
import { MountingPortal } from 'portal-vue';
import { nextTick } from 'vue';
import { stubComponent } from 'helpers/stub_component';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import DynamicPanel from '~/vue_shared/components/dynamic_panel.vue';
import AccessSidePanel from 'ee/packages_and_registries/artifact_registry/repositories/detail/access/access_side_panel.vue';
import AddMembersModal from 'ee/packages_and_registries/artifact_registry/repositories/detail/access/add_members_modal.vue';
import DirectMembersCard from 'ee/packages_and_registries/artifact_registry/repositories/detail/access/direct_members_card.vue';
import { REPOSITORY_ID, mockRepositoryPermissions } from '../../../mock_data';

describe('ArtifactRegistryAccessSidePanel', () => {
  let wrapper;

  const findPanel = () => wrapper.findByTestId('access-side-panel');
  const findHeading = () => wrapper.findByTestId('access-heading');
  const findCloseButton = () => wrapper.findByTestId('panel-close-button');
  const findDirectCard = () => wrapper.findComponent(DirectMembersCard);
  const findOrganizationAccessNote = () => wrapper.findByTestId('organization-access-note');
  const findOrganizationAccessLink = () => wrapper.findByTestId('organization-access-link');
  const findAddMembersModal = () => wrapper.findComponent(AddMembersModal);

  const permissions = mockRepositoryPermissions();

  const createComponent = ({ open = true, repositoryName = 'payment-core', provide = {} } = {}) => {
    wrapper = mountExtended(AccessSidePanel, {
      propsData: { open, repositoryId: REPOSITORY_ID, repositoryName, permissions },
      provide,
      stubs: {
        AddMembersModal: true,
        DirectMembersCard: stubComponent(DirectMembersCard),
        MountingPortal: stubComponent(MountingPortal, { name: 'MountingPortal' }),
      },
      attachTo: document.body,
    });
  };

  const pressEscape = () =>
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));

  describe('when closed', () => {
    beforeEach(() => {
      createComponent({ open: false });
    });

    it('renders no panel', () => {
      expect(wrapper.findComponent(DynamicPanel).exists()).toBe(false);
    });

    it('ignores Escape', () => {
      pressEscape();

      expect(wrapper.emitted('close')).toBeUndefined();
    });
  });

  describe('when open', () => {
    beforeEach(() => {
      createComponent();
    });

    it('names the repository in its heading', () => {
      expect(findHeading().text()).toBe('Access for payment-core');
    });

    it('renders the heading at the level the panel reserves for its title', () => {
      expect(findHeading().element.tagName).toBe('H2');
    });

    it('is a region named by its heading', () => {
      expect(findPanel().attributes('role')).toBe('region');
      expect(findHeading().attributes('id')).toEqual(expect.any(String));
      expect(findPanel().attributes('aria-labelledby')).toBe(findHeading().attributes('id'));
    });

    it('does not escape the repository name, which renders as text', () => {
      createComponent({ repositoryName: 'a&b' });

      expect(findHeading().text()).toBe('Access for a&b');
    });

    it('emits close when its Close button is pressed', async () => {
      await findCloseButton().trigger('click');

      expect(wrapper.emitted('close')).toEqual([[]]);
    });

    it('emits close on Escape', () => {
      pressEscape();

      expect(wrapper.emitted('close')).toEqual([[]]);
    });

    it('leaves other keys alone', () => {
      document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter' }));

      expect(wrapper.emitted('close')).toBeUndefined();
    });

    it('leaves Escape to an open modal', () => {
      document.body.classList.add('modal-open');

      pressEscape();

      expect(wrapper.emitted('close')).toBeUndefined();

      document.body.classList.remove('modal-open');
    });

    it.each(['input', 'textarea'])('leaves Escape to a focused %s', (tag) => {
      const field = document.createElement(tag);
      document.body.appendChild(field);
      field.focus();

      pressEscape();

      expect(wrapper.emitted('close')).toBeUndefined();

      field.remove();
    });

    it('leaves Escape to a focused rich text editor', () => {
      const editor = document.createElement('div');
      editor.setAttribute('contenteditable', 'true');
      document.body.appendChild(editor);
      editor.focus();

      pressEscape();

      expect(wrapper.emitted('close')).toBeUndefined();

      editor.remove();
    });

    it('leaves Escape to an open drawer', async () => {
      mountExtended(GlDrawer, { propsData: { open: true }, attachTo: document.body });
      await nextTick();

      pressEscape();

      expect(wrapper.emitted('close')).toBeUndefined();
    });

    it('closes on Escape while a closed dropdown toggle has focus', () => {
      const dropdown = mountExtended(GlDisclosureDropdown, {
        propsData: { toggleText: 'More actions', items: [{ text: 'Copy', action: jest.fn() }] },
        attachTo: document.body,
      });
      dropdown.find('button').element.focus();

      pressEscape();

      expect(wrapper.emitted('close')).toEqual([[]]);
    });

    it('still closes from its Close button while a drawer is open', async () => {
      mountExtended(GlDrawer, { propsData: { open: true }, attachTo: document.body });
      await nextTick();

      await findCloseButton().trigger('click');

      expect(wrapper.emitted('close')).toEqual([[]]);
    });

    it('hands the Direct card the repository and its verdicts', () => {
      expect(findDirectCard().props('repositoryId')).toBe(REPOSITORY_ID);
      expect(findDirectCard().props('permissions')).toBe(permissions);
    });

    describe('the Organization access note', () => {
      const organizationAccessPath = '/o/default/-/access/artifact-registry';

      it('tells every viewer that Organization access roles also apply', () => {
        expect(findOrganizationAccessNote().text()).toBe(
          'Members with a role in Organization access also have access to this repository.',
        );
      });

      it('renders no link when the viewer cannot open Organization access', () => {
        expect(findOrganizationAccessLink().exists()).toBe(false);
      });

      it('links to Organization access when the viewer can open it', () => {
        createComponent({ provide: { organizationAccessPath } });

        expect(findOrganizationAccessLink().text()).toBe('Manage Organization access');
        expect(findOrganizationAccessLink().attributes('href')).toBe(organizationAccessPath);
      });
    });

    describe('the Add members modal', () => {
      const loadedMemberIds = ['gid://gitlab/User/1', 'gid://gitlab/User/2'];
      const trigger = document.createElement('button');

      it('stays closed until the Direct card asks for it', () => {
        expect(findAddMembersModal().props()).toMatchObject({
          visible: false,
          repositoryId: REPOSITORY_ID,
          repositoryName: 'payment-core',
          excludedMemberIds: [],
          returnFocus: null,
        });
      });

      describe('when the Direct card asks to add members', () => {
        beforeEach(async () => {
          findDirectCard().vm.$emit('add-members', { trigger, memberIds: loadedMemberIds });
          await nextTick();
        });

        it('opens, excluding the members the card has loaded', () => {
          expect(findAddMembersModal().props()).toMatchObject({
            visible: true,
            excludedMemberIds: loadedMemberIds,
          });
        });

        it('closes when the modal reports it was closed', async () => {
          findAddMembersModal().vm.$emit('change', false);
          await nextTick();

          expect(findAddMembersModal().props('visible')).toBe(false);
        });

        it('returns focus to the Add members button once the modal closes', () => {
          expect(findAddMembersModal().props('returnFocus')).toBe(trigger);
        });
      });
    });
  });

  describe('when it opens', () => {
    beforeEach(async () => {
      createComponent({ open: false });

      await wrapper.setProps({ open: true });
      await nextTick();
    });

    it('moves focus to the panel', () => {
      expect(document.activeElement).toBe(findPanel().element);
    });
  });
});
