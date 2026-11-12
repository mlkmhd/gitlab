import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import WorkplanSkeleton from 'ee/work_items/components/implementation_widget/workplan_skeleton.vue';

describe('WorkplanSkeleton', () => {
  let wrapper;

  const findBars = () => wrapper.findAll('.gl-animate-skeleton-loader');

  beforeEach(() => {
    wrapper = shallowMountExtended(WorkplanSkeleton);
  });

  it('renders 4 sections of a heading and paragraph lines', () => {
    expect(wrapper.findByTestId('workplan-skeleton').element.children).toHaveLength(4);
    expect(findBars()).toHaveLength(20);
  });

  it('keeps every bar within the panel width', () => {
    findBars().wrappers.forEach((bar) => {
      expect(bar.classes()).toContain('gl-max-w-full');
    });
  });
});
