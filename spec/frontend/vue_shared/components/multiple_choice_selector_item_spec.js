import { GlFormCheckbox } from '@gitlab/ui';
import { mount, shallowMount } from '@vue/test-utils';
import MultipleChoiceSelectorItem from '~/vue_shared/components/multiple_choice_selector_item.vue';

describe('MultipleChoiceSelectorItem', () => {
  let wrapper;

  function createComponent({ propsData = {} } = {}) {
    wrapper = shallowMount(MultipleChoiceSelectorItem, {
      propsData: {
        ...propsData,
      },
    });
  }

  const findCheckbox = () => wrapper.findComponent(GlFormCheckbox);

  it('renders checkbox', () => {
    createComponent();

    expect(findCheckbox().exists()).toBe(true);
  });

  it('renders title', () => {
    createComponent({ propsData: { title: 'Option title' } });

    expect(findCheckbox().text()).toContain('Option title');
  });

  it('renders description', () => {
    createComponent({ propsData: { description: 'Option description' } });

    expect(wrapper.text()).toContain('Option description');
  });

  it('renders disabled message', () => {
    createComponent({ propsData: { disabledMessage: 'Option disabled message', disabled: true } });

    expect(wrapper.text()).toContain('Option disabled message');
  });

  describe('when focused', () => {
    beforeEach(() => {
      wrapper = mount(MultipleChoiceSelectorItem, {
        attachTo: document.body,
        propsData: { title: 'Option title' },
      });
      wrapper.vm.focus();
    });

    it('focuses the checkbox', () => {
      expect(document.activeElement).toBe(wrapper.find('input[type="checkbox"]').element);
    });
  });
});
