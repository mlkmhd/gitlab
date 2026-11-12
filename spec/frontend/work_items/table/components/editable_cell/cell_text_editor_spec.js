import { GlFormInput } from '@gitlab/ui';
import { nextTick } from 'vue';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import CellTextEditor from '~/work_items/table/components/editable_cell/cell_text_editor.vue';

describe('CellTextEditor', () => {
  let wrapper;

  const findInput = () => wrapper.findComponent(GlFormInput);

  const createComponent = (props = {}, attrs = {}) => {
    wrapper = mountExtended(CellTextEditor, {
      propsData: { value: 'Old title', ...props },
      attrs,
      attachTo: document.body,
    });
  };

  const typeAndPress = async (value, key) => {
    await findInput().setValue(value);
    await findInput().trigger('keydown', { key });
  };

  it('shows the value in a focused input and passes attributes to it', () => {
    createComponent({}, { maxlength: 10, 'aria-label': 'Title' });

    expect(findInput().element.value).toBe('Old title');
    expect(findInput().attributes()).toMatchObject({ maxlength: '10', 'aria-label': 'Title' });
    expect(document.activeElement).toBe(findInput().element);
  });

  it('submits the edited value on Enter', async () => {
    createComponent();

    await typeAndPress('New title', 'Enter');

    expect(wrapper.emitted('submit')).toEqual([['New title']]);
  });

  it('does not submit an invalid value', async () => {
    createComponent({ validator: (value) => value.length > 0 });

    await typeAndPress('', 'Enter');

    expect(wrapper.emitted('submit')).toBeUndefined();
    expect(findInput().props('state')).toBe(false);
  });

  it('does not submit while saving', async () => {
    createComponent({ isSaving: true });

    await findInput().trigger('keydown', { key: 'Enter' });

    expect(wrapper.emitted('submit')).toBeUndefined();
    expect(findInput().attributes('disabled')).toBeDefined();
  });

  it('cancels on Escape without the event reaching parent handlers', async () => {
    createComponent();
    const parentHandler = jest.fn();
    wrapper.element.parentElement.addEventListener('keydown', parentHandler);

    await findInput().trigger('keydown', { key: 'Escape' });

    expect(wrapper.emitted('cancel')).toHaveLength(1);
    expect(parentHandler).not.toHaveBeenCalled();
  });

  it('submits on blur', async () => {
    createComponent();

    await findInput().setValue('New title');
    await findInput().trigger('blur');

    expect(wrapper.emitted('submit')).toEqual([['New title']]);
  });

  describe('when an invalid value is blurred', () => {
    const validator = () => false;

    it('cancels when cancelInvalidOnBlur is set', async () => {
      createComponent({ validator, cancelInvalidOnBlur: true });

      await findInput().trigger('blur');

      expect(wrapper.emitted('cancel')).toHaveLength(1);
    });

    it('stays open otherwise', async () => {
      createComponent({ validator });

      await findInput().trigger('blur');
      await nextTick();

      expect(wrapper.emitted('cancel')).toBeUndefined();
      expect(wrapper.emitted('submit')).toBeUndefined();
    });
  });
});
