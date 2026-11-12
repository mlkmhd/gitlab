import { GlDisclosureDropdown } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import NavControls from '~/ci/pipelines_page/components/nav_controls.vue';

describe('Pipelines Nav Controls', () => {
  let wrapper;

  const createComponent = (props = {}, { pipelinesAnalyticsPath = '/pipelines/charts' } = {}) => {
    wrapper = shallowMountExtended(NavControls, {
      propsData: {
        ...props,
      },
      provide: {
        pipelinesAnalyticsPath,
      },
      directives: {
        GlTooltip: createMockDirective('gl-tooltip'),
      },
    });
  };

  const findRunPipelineButton = () => wrapper.findComponentByTestId('run-pipeline-button');
  const findViewAnalyticsButton = () => wrapper.findComponentByTestId('view-analytics-link');
  const findMoreActionsDropdown = () => wrapper.findComponent(GlDisclosureDropdown);
  const findClearCacheItem = () =>
    findMoreActionsDropdown()
      .props('items')
      .find((item) => item.extraAttrs['data-testid'] === 'clear-cache-button');

  describe('New pipeline button', () => {
    it('renders a small primary button linking to the new pipeline page', () => {
      createComponent({ newPipelinePath: 'foo' });

      const runPipelineButton = findRunPipelineButton();
      expect(runPipelineButton.text()).toContain('New pipeline');
      expect(runPipelineButton.attributes('href')).toBe('foo');
      expect(runPipelineButton.props()).toMatchObject({
        category: 'primary',
        variant: 'confirm',
        size: 'small',
      });
    });

    it('does not render when no path is provided', () => {
      createComponent({ resetCachePath: 'foo' });

      expect(findRunPipelineButton().exists()).toBe(false);
    });
  });

  describe('View analytics button', () => {
    it('renders a small tertiary icon-only button linking to CI/CD analytics', () => {
      createComponent();

      const button = findViewAnalyticsButton();
      expect(button.attributes()).toMatchObject({
        href: '/pipelines/charts',
        title: 'View analytics',
        'aria-label': 'View analytics',
      });
      expect(button.props()).toMatchObject({
        icon: 'cicd-analytics',
        category: 'tertiary',
        size: 'small',
      });
      expect(button.text()).toBe('');
      expect(getBinding(button.element, 'gl-tooltip').modifiers).toEqual({ bottom: true });
    });

    it('does not render when no path is provided', () => {
      createComponent({}, { pipelinesAnalyticsPath: '' });

      expect(findViewAnalyticsButton().exists()).toBe(false);
    });
  });

  describe('More actions dropdown', () => {
    it('renders a small tertiary horizontal ellipsis toggle', () => {
      createComponent({ resetCachePath: 'foo' });

      expect(findMoreActionsDropdown().props()).toMatchObject({
        toggleText: 'More actions',
        textSrOnly: true,
        icon: 'ellipsis_h',
        category: 'tertiary',
        size: 'small',
        noCaret: true,
      });
    });

    it('shows a tooltip only while the dropdown is closed', async () => {
      createComponent({ resetCachePath: 'foo' });

      expect(getBinding(findMoreActionsDropdown().element, 'gl-tooltip').value).toBe(
        'More actions',
      );

      await findMoreActionsDropdown().vm.$emit('shown');

      expect(getBinding(findMoreActionsDropdown().element, 'gl-tooltip').value).toBe('');
    });

    it('does not render when no reset cache path is provided', () => {
      createComponent({ newPipelinePath: 'foo' });

      expect(findMoreActionsDropdown().exists()).toBe(false);
    });

    describe('Reset Runners Cache', () => {
      beforeEach(() => {
        createComponent({ newPipelinePath: 'foo', resetCachePath: 'foo' });
      });

      it('renders an item for resetting runner caches', () => {
        expect(findClearCacheItem().text).toBe('Clear runner caches');
      });

      it('emits reset-runners-cache when the item is clicked', () => {
        findClearCacheItem().action();

        expect(wrapper.emitted('reset-runners-cache')).toEqual([['foo']]);
      });

      it('shows the dropdown as loading while the cache resets', () => {
        createComponent({ resetCachePath: 'foo', isResetCacheButtonLoading: true });

        expect(findMoreActionsDropdown().props('loading')).toBe(true);
      });
    });
  });
});
