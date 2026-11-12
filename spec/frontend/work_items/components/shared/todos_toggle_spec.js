import { GlButton, GlAnimatedTodoIcon } from '@gitlab/ui';

import { shallowMountExtended } from 'helpers/vue_test_utils_helper';

import TodosToggle from '~/work_items/components/shared/todos_toggle.vue';
import { TODO_DONE_ICON, TODO_ADD_ICON } from '~/work_items/constants';

describe('TodosToggle', () => {
  let wrapper;

  const mockTodo = { id: 'gid://gitlab/Todo/1', state: 'pending' };

  const findButton = () => wrapper.findComponent(GlButton);
  const findAnimatedTodoIcon = () => wrapper.findComponent(GlAnimatedTodoIcon);

  const createComponent = ({ currentUserTodos = [], ...props } = {}) => {
    wrapper = shallowMountExtended(TodosToggle, {
      propsData: { currentUserTodos, ...props },
      stubs: { GlAnimatedTodoIcon },
    });
  };

  describe('when there are no pending to-do items', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the add button', () => {
      expect(findAnimatedTodoIcon().attributes('name')).toBe(TODO_ADD_ICON);
      expect(findAnimatedTodoIcon().props('isOn')).toBe(false);
      expect(findButton().props('selected')).toBe(false);
      expect(findButton().props('category')).toBe('tertiary');
      expect(findButton().props('size')).toBe('small');
      expect(findButton().attributes('aria-pressed')).toBeUndefined();
      expect(findButton().attributes('title')).toBe('Add to To-Do List');
    });

    it('emits toggle with no payload on click', () => {
      findButton().vm.$emit('click');

      expect(wrapper.emitted('toggle')).toEqual([[]]);
    });
  });

  describe('when there is a pending to-do item', () => {
    beforeEach(() => {
      createComponent({ currentUserTodos: [mockTodo] });
    });

    it('renders the mark-done button', () => {
      expect(findAnimatedTodoIcon().attributes('name')).toBe(TODO_DONE_ICON);
      expect(findAnimatedTodoIcon().props('isOn')).toBe(true);
      expect(findButton().props('selected')).toBe(true);
      expect(findButton().attributes('aria-pressed')).toBeUndefined();
      expect(findButton().attributes('title')).toBe('Mark as done');
    });
  });

  // The label used to be seeded once in `data()`, so it never caught up with the prop.
  describe('when the to-do items arrive after the first render', () => {
    beforeEach(async () => {
      createComponent();
      await wrapper.setProps({ currentUserTodos: [mockTodo] });
    });

    it('updates the label and icon', () => {
      expect(findButton().attributes('title')).toBe('Mark as done');
      expect(findAnimatedTodoIcon().attributes('name')).toBe(TODO_DONE_ICON);
    });
  });

  describe('when an update is in flight', () => {
    beforeEach(() => {
      createComponent({ isUpdating: true });
    });

    it('keeps the button enabled so focus stays on it', () => {
      expect(findButton().props('disabled')).toBe(false);
    });

    it('does not emit toggle on click', () => {
      findButton().vm.$emit('click');

      expect(wrapper.emitted('toggle')).toBeUndefined();
    });
  });

  describe('when todosButtonType is secondary', () => {
    beforeEach(() => {
      createComponent({ todosButtonType: 'secondary' });
    });

    it('renders a secondary button', () => {
      expect(findButton().props('category')).toBe('secondary');
    });
  });

  it('renders a medium button when requested', () => {
    createComponent({ size: 'medium' });

    expect(findButton().props('size')).toBe('medium');
  });
});
