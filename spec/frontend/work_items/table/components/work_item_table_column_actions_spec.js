import { GlDisclosureDropdown } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { COLUMN_DIRECTION } from '~/work_items/table/constants';
import WorkItemTableColumnActions from '~/work_items/table/components/work_item_table_column_actions.vue';

describe('WorkItemTableColumnActions', () => {
  let wrapper;

  const findDropdown = () => wrapper.findComponent(GlDisclosureDropdown);
  const findItems = () => findDropdown().props('items')[0].items;
  const findItemTexts = () => findItems().map(({ text }) => text);
  const findItem = (text) => findItems().find((item) => item.text === text);

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(WorkItemTableColumnActions, {
      propsData: {
        columnLabel: 'Status',
        ...props,
      },
    });
  };

  it('names the menu after its column for screen readers', () => {
    createComponent({ canHide: true });

    expect(findDropdown().props()).toMatchObject({
      toggleText: 'Status column options',
      textSrOnly: true,
      icon: 'ellipsis_v',
    });
  });

  it('groups the actions under a Column options heading', () => {
    createComponent({ canHide: true });

    expect(findDropdown().props('items')[0].name).toBe('Column options');
  });

  it('offers every action the column allows', () => {
    createComponent({ canHide: true, canMoveLeft: true, canMoveRight: true });

    expect(findItemTexts()).toEqual(['Hide field', 'Move left', 'Move right']);
  });

  it('leaves out the actions the column does not allow', () => {
    createComponent({ canMoveRight: true });

    expect(findItemTexts()).toEqual(['Move right']);
  });

  it('renders nothing when no action is allowed', () => {
    createComponent();

    expect(findDropdown().exists()).toBe(false);
  });

  it.each`
    text            | event            | payload
    ${'Hide field'} | ${'hide-column'} | ${undefined}
    ${'Move left'}  | ${'move-column'} | ${COLUMN_DIRECTION.LEFT}
    ${'Move right'} | ${'move-column'} | ${COLUMN_DIRECTION.RIGHT}
  `('emits $event when $text is chosen', ({ text, event, payload }) => {
    createComponent({ canHide: true, canMoveLeft: true, canMoveRight: true });

    findItem(text).action();

    expect(wrapper.emitted(event)).toEqual([payload === undefined ? [] : [payload]]);
  });
});
