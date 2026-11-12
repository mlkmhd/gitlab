import Vue from 'vue';
import VueApollo from 'vue-apollo';
import { GlButton } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import WorkItemRelationshipIcons from '~/work_items/components/shared/work_item_relationship_icons.vue';
import { LINKED_CATEGORIES_MAP } from '~/work_items/constants';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { createMockDirective } from 'helpers/vue_mock_directive';
import workItemLinkedItemsSlimQuery from '~/work_items/graphql/work_items_linked_items_slim.query.graphql';

import { mockLinkedItems, workItemLinkedItemsFeaturesResponse } from '../../mock_data';

describe('WorkItemRelationshipIcons', () => {
  Vue.use(VueApollo);

  let wrapper;

  const workItemLinkedItemsSuccessHandler = jest
    .fn()
    .mockResolvedValue(workItemLinkedItemsFeaturesResponse);

  const createComponent = async ({
    workItemType = 'Task',
    workItemLinkedItemsHandler = workItemLinkedItemsSuccessHandler,
  } = {}) => {
    const mockApollo = createMockApollo([
      [workItemLinkedItemsSlimQuery, workItemLinkedItemsHandler],
    ]);

    wrapper = shallowMountExtended(WorkItemRelationshipIcons, {
      apolloProvider: mockApollo,
      directives: {
        GlTooltip: createMockDirective('gl-tooltip'),
      },
      propsData: {
        workItemType,
        workItemIid: '1',
        workItemFullPath: 'gitlab-org/gitlab-test',
        workItemWebUrl: '/gitlab-org/gitlab-test/-/work_items/1',
        blockingCount: 1,
        blockedByCount: 1,
      },
    });

    await waitForPromises();
  };

  const findBlockedIcon = () => wrapper.findComponentByTestId('relationship-blocked-by-icon');
  const findBlockingIcon = () => wrapper.findComponentByTestId('relationship-blocks-icon');

  const blockedItems = mockLinkedItems.linkedItems.nodes.filter(
    (item) => item.linkType === LINKED_CATEGORIES_MAP.IS_BLOCKED_BY,
  );
  const blockingItems = mockLinkedItems.linkedItems.nodes.filter(
    (item) => item.linkType === LINKED_CATEGORIES_MAP.BLOCKS,
  );

  it('renders the correct number of blocked and blocking items', () => {
    createComponent();

    expect(findBlockedIcon().exists()).toBe(true);
    expect(findBlockedIcon().text()).toContain(blockedItems.length.toString());

    expect(findBlockingIcon().exists()).toBe(true);
    expect(findBlockingIcon().text()).toContain(blockingItems.length.toString());
  });

  it('renders the correct aria labels for icons', () => {
    createComponent();

    expect(findBlockedIcon().attributes('aria-label')).toBe('Task is blocked by 1 item');
    expect(findBlockingIcon().attributes('aria-label')).toBe('Task blocks 1 item');
  });

  it('renders the icons as buttons', () => {
    createComponent();

    expect(wrapper.findAllComponents(GlButton)).toHaveLength(2);
  });

  it('renders only blocked icon if no blocking relationship exists', () => {
    createComponent({ linkedWorkItems: blockedItems });

    expect(findBlockedIcon().exists()).toBe(true);
    expect(findBlockingIcon().exists()).toBe(true);
    expect(findBlockedIcon().text()).toContain(blockedItems.length.toString());
  });

  it('renders only blocking icon if no blocked relationship exists', () => {
    createComponent({ linkedWorkItems: blockingItems });

    expect(findBlockingIcon().exists()).toBe(true);
    expect(findBlockedIcon().exists()).toBe(true);
    expect(findBlockingIcon().text()).toContain(blockedItems.length.toString());
  });

  it('does not query child link items if the icons are not hovered', () => {
    createComponent();

    expect(workItemLinkedItemsSuccessHandler).not.toHaveBeenCalled();
  });

  it('triggers child link items query on hover', async () => {
    createComponent();

    await findBlockedIcon().vm.$emit('mouseenter');
    await waitForPromises();

    expect(workItemLinkedItemsSuccessHandler).toHaveBeenCalled();
  });

  describe('when an icon gets keyboard focus', () => {
    it.each`
      icon            | findIcon
      ${'blocked by'} | ${findBlockedIcon}
      ${'blocks'}     | ${findBlockingIcon}
    `('triggers child link items query for the $icon icon', async ({ findIcon }) => {
      createComponent();

      await findIcon().vm.$emit('focus');
      await waitForPromises();

      expect(workItemLinkedItemsSuccessHandler).toHaveBeenCalled();
    });
  });

  it('passes useWorkItemFeatures to the query', async () => {
    createComponent();

    await findBlockedIcon().vm.$emit('mouseenter');
    await waitForPromises();

    expect(workItemLinkedItemsSuccessHandler).toHaveBeenCalledWith(
      expect.objectContaining({ useWorkItemFeatures: true }),
    );
  });
});
