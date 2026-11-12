import { GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import StageCard from 'ee/ai/duo_agents_platform/pages/software_factory/components/stage_card.vue';

const buildStage = {
  name: 'build',
  skipped: false,
  status: 'In dev',
  start: 'automated',
  exit: 'manual',
  flow: 414,
  markMergeRequestsReady: true,
};

describe('StageCard', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(StageCard, {
      propsData: { stage: buildStage, position: 3, flowName: 'Developer flow', ...props },
      stubs: { GlSprintf },
    });
  };

  const findCard = () => wrapper.findByTestId('stage-card');

  describe('for an active stage', () => {
    beforeEach(() => {
      createComponent();
    });

    it('shows the stage, its status, how it starts and exits, and its flow', () => {
      expect(wrapper.text()).toContain('Build');
      expect(wrapper.findByTestId('stage-card-status').text()).toMatch(/^Status:\s+In dev$/);
      expect(wrapper.findByTestId('stage-card-mode').text()).toBe(
        'Starts automatically · Exits manually',
      );
      expect(wrapper.findByTestId('stage-card-flow').text()).toMatch(/^Flow:\s+Developer flow$/);
      expect(wrapper.findByTestId('stage-card-mark-ready').exists()).toBe(true);
    });

    it('emits select when clicked', () => {
      findCard().trigger('click');

      expect(wrapper.emitted('select')).toEqual([['build']]);
    });
  });

  describe('for a skipped stage', () => {
    beforeEach(() => {
      createComponent({ stage: { name: 'verify', skipped: true }, flowName: '' });
    });

    it('shows that the stage is not enabled, without its details', () => {
      expect(wrapper.findByTestId('stage-card-skipped').exists()).toBe(true);
      expect(wrapper.findByTestId('stage-card-status').exists()).toBe(false);
      expect(wrapper.findByTestId('stage-card-mode').exists()).toBe(false);
    });
  });

  // Both states are asserted because a boolean false would drop the attribute
  // altogether, leaving the card announced as a plain button rather than a
  // toggle that is off.
  it.each([
    [true, 'true'],
    [false, 'false'],
  ])('reports aria-pressed as %s', (selected, expected) => {
    createComponent({ selected });

    expect(findCard().attributes('aria-pressed')).toBe(expected);
  });

  describe('with a warning', () => {
    beforeEach(() => {
      createComponent({ warning: 'Will not start' });
    });

    it('shows the warning', () => {
      expect(wrapper.findByTestId('stage-card-warning').text()).toBe('Will not start');
    });
  });

  describe('with errors', () => {
    beforeEach(() => {
      createComponent({ errorCount: 2 });
    });

    it('shows the error count', () => {
      expect(wrapper.findByTestId('stage-card-errors').text()).toBe('2 errors');
    });
  });
});
