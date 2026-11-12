import { GlLoadingIcon } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import WorkItemEditableCell from '~/work_items/table/components/editable_cell/work_item_editable_cell.vue';
import updateWorkItemMutation from '~/work_items/graphql/update_work_item.mutation.graphql';
import { EDIT_TRIGGER_CELL } from '~/work_items/table/constants';
import { updateWorkItemMutationResponseFactory } from 'ee_else_ce_jest/work_items/mock_data';
import { buildWorkItemNode } from '../../../board/mock_data';

jest.mock('~/sentry/sentry_browser_wrapper');

Vue.use(VueApollo);

describe('WorkItemEditableCell', () => {
  let wrapper;
  let editorProps;
  let mockToast;

  const item = buildWorkItemNode(1, { title: 'Test work item' });
  const errorMessage = 'Something went wrong while updating the title.';
  const successHandler = jest.fn().mockResolvedValue(updateWorkItemMutationResponseFactory());

  const findEditButton = () => wrapper.findByTestId('cell-edit-button');
  const findDisplay = () => wrapper.findByTestId('display');
  const findEditor = () => wrapper.findByTestId('editor');
  const findLoadingIcon = () => wrapper.findComponent(GlLoadingIcon);

  const createComponent = ({ props = {}, mutationHandler = successHandler } = {}) => {
    mockToast = { show: jest.fn() };
    wrapper = mountExtended(WorkItemEditableCell, {
      apolloProvider: createMockApollo([[updateWorkItemMutation, mutationHandler]]),
      propsData: {
        item,
        editLabel: 'Edit title',
        savingText: 'Saving title',
        errorMessage,
        ...props,
      },
      scopedSlots: {
        display: '<span data-testid="display">Value</span>',
        editor(slotProps) {
          editorProps = slotProps;
          return this.$createElement('span', { attrs: { 'data-testid': 'editor' } });
        },
      },
      mocks: {
        $toast: mockToast,
      },
    });
  };

  const startEditing = async () => {
    findEditButton().trigger('click');
    await nextTick();
  };

  describe('with the default pencil button', () => {
    it('shows the value and the edit button', () => {
      createComponent();

      expect(findDisplay().exists()).toBe(true);
      expect(findEditButton().attributes('aria-label')).toBe('Edit title');
      expect(findEditor().exists()).toBe(false);
    });

    it('hides the edit button when the user cannot edit', () => {
      createComponent({ props: { canEdit: false } });

      expect(findEditButton().exists()).toBe(false);
    });

    it('shows the editor when the edit button is clicked', async () => {
      createComponent();
      await startEditing();

      expect(findDisplay().exists()).toBe(false);
      expect(findEditor().exists()).toBe(true);
    });

    it('emits cell-click instead of editing when the cell is clicked', async () => {
      createComponent();

      await wrapper.trigger('click');

      expect(wrapper.emitted('cell-click')).toHaveLength(1);
      expect(findEditor().exists()).toBe(false);
    });
  });

  describe('when editing starts on cell click', () => {
    it('shows the editor without an edit button', async () => {
      createComponent({ props: { editTrigger: EDIT_TRIGGER_CELL } });

      expect(findEditButton().exists()).toBe(false);

      await wrapper.trigger('click');

      expect(findEditor().exists()).toBe(true);
      expect(wrapper.emitted('cell-click')).toBeUndefined();
    });

    it('does not edit when the user cannot edit', async () => {
      createComponent({ props: { editTrigger: EDIT_TRIGGER_CELL, canEdit: false } });

      await wrapper.trigger('click');

      expect(findEditor().exists()).toBe(false);
    });
  });

  describe('saving', () => {
    it('leaves edit mode without saving when nothing changed', async () => {
      createComponent();
      await startEditing();

      await expect(editorProps.save(null)).resolves.toBe(true);
      await nextTick();

      expect(successHandler).not.toHaveBeenCalled();
      expect(findEditor().exists()).toBe(false);
    });

    it('sends the input and leaves edit mode', async () => {
      createComponent();
      await startEditing();

      const result = editorProps.save({ title: 'New title' });
      await nextTick();

      expect(editorProps.isSaving).toBe(true);
      expect(findLoadingIcon().exists()).toBe(true);
      expect(wrapper.text()).toContain('Saving title');

      await expect(result).resolves.toBe(true);
      await nextTick();

      expect(successHandler).toHaveBeenCalledWith({
        input: { id: item.id, title: 'New title' },
        useWorkItemFeatures: true,
      });
      expect(findEditor().exists()).toBe(false);
    });

    it('leaves edit mode when cancel is called', async () => {
      createComponent();
      await startEditing();

      editorProps.cancel();
      await nextTick();

      expect(findEditor().exists()).toBe(false);
      expect(findDisplay().exists()).toBe(true);
    });

    it.each`
      description                     | mutationHandler
      ${'returns errors'}             | ${jest.fn().mockResolvedValue({ data: { workItemUpdate: { workItem: null, errors: ['Title is invalid'] } } })}
      ${'fails with a network error'} | ${jest.fn().mockRejectedValue(new Error('Network error'))}
    `(
      'shows a toast, reports to Sentry and stays in edit mode when the save $description',
      async ({ mutationHandler }) => {
        createComponent({ mutationHandler });
        await startEditing();

        await expect(editorProps.save({ title: 'New title' })).resolves.toBe(false);
        await waitForPromises();

        expect(mockToast.show).toHaveBeenCalledWith(errorMessage);
        expect(Sentry.captureException).toHaveBeenCalled();
        expect(findEditor().exists()).toBe(true);
      },
    );
  });
});
