import { GlCard } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ProfileCard from 'ee/security_configuration/components/enable_scanners_wizard/profile_card.vue';
import TriageProfileDrawer from 'ee/security_configuration/components/scan_profiles/triage_profile_drawer.vue';
import { standardPreset } from './mock_data';

describe('EnableScannersProfileCard', () => {
  let wrapper;

  const createComponent = ({ props = {} } = {}) => {
    wrapper = shallowMountExtended(ProfileCard, {
      propsData: props,
      provide: {
        wizard: {
          selectedProfiles: [standardPreset],
          routes: { profiles: 'wizard_step_profiles' },
        },
      },
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

  const findEditButton = () => wrapper.findComponentByTestId('edit-profile-button');
  const findPreviewLink = () => wrapper.findComponentByTestId('preview-profile-link');
  const findDrawer = () => wrapper.findComponent(TriageProfileDrawer);

  it('renders the chosen preset', () => {
    createComponent();

    expect(findPreviewLink().text()).toBe('Triage and Remediation (Standard)');
  });

  describe('edit button', () => {
    it('hides the button by default', () => {
      createComponent();

      expect(findEditButton().exists()).toBe(false);
    });

    describe('with editable set', () => {
      beforeEach(() => {
        createComponent({ props: { editable: true } });
      });

      it("links to the wizard's profiles step", () => {
        expect(findEditButton().props('to')).toEqual({ name: 'wizard_step_profiles' });
      });

      it('sets the title and aria-label to Change profile', () => {
        expect(findEditButton().attributes()).toMatchObject({
          title: 'Change profile',
          'aria-label': 'Change profile',
        });
      });
    });
  });

  describe('profile preview', () => {
    beforeEach(() => {
      createComponent();
    });

    it('shows the preset drawer on the chosen preset', async () => {
      await findPreviewLink().vm.$emit('click');

      expect(findDrawer().props()).toMatchObject({ open: true, presetId: standardPreset.id });
    });

    it('hides the drawer on close', async () => {
      await findPreviewLink().vm.$emit('click');
      await findDrawer().vm.$emit('close');

      expect(findDrawer().props('open')).toBe(false);
    });
  });
});
