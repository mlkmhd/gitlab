import { GlPopover, GlBadge } from '@gitlab/ui';
import { shallowMount } from '@vue/test-utils';
import ResolutionBadge from 'ee/vulnerabilities/components/resolution_badge.vue';

const POPOVER_TITLE = 'Vulnerability no longer detected';
const POPOVER_CONTENT =
  'The vulnerability is no longer detected. Verify the vulnerability has been fixed or removed before changing its status.';
const POPOVER_CONTENT_RESOLVED = 'The vulnerability is no longer detected on the default branch.';

describe('Resolution badge component', () => {
  let wrapper;

  const findBadge = () => wrapper.findComponent(GlBadge);
  const findPopover = () => wrapper.findComponent(GlPopover);

  const createWrapper = (props = {}) => {
    wrapper = shallowMount(ResolutionBadge, { propsData: props });
  };

  it('should display the correct icon', () => {
    createWrapper();

    expect(findBadge().props('icon')).toBe('check-circle-dashed');
  });

  it('should link the badge and the popover', () => {
    createWrapper();

    expect(findPopover().props('target')()).toEqual(findBadge().element);
  });

  it.each`
    isResolved | content
    ${false}   | ${POPOVER_CONTENT}
    ${true}    | ${POPOVER_CONTENT_RESOLVED}
  `('shows the correct popover text when isResolved is $isResolved', ({ isResolved, content }) => {
    createWrapper({ isResolved });

    const popoverAttributes = findPopover().attributes();

    expect(popoverAttributes.title).toBe(POPOVER_TITLE);
    expect(popoverAttributes.content).toBe(content);
  });
});
