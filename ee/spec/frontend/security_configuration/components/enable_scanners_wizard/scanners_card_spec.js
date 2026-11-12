import { GlCard } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ScannersCard from 'ee/security_configuration/components/enable_scanners_wizard/scanners_card.vue';
import ScanProfileDetailsModal from 'ee/security_configuration/components/scan_profiles/scan_profile_details_modal.vue';

describe('EnableScannersCard', () => {
  let wrapper;

  const selectedProfiles = [
    { id: 'gid://gitlab/Security::ScanProfile/1', name: 'SAST Profile', scanType: 'SAST' },
    {
      id: 'gid://gitlab/Security::ScanProfile/2',
      name: 'Secret Detection Profile',
      scanType: 'SECRET_DETECTION',
    },
  ];

  const createComponent = ({ props = {} } = {}) => {
    wrapper = shallowMountExtended(ScannersCard, {
      propsData: props,
      provide: { wizard: { selectedProfiles, routes: { profiles: 'wizard_step_profiles' } } },
      stubs: {
        GlCard,
        GlTableLite: {
          props: ['items', 'fields'],
          template: `
            <div>
              <div v-for="(item, index) in items" :key="index">
                <slot name="cell(name)" :item="item" />
              </div>
            </div>
          `,
        },
      },
    });
  };

  const findEditButton = () => wrapper.findComponentByTestId('edit-scanners-button');
  const findScannersTable = () => wrapper.findComponentByTestId('scanners-table');
  const findPreviewModal = () => wrapper.findComponent(ScanProfileDetailsModal);
  const findProfilePreviewLink = () => wrapper.findComponentByTestId('preview-profile-link');

  it('renders a table row per selected scanner', () => {
    createComponent();

    expect(findScannersTable().props('items')).toBe(selectedProfiles);
  });

  describe('edit button', () => {
    it('hides the button by default', () => {
      createComponent();

      expect(findEditButton().exists()).toBe(false);
    });

    describe('with editable set', () => {
      it("links to the wizard's profiles step", () => {
        createComponent({ props: { editable: true } });

        expect(findEditButton().attributes('title')).toBe('Edit scanners');
        expect(findEditButton().props('to')).toEqual({ name: 'wizard_step_profiles' });
      });

      it('sets the aria-label to Edit scanners', () => {
        createComponent({ props: { editable: true } });

        expect(findEditButton().attributes('aria-label')).toBe('Edit scanners');
      });
    });
  });

  describe('profile preview', () => {
    beforeEach(() => {
      createComponent();
    });

    it('shows the preview modal for the clicked profile', async () => {
      await findProfilePreviewLink().vm.$emit('click');

      expect(findPreviewModal().props()).toMatchObject({
        visible: true,
        profileId: selectedProfiles[0].id,
        scanType: selectedProfiles[0].scanType,
      });
    });

    it('hides the preview modal on the modal close event', async () => {
      await findProfilePreviewLink().vm.$emit('click');
      await findPreviewModal().vm.$emit('close');

      expect(findPreviewModal().props('visible')).toBe(false);
    });
  });
});
