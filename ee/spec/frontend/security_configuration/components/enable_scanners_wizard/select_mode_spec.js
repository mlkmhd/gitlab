import { GlBadge, GlFormRadio, GlFormRadioGroup } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import EnableScannersSelectMode from 'ee/security_configuration/components/enable_scanners_wizard/select_mode.vue';
import ScannersCard from 'ee/security_configuration/components/enable_scanners_wizard/scanners_card.vue';
import ProfileCard from 'ee/security_configuration/components/enable_scanners_wizard/profile_card.vue';
import { ATTACH_MODE_OPTIONS } from 'ee/security_configuration/components/enable_scanners_wizard/constants';

describe('EnableScannersSelectMode', () => {
  let wrapper;
  let wizard;

  const createComponent = ({ attachMode = 'FILL_SCAN_GAPS', props = {} } = {}) => {
    wizard = { attachMode, attachModeOptions: ATTACH_MODE_OPTIONS };
    wrapper = shallowMountExtended(EnableScannersSelectMode, {
      propsData: props,
      provide: { wizard },
    });
  };

  const findRadioGroup = () => wrapper.findComponent(GlFormRadioGroup);
  const findRadios = () => wrapper.findAllComponents(GlFormRadio);
  const findScannersCard = () => wrapper.findComponent(ScannersCard);

  beforeEach(() => {
    createComponent();
  });

  it('shows the scanners card with its edit button', () => {
    expect(findScannersCard().props('editable')).toBe(true);
  });

  it('shows the card the wizard passes', () => {
    createComponent({ props: { profilesCard: ProfileCard } });

    expect(wrapper.findComponent(ProfileCard).props('editable')).toBe(true);
    expect(findScannersCard().exists()).toBe(false);
  });

  it("renders the wizard's modes", () => {
    wizard = {
      attachMode: 'B',
      attachModeOptions: [
        { value: 'A', label: 'A' },
        { value: 'B', label: 'B' },
      ],
    };
    wrapper = shallowMountExtended(EnableScannersSelectMode, { provide: { wizard } });

    expect(findRadios().wrappers.map((radio) => radio.attributes('value'))).toEqual(['A', 'B']);
  });

  it('renders the modes in order', () => {
    expect(findRadios().wrappers.map((radio) => radio.attributes('value'))).toEqual([
      'SET',
      'FILL_SCAN_GAPS',
      'REPLACE',
    ]);
    expect(findRadios().at(0).text()).toContain('All projects');
    expect(findRadios().at(1).text()).toContain("Projects that don't scan yet");
    expect(findRadios().at(2).text()).toContain('Replace existing');
  });

  it('shows the Recommended badge on one mode', () => {
    expect(findRadios().at(1).findComponent(GlBadge).text()).toBe('Recommended');
    expect(wrapper.findAllComponents(GlBadge)).toHaveLength(1);
  });

  it('sets the radio group to the current attach mode', () => {
    expect(findRadioGroup().attributes('checked')).toBe('FILL_SCAN_GAPS');
  });

  it.each(['SET', 'FILL_SCAN_GAPS', 'REPLACE'])(
    'sets the attach mode to %s on select',
    (attachMode) => {
      createComponent({ attachMode: null });

      findRadioGroup().vm.$emit('input', attachMode);

      expect(wizard.attachMode).toBe(attachMode);
    },
  );
});
