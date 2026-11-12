import { GlFormInput } from '@gitlab/ui';
import Vue, { nextTick } from 'vue';
import VueApollo from 'vue-apollo';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import WorkItemWeightCell from '~/work_items/table/components/work_item_weight_cell.vue';
import updateWorkItemMutation from '~/work_items/graphql/update_work_item.mutation.graphql';
import { buildWorkItemNode, buildWeightWidget } from '../../board/mock_data';

Vue.use(VueApollo);

describe('WorkItemWeightCell', () => {
  let wrapper;
  const mockToast = { show: jest.fn() };

  const item = buildWorkItemNode(1, {
    userPermissions: { updateWorkItem: true },
    widgets: [buildWeightWidget(5)],
  });

  const itemWithoutWeight = buildWorkItemNode(2, {
    userPermissions: { updateWorkItem: true },
    widgets: [buildWeightWidget(null)],
  });

  const weightCellMutationResponse = {
    data: {
      workItemUpdate: {
        __typename: 'WorkItemUpdatePayload',
        errors: [],
        workItem: {
          ...item,
          archived: false,
          imported: false,
          description: null,
          movedToWorkItemUrl: null,
          duplicatedToWorkItemUrl: null,
          promotedToEpicUrl: null,
          showPlanUpgradePromotion: false,
          createNoteEmail: null,
          project: null,
          commentTemplatesPaths: [],
          namespace: {
            ...item.namespace,
            name: 'Group Name',
            fullName: 'Full Group Name',
            webUrl: 'http://gdk.test/group',
          },
          widgets: item.widgets.map((w) =>
            w.type === 'WEIGHT'
              ? { ...w, weight: 10, rolledUpWeight: null, rolledUpCompletedWeight: null }
              : w,
          ),
        },
      },
    },
  };

  const defaultMutationHandler = jest.fn().mockResolvedValue(weightCellMutationResponse);

  const findCell = () => wrapper.findByTestId('cell-weight');
  const findEditButton = () => wrapper.findByTestId('cell-edit-button');
  const startEditing = () => findCell().trigger('click');
  const findWeightInput = () => wrapper.findComponent(GlFormInput);
  const findWeightValue = () => wrapper.findByTestId('weight-value');

  const createComponent = ({ props = {}, mutationHandler = defaultMutationHandler } = {}) => {
    const apolloProvider = createMockApollo([[updateWorkItemMutation, mutationHandler]]);

    wrapper = mountExtended(WorkItemWeightCell, {
      apolloProvider,
      propsData: {
        item,
        ...props,
      },
      mocks: {
        $toast: mockToast,
      },
    });
  };

  describe('display mode', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the weight value', () => {
      expect(findWeightValue().text()).toBe('5');
    });

    it('does not show an edit button', () => {
      expect(findEditButton().exists()).toBe(false);
    });

    it('does not show the edit input', () => {
      expect(findWeightInput().exists()).toBe(false);
    });

    it('clicking the cell enters edit mode', async () => {
      await startEditing();

      expect(findWeightInput().exists()).toBe(true);
      expect(findWeightValue().exists()).toBe(false);
    });
  });

  describe('when work item has no weight', () => {
    beforeEach(() => {
      createComponent({ props: { item: itemWithoutWeight } });
    });

    it('renders empty string', () => {
      expect(findWeightValue().text()).toBe('');
    });

    it('can enter edit mode', async () => {
      await startEditing();

      expect(findWeightInput().exists()).toBe(true);
    });
  });

  describe('when work item type does not support weight', () => {
    it('does not enter edit mode when weight feature is null', async () => {
      const incidentItem = buildWorkItemNode(4, {
        userPermissions: { updateWorkItem: true },
        features: { weight: null },
      });

      createComponent({ props: { item: incidentItem } });
      await startEditing();

      expect(findWeightInput().exists()).toBe(false);
    });
  });

  describe('when entering edit mode', () => {
    beforeEach(async () => {
      createComponent();
      await startEditing();
      await nextTick();
    });

    it('hides the weight value', () => {
      expect(findWeightValue().exists()).toBe(false);
    });

    it('shows the input field', () => {
      expect(findWeightInput().exists()).toBe(true);
    });

    it('shows input with current weight value', () => {
      expect(findWeightInput().element.value).toBe('5');
    });
  });

  describe('when saving weight', () => {
    beforeEach(() => {
      createComponent();
    });

    it('calls mutation with correct variables when updating weight', async () => {
      await startEditing();
      await findWeightInput().setValue('10');
      await findWeightInput().trigger('blur');
      await waitForPromises();

      expect(defaultMutationHandler).toHaveBeenCalledWith({
        input: {
          id: item.id,
          weightWidget: {
            weight: 10,
          },
        },
        useWorkItemFeatures: true,
      });
    });

    it('calls mutation to clear weight when input is empty', async () => {
      await startEditing();
      await findWeightInput().setValue('');
      await findWeightInput().trigger('blur');
      await waitForPromises();

      expect(defaultMutationHandler).toHaveBeenCalledWith({
        input: {
          id: item.id,
          weightWidget: {
            weight: null,
          },
        },
        useWorkItemFeatures: true,
      });
    });

    it('does not call mutation when weight unchanged', async () => {
      await startEditing();
      await findWeightInput().trigger('blur');
      await waitForPromises();

      expect(defaultMutationHandler).not.toHaveBeenCalled();
    });
  });

  describe('when mutation returns errors', () => {
    beforeEach(() => {
      const errorMutationHandler = jest.fn().mockResolvedValue({
        data: {
          workItemUpdate: {
            errors: ['Something went wrong'],
            workItem: null,
          },
        },
      });
      createComponent({ mutationHandler: errorMutationHandler });
    });

    it('shows toast when mutation returns errors', async () => {
      await startEditing();
      await findWeightInput().setValue('10');
      await findWeightInput().trigger('blur');
      await waitForPromises();

      expect(mockToast.show).toHaveBeenCalledWith(
        'Something went wrong while updating the weight.',
      );
    });
  });

  describe('validation', () => {
    beforeEach(async () => {
      createComponent();
      await startEditing();
      await nextTick();
    });

    it('accepts valid positive integers', async () => {
      await findWeightInput().setValue('10');
      expect(findWeightInput().attributes('aria-invalid')).toBeUndefined();
    });

    it('accepts zero', async () => {
      await findWeightInput().setValue('0');
      expect(findWeightInput().attributes('aria-invalid')).toBeUndefined();
    });

    it('accepts empty value', async () => {
      await findWeightInput().setValue('');
      expect(findWeightInput().attributes('aria-invalid')).toBeUndefined();
    });

    it('rejects negative numbers', async () => {
      await findWeightInput().setValue('-5');
      expect(findWeightInput().attributes('aria-invalid')).toBe('true');
    });

    it('rejects decimal numbers', async () => {
      await findWeightInput().setValue('1.5');
      expect(findWeightInput().attributes('aria-invalid')).toBe('true');
    });
  });

  describe('blur with invalid input', () => {
    beforeEach(() => {
      createComponent();
    });

    it('cancels editing when blur occurs with negative number', async () => {
      await startEditing();
      await findWeightInput().setValue('-5');
      await findWeightInput().trigger('blur');
      await nextTick();

      expect(findWeightInput().exists()).toBe(false);
      expect(findWeightValue().exists()).toBe(true);
      expect(findWeightValue().text()).toBe('5');
    });

    it('cancels editing when blur occurs with decimal number', async () => {
      await startEditing();
      await findWeightInput().setValue('1.5');
      await findWeightInput().trigger('blur');
      await nextTick();

      expect(findWeightInput().exists()).toBe(false);
      expect(findWeightValue().exists()).toBe(true);
      expect(findWeightValue().text()).toBe('5');
    });
  });

  describe('keyboard shortcuts', () => {
    beforeEach(() => {
      createComponent();
    });

    it('saves on Enter key', async () => {
      await startEditing();
      await findWeightInput().setValue('10');
      await findWeightInput().trigger('keydown', { key: 'Enter' });
      await waitForPromises();
      await nextTick();

      expect(defaultMutationHandler).toHaveBeenCalledWith({
        input: {
          id: item.id,
          weightWidget: {
            weight: 10,
          },
        },
        useWorkItemFeatures: true,
      });
      expect(findWeightInput().exists()).toBe(false);
    });

    it('does not save when Escape is pressed', async () => {
      await startEditing();
      await findWeightInput().setValue('10');
      await findWeightInput().trigger('keydown', { key: 'Escape' });
      await nextTick();

      expect(defaultMutationHandler).not.toHaveBeenCalled();
      expect(findWeightInput().exists()).toBe(false);
    });
  });
});
