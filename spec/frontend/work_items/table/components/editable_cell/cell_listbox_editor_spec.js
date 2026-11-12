import { GlCollapsibleListbox } from '@gitlab/ui';
import { nextTick } from 'vue';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import CellListboxEditor from '~/work_items/table/components/editable_cell/cell_listbox_editor.vue';

describe('CellListboxEditor', () => {
  let wrapper;
  let toggleProps;

  const frontend = { value: 'gid://gitlab/Label/1', text: 'frontend' };
  const backend = { value: 'gid://gitlab/Label/2', text: 'backend' };
  const docs = { value: 'gid://gitlab/Label/3', text: 'docs' };

  const findListbox = () => wrapper.findComponent(GlCollapsibleListbox);

  const createComponent = (props = {}) => {
    wrapper = mountExtended(CellListboxEditor, {
      propsData: {
        items: [frontend, backend],
        selectedOptions: [frontend],
        multiple: true,
        ...props,
      },
      attrs: { 'header-text': 'Select labels' },
      scopedSlots: {
        toggle(slotProps) {
          toggleProps = slotProps;
          return this.$createElement('span', 'Toggle');
        },
      },
    });
  };

  it('opens a searchable listbox with the starting selection', () => {
    createComponent();

    expect(findListbox().props()).toMatchObject({
      selected: [frontend.value],
      multiple: true,
      searchable: true,
      startOpened: true,
      headerText: 'Select labels',
    });
  });

  it('asks for the first options when created', () => {
    createComponent();

    expect(wrapper.emitted('search')).toEqual([['']]);
  });

  it('groups selected options first', () => {
    createComponent();

    expect(findListbox().props('items')).toEqual([
      { text: 'Selected', options: [frontend] },
      { text: 'All', textSrOnly: true, options: [backend] },
    ]);
  });

  it('shows a flat list while searching', async () => {
    createComponent();

    findListbox().vm.$emit('search', 'back');
    await nextTick();

    expect(wrapper.emitted('search')).toContainEqual(['back']);
    expect(findListbox().props('items')).toEqual([frontend, backend]);
  });

  it('keeps selected options that a later search leaves out', async () => {
    createComponent();

    findListbox().vm.$emit('select', [frontend.value, backend.value]);
    await wrapper.setProps({ items: [docs] });

    expect(toggleProps.pickedOptions).toEqual([frontend, backend]);
  });

  it('clears the selection on reset', async () => {
    createComponent();

    findListbox().vm.$emit('reset');
    await nextTick();

    expect(findListbox().props('selected')).toEqual([]);
  });

  it('submits the selection when the listbox closes', () => {
    createComponent();

    findListbox().vm.$emit('select', [backend.value]);
    findListbox().vm.$emit('hidden');

    expect(wrapper.emitted('submit')).toEqual([[[backend.value]]]);
  });

  it('clears a single selection to null on reset', async () => {
    createComponent({ multiple: false });

    findListbox().vm.$emit('reset');
    findListbox().vm.$emit('hidden');
    await nextTick();

    expect(wrapper.emitted('submit')).toEqual([[null]]);
  });

  describe('after the listbox closes', () => {
    // The listbox opens once on mount, so a reopen is its second `shown` event.
    const reopen = async () => {
      await findListbox().vm.close();
      wrapper.find('.gl-new-dropdown-custom-toggle').trigger('click');
      await nextTick();
    };

    it('reopens when the toggle is clicked', async () => {
      createComponent();
      await reopen();

      expect(findListbox().emitted('shown')).toHaveLength(2);
    });

    it('does not reopen while saving, so no change is lost', async () => {
      createComponent({ isSaving: true });
      await reopen();

      expect(findListbox().emitted('shown')).toHaveLength(1);
    });
  });

  describe('when some values cannot be selected', () => {
    beforeEach(() => {
      createComponent({ unselectableValues: [frontend.value, docs.value] });
    });

    it('does not add them to the selection', async () => {
      findListbox().vm.$emit('select', [frontend.value, docs.value]);
      await nextTick();

      expect(findListbox().props('selected')).toEqual([frontend.value]);
    });

    it('still lets them be removed', async () => {
      findListbox().vm.$emit('select', []);
      await nextTick();

      expect(findListbox().props('selected')).toEqual([]);
    });
  });

  it('keeps the latest pick when it switches to single select', async () => {
    createComponent();
    findListbox().vm.$emit('select', [frontend.value, backend.value]);

    await wrapper.setProps({ multiple: false });

    expect(findListbox().props('selected')).toBe(backend.value);
  });

  it('shows the newest copy of a starting option once the items include it', async () => {
    createComponent({ items: [], selectedOptions: [frontend] });

    await wrapper.setProps({ items: [{ ...frontend, text: 'frontend (renamed)' }, backend] });

    expect(toggleProps.pickedOptions).toEqual([{ ...frontend, text: 'frontend (renamed)' }]);
  });
});
