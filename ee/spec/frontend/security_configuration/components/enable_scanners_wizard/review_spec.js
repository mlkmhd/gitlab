import { GlButton, GlCard } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import EnableScannersReview from 'ee/security_configuration/components/enable_scanners_wizard/review.vue';
import ScannersCard from 'ee/security_configuration/components/enable_scanners_wizard/scanners_card.vue';
import ProfileCard from 'ee/security_configuration/components/enable_scanners_wizard/profile_card.vue';
import {
  APPROACH_ADVANCED,
  APPROACH_QUICK,
  ATTACH_MODE_SET,
  ATTACH_MODE_FILL_SCAN_GAPS,
  ATTACH_MODE_REPLACE,
  ATTACH_MODE_OPTIONS,
} from 'ee/security_configuration/components/enable_scanners_wizard/constants';

describe('EnableScannersReview', () => {
  let wrapper;
  let wizard;

  const selectedItems = [
    { id: 'gid://gitlab/Project/1', name: 'Project 1', group: { name: 'Group A', webPath: '/a' } },
    { id: 'gid://gitlab/Project/2', name: 'Project 2', group: { name: 'Group B', webPath: '/b' } },
    { id: 'gid://gitlab/Project/3', name: 'Project 3', group: { name: 'Group B', webPath: '/b' } },
  ];
  const selectedProfiles = [
    { id: 'gid://gitlab/Security::ScanProfile/1', name: 'SAST Profile', scanType: 'SAST' },
    {
      id: 'gid://gitlab/Security::ScanProfile/2',
      name: 'Secret Detection Profile',
      scanType: 'SECRET_DETECTION',
    },
  ];

  const GlTableLiteStub = {
    props: ['items', 'fields'],
    template: `
      <div>
        <div v-for="(item, index) in items" :key="index">
          <slot v-for="field in fields" :name="'cell(' + field.key + ')'" :item="item" />
        </div>
      </div>
    `,
  };

  const createComponent = ({
    approach = APPROACH_QUICK,
    selectedItems: items = [],
    selectedProfiles: scanners = [],
    areAllItemsSelected = false,
    hasModeStep = false,
    attachMode = ATTACH_MODE_FILL_SCAN_GAPS,
    stubs = { GlTableLite: GlTableLiteStub },
    props = {},
  } = {}) => {
    wizard = {
      approach,
      selectedItems: items,
      selectedProfiles: scanners,
      areAllItemsSelected,
      hasModeStep,
      attachMode,
      attachModeOptions: ATTACH_MODE_OPTIONS,
      routes: { items: 'wizard_step_items' },
    };

    wrapper = shallowMountExtended(EnableScannersReview, {
      propsData: props,
      provide: { wizard },
      stubs,
    });
  };

  const findItemsImpactedStat = () => wrapper.findComponentByTestId('items-impacted-stat');
  const findScannersConfiguredStat = () =>
    wrapper.findComponentByTestId('scanners-configured-stat');
  const findItemsTable = () => wrapper.findComponentByTestId('items-table');
  const findScannersCard = () => wrapper.findComponent(ScannersCard);

  describe('summary stats', () => {
    it('shows "All" for items impacted when all items are selected', () => {
      createComponent({ areAllItemsSelected: true });

      expect(findItemsImpactedStat().props('value')).toBe('All');
    });

    it('shows the selected item count for items impacted otherwise', () => {
      createComponent({ selectedItems });

      expect(findItemsImpactedStat().props('value')).toBe('3');
    });

    it('shows the selected scanner count for scanners configured', () => {
      createComponent({ selectedProfiles });

      expect(findScannersConfiguredStat().props('value')).toBe(2);
    });

    it.each`
      attachMode                    | label
      ${ATTACH_MODE_SET}            | ${'All projects'}
      ${ATTACH_MODE_FILL_SCAN_GAPS} | ${"Projects that don't scan yet"}
      ${ATTACH_MODE_REPLACE}        | ${'Replace existing'}
    `('shows "$label" for items impacted when the mode is $attachMode', ({ attachMode, label }) => {
      createComponent({ areAllItemsSelected: true, hasModeStep: true, attachMode });

      expect(findItemsImpactedStat().props('value')).toBe(label);
    });
  });

  describe('items card', () => {
    it('shows the "all uncovered projects are selected" message when all items are selected', () => {
      createComponent({ areAllItemsSelected: true });

      expect(wrapper.text()).toContain('All uncovered projects are selected.');
      expect(findItemsTable().exists()).toBe(false);
    });

    it.each`
      attachMode                    | message
      ${ATTACH_MODE_SET}            | ${'All projects are selected.'}
      ${ATTACH_MODE_FILL_SCAN_GAPS} | ${"Projects that don't scan yet are selected."}
      ${ATTACH_MODE_REPLACE}        | ${'Projects with an existing profile are selected.'}
    `(
      'shows "$message" when all items are selected and the mode is $attachMode',
      ({ attachMode, message }) => {
        createComponent({ areAllItemsSelected: true, hasModeStep: true, attachMode });

        expect(wrapper.text()).toContain(message);
        expect(wrapper.text()).not.toContain('uncovered');
      },
    );

    it('renders a table row per selected item otherwise', () => {
      createComponent({ selectedItems });

      expect(findItemsTable().props('items')).toBe(selectedItems);
    });

    it('renders — in the group column for a selected subgroup', () => {
      const subgroup = { id: 'gid://gitlab/Group/5', name: 'Subgroup', __typename: 'Group' };
      createComponent({
        selectedItems: [subgroup],
        stubs: {
          GlTableLite: {
            props: ['items', 'fields'],
            template: `
              <div>
                <div v-for="(item, index) in items" :key="index">
                  <slot name="cell(group)" :item="item" />
                </div>
              </div>
            `,
          },
        },
      });

      expect(findItemsTable().text()).toContain('—');
    });

    it('sets the edit button aria-label', () => {
      createComponent({
        approach: APPROACH_ADVANCED,
        stubs: { GlCard, GlTableLite: GlTableLiteStub },
      });

      expect(wrapper.findComponent(GlButton).attributes('aria-label')).toBe('Edit project scope');
    });

    it("links the edit button to the wizard's items step", () => {
      createComponent({
        approach: APPROACH_ADVANCED,
        stubs: { GlCard, GlTableLite: GlTableLiteStub },
      });

      expect(wrapper.findComponent(GlButton).props('to')).toEqual({ name: 'wizard_step_items' });
    });
  });

  describe('scanners card', () => {
    it.each`
      approach             | editable
      ${APPROACH_QUICK}    | ${false}
      ${APPROACH_ADVANCED} | ${true}
    `('sets editable to $editable for the $approach approach', ({ approach, editable }) => {
      createComponent({ approach });

      expect(findScannersCard().props('editable')).toBe(editable);
    });

    it('shows the card the wizard passes', () => {
      createComponent({ approach: APPROACH_ADVANCED, props: { profilesCard: ProfileCard } });

      expect(wrapper.findComponent(ProfileCard).props('editable')).toBe(true);
      expect(findScannersCard().exists()).toBe(false);
    });
  });
});
