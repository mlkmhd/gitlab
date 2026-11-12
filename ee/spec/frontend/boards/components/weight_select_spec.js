import { GlCollapsibleListbox, GlListboxItem, GlButton } from '@gitlab/ui';
import { mount } from '@vue/test-utils';
import { nextTick } from 'vue';
import WeightSelect from 'ee/boards/components/weight_select.vue';

describe('WeightSelect', () => {
  let wrapper;

  const editButton = () => wrapper.findComponent(GlButton);
  const valueContainer = () => wrapper.find('[data-testid="selected-weight"]');
  const weightDropdown = () => wrapper.findComponent(GlCollapsibleListbox);
  const getWeightItemAtIndex = (index) =>
    weightDropdown().findAllComponents(GlListboxItem).at(index);
  const defaultProps = {
    weights: ['Any', 'None', 0, 1, 2, 3],
    board: {
      weight: null,
    },
    canEdit: true,
  };

  const createComponent = (props = {}) => {
    wrapper = mount(WeightSelect, {
      propsData: {
        ...defaultProps,
        ...props,
      },
    });
  };

  describe('when no weight has been selected', () => {
    beforeEach(() => {
      createComponent();
    });

    it('displays "Any weight"', () => {
      expect(valueContainer().text()).toEqual('Any weight');
    });

    it('hides the weight dropdown', () => {
      expect(weightDropdown().exists()).toBe(false);
    });
  });

  describe('when the weight cannot be edited', () => {
    beforeEach(() => {
      createComponent({ canEdit: false });
    });

    it('does not render the edit button', () => {
      expect(editButton().exists()).toBe(false);
    });
  });

  describe('when the weight can be edited', () => {
    beforeEach(() => {
      createComponent();
    });

    it('shows the edit button', () => {
      expect(editButton().exists()).toBe(true);
    });

    describe('and the edit button is clicked', () => {
      beforeEach(() => {
        editButton().trigger('click');
      });

      describe('and no weight has been selected yet', () => {
        it('hides the value text', () => {
          expect(valueContainer().exists()).toBe(false);
        });

        it('shows the weight dropdown', () => {
          expect(weightDropdown().exists()).toBe(true);
        });
      });

      describe('and a weight has been selected', () => {
        beforeEach(() => {
          editButton().trigger('click');
          getWeightItemAtIndex(0).vm.$emit('click');
        });

        it('shows the value text', () => {
          expect(valueContainer().exists()).toBe(true);
        });

        it('hides the weight dropdown', () => {
          expect(weightDropdown().exists()).toBe(false);
        });
      });
    });
  });

  describe('weight dropdown items', () => {
    beforeEach(() => {
      createComponent();
      editButton().trigger('click');
    });

    it('shows display text for each weight', () => {
      expect(weightDropdown().props('items')).toEqual([
        { value: 'Any', text: 'Any' },
        { value: 'None', text: 'None' },
        { value: 0, text: '0' },
        { value: 1, text: '1' },
        { value: 2, text: '2' },
        { value: 3, text: '3' },
      ]);
    });

    it.each`
      value     | emitted | text
      ${'Any'}  | ${null} | ${'Any weight'}
      ${'None'} | ${-2}   | ${'None'}
      ${2}      | ${2}    | ${'2'}
    `(
      'emits set-weight with $emitted and displays "$text" when $value is selected',
      async ({ value, emitted, text }) => {
        weightDropdown().vm.$emit('select', value);
        await nextTick();

        expect(wrapper.emitted('set-weight')).toEqual([[emitted]]);
        expect(valueContainer().text()).toBe(text);
      },
    );
  });

  describe('when a new weight value is selected', () => {
    it.each`
      weight  | text
      ${null} | ${'Any weight'}
      ${0}    | ${'0'}
      ${1}    | ${'1'}
      ${-1}   | ${'Any weight'}
      ${-2}   | ${'None'}
    `('$weight displays as "$text"', ({ weight, text }) => {
      createComponent({ board: { weight } });
      expect(valueContainer().text()).toEqual(text);
    });

    it.each`
      weight  | cssClass
      ${null} | ${'gl-text-subtle'}
      ${-1}   | ${'gl-text-subtle'}
      ${-2}   | ${'bold'}
      ${0}    | ${'bold'}
      ${3}    | ${'bold'}
    `('$weight has the "$cssClass" class', ({ weight, cssClass }) => {
      createComponent({ board: { weight } });
      expect(valueContainer().classes()).toContain(cssClass);
    });
  });
});
