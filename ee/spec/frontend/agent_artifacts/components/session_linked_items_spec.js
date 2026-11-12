import { GlIcon, GlLink, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import SessionLinkedItems from 'ee/agent_artifacts/components/session_linked_items.vue';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import WorkItemTypeIcon from '~/work_items/components/work_item_type_icon.vue';
import { mockGroupedSessionLinks } from '../mock_data';

describe('SessionLinkedItems', () => {
  let wrapper;

  const createComponent = (props = mockGroupedSessionLinks) => {
    wrapper = shallowMountExtended(SessionLinkedItems, {
      propsData: props,
      stubs: { CrudComponent, GlSprintf },
    });
  };

  const findCrudComponent = () => wrapper.findComponent(CrudComponent);
  const findSource = () => wrapper.findByTestId('linked-items-source');
  const findCreated = () => wrapper.findByTestId('linked-items-created');
  const findItems = (group) => group.findAllByTestId('linked-item');
  const findItemLinks = (group) => group.findAllComponents(GlLink);
  const findMoreMessage = () => wrapper.findByTestId('linked-items-more');
  const findMoreLink = () => wrapper.findByTestId('linked-items-more-link');

  describe('with links in both groups', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders a collapsible "Linked items" card', () => {
      expect(findCrudComponent().props('title')).toBe('Linked items');
      expect(findCrudComponent().props('isCollapsible')).toBe(true);
    });

    it('renders both groups with their headings', () => {
      expect(findSource().find('h5').text()).toBe('Source');
      expect(findCreated().find('h5').text()).toBe('Created');
    });

    it('renders each item with its title, reference, and link', () => {
      const items = findItems(findSource());
      const links = findItemLinks(findSource());

      expect(items).toHaveLength(3);
      expect(links.wrappers.map((link) => [link.text(), link.attributes('href')])).toEqual([
        ['Source merge request', '/gitlab-org/security-scanner/-/merge_requests/11'],
        ['Source issue', '/gitlab-org/security-scanner/-/work_items/31'],
        [
          'Comment by Alice Smith',
          'http://gdk.test/gitlab-org/security-scanner/-/merge_requests/11#note_21',
        ],
      ]);
      expect(items.at(0).text()).toContain('!11');
      expect(items.at(1).text()).toContain('#31');
    });

    it('renders the created items', () => {
      expect(findItemLinks(findCreated()).wrappers.map((link) => link.text())).toEqual([
        'Created merge request',
        'Created task',
        'Comment by Duo Bot',
      ]);
    });

    it('renders an icon for merge requests and notes', () => {
      const items = findItems(findCreated());

      expect(items.at(0).findComponent(GlIcon).props('name')).toBe('git-merge');
      expect(items.at(2).findComponent(GlIcon).props('name')).toBe('comment');
    });

    it('renders the work item type icon for work items', () => {
      const icons = wrapper.findAllComponents(WorkItemTypeIcon);

      expect(icons.wrappers.map((icon) => icon.props())).toMatchObject([
        { workItemType: 'Issue', typeIconName: 'work-item-issue' },
        { workItemType: 'Task', typeIconName: 'work-item-task' },
      ]);
    });
  });

  it('hides the "Source" group when it is empty', () => {
    createComponent({ startedFrom: [], created: mockGroupedSessionLinks.created });

    expect(findSource().exists()).toBe(false);
    expect(findCreated().exists()).toBe(true);
  });

  it('hides the "Created" group when it is empty', () => {
    createComponent({ startedFrom: mockGroupedSessionLinks.startedFrom, created: [] });

    expect(findSource().exists()).toBe(true);
    expect(findCreated().exists()).toBe(false);
  });

  describe('more linked items message', () => {
    const sessionPath = '/gitlab-org/security-scanner/-/automate/agent-sessions/1908';

    it('is hidden by default', () => {
      createComponent();

      expect(findMoreMessage().exists()).toBe(false);
    });

    it('links to the full session details when there is a session path', () => {
      createComponent({ ...mockGroupedSessionLinks, hasMore: true, sessionPath });

      expect(findMoreMessage().text()).toBe(
        'Some linked items are not shown. View full session details',
      );
      expect(findMoreLink().attributes('href')).toBe(sessionPath);
    });

    it('renders only the message when there is no session path', () => {
      createComponent({ ...mockGroupedSessionLinks, hasMore: true });

      expect(findMoreMessage().text()).toBe('Some linked items are not shown.');
      expect(findMoreLink().exists()).toBe(false);
    });

    it('renders the message without empty group sections', () => {
      createComponent({ startedFrom: [], created: [], hasMore: true });

      expect(findSource().exists()).toBe(false);
      expect(findCreated().exists()).toBe(false);
      expect(findMoreMessage().exists()).toBe(true);
    });
  });
});
