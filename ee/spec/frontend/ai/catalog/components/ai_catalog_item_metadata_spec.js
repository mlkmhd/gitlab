import { GlBadge, GlIcon, GlLink, GlSprintf } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import AiCatalogItemMetadata from 'ee/ai/catalog/components/ai_catalog_item_metadata.vue';
import AiCatalogItemUserAttribution from 'ee/ai/catalog/components/ai_catalog_item_user_attribution.vue';
import {
  VERSION_LATEST,
  AI_CATALOG_TYPE_FOUNDATIONAL_AGENT,
  VISIBILITY_LEVEL_PRIVATE,
  VISIBILITY_LEVEL_PUBLIC,
  VISIBILITY_LEVEL_RESTRICTED,
} from 'ee/ai/catalog/constants';
import { mockAgent, mockFlow, mockThirdPartyFlow } from '../mock_data';

describe('AiCatalogItemMetadata', () => {
  let wrapper;

  const GlIconStub = stubComponent(GlIcon);

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(AiCatalogItemMetadata, {
      propsData: {
        item: mockAgent,
        versionKey: VERSION_LATEST,
        ...props,
      },
      directives: {
        GlTooltip: createMockDirective('gl-tooltip'),
      },
      stubs: {
        GlIcon: GlIconStub,
        GlSprintf,
      },
    });
  };

  const findUserAttribution = () => wrapper.findComponent(AiCatalogItemUserAttribution);
  const findGitLabMaintainedItem = () => wrapper.findByTestId('metadata-gitlab-maintained');
  const findExternalItem = () => wrapper.findByTestId('metadata-external');
  const findVersionItem = () => wrapper.findByTestId('metadata-version');
  const findVisibilityItem = () => wrapper.findByTestId('metadata-visibility');
  const findManagedByItem = () => wrapper.findByTestId('metadata-managed-by');

  describe('visibility field', () => {
    it('shows the visibility level as a badge with its icon and a description tooltip', () => {
      createComponent();

      const visibility = findVisibilityItem();
      const badge = visibility.findComponent(GlBadge);
      expect(visibility.text()).toBe('Public');
      expect(badge.props('icon')).toBe('earth');
      expect(getBinding(visibility.element, 'gl-tooltip').value).toBe(
        'Anyone can view and use the agent.',
      );
    });

    it.each`
      visibility                     | expectedLabel   | expectedIcon      | expectedVariant
      ${VISIBILITY_LEVEL_PUBLIC}     | ${'Public'}     | ${'earth'}        | ${'success'}
      ${VISIBILITY_LEVEL_RESTRICTED} | ${'Restricted'} | ${'organization'} | ${'info'}
      ${VISIBILITY_LEVEL_PRIVATE}    | ${'Private'}    | ${'lock'}         | ${'warning'}
    `(
      'renders a $expectedVariant badge when visibility is $visibility',
      ({ visibility, expectedLabel, expectedIcon, expectedVariant }) => {
        createComponent({ item: { ...mockAgent, visibility } });

        const badge = findVisibilityItem().findComponent(GlBadge);
        expect(badge.text()).toBe(expectedLabel);
        expect(badge.props('icon')).toBe(expectedIcon);
        expect(badge.props('variant')).toBe(expectedVariant);
      },
    );

    it('is keyboard focusable so the tooltip can be reached', () => {
      createComponent();

      expect(findVisibilityItem().attributes('tabindex')).toBe('0');
    });

    it('does not make items without a tooltip focusable', () => {
      createComponent();

      expect(findVersionItem().attributes('tabindex')).toBeUndefined();
    });

    it('uses the flow description for a flow', () => {
      createComponent({ item: { ...mockFlow, visibility: VISIBILITY_LEVEL_PRIVATE } });

      const visibility = findVisibilityItem();
      expect(visibility.text()).toBe('Private');
      expect(getBinding(visibility.element, 'gl-tooltip').value).toContain('This flow');
    });

    it('uses the agent description for a third-party flow, which is shown as an external agent', () => {
      createComponent({ item: { ...mockThirdPartyFlow, visibility: VISIBILITY_LEVEL_PRIVATE } });

      const visibility = findVisibilityItem();
      expect(visibility.text()).toBe('Private');
      expect(getBinding(visibility.element, 'gl-tooltip').value).toContain('This agent');
    });
  });

  describe('managed by field', () => {
    it('links to the managing project', () => {
      createComponent();

      const link = findManagedByItem().findComponent(GlLink);
      expect(link.attributes('href')).toBe(mockAgent.project.webPath);
      expect(link.text()).toBe(mockAgent.project.nameWithNamespace);
    });

    it('is not shown for a GitLab-maintained item', () => {
      createComponent({ item: { ...mockAgent, verificationLevel: 'GITLAB_MAINTAINED' } });

      expect(findManagedByItem().exists()).toBe(false);
    });
  });

  describe('user attribution', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders the user attribution component with correct props', () => {
      const attribution = findUserAttribution();
      expect(attribution.exists()).toBe(true);
      expect(attribution.props('item')).toBe(mockAgent);
      expect(attribution.props('versionKey')).toBe(VERSION_LATEST);
    });
  });

  describe('gitlab-maintained field', () => {
    describe('when item is a GitLab-maintained agent', () => {
      beforeEach(() => {
        createComponent({
          item: {
            ...mockAgent,
            verificationLevel: 'GITLAB_MAINTAINED',
          },
        });
      });

      it('displays "GitLab-managed" text', () => {
        const gitLabMaintained = findGitLabMaintainedItem();
        expect(gitLabMaintained.text()).toBe('GitLab-managed');
        expect(gitLabMaintained.findComponent(GlIcon).props('name')).toBe('tanuki-verified');
      });
    });

    describe('when item is a GitLab-maintained flow', () => {
      beforeEach(() => {
        createComponent({
          item: {
            ...mockFlow,
            verificationLevel: 'GITLAB_MAINTAINED',
          },
        });
      });

      it('displays "GitLab-managed" text', () => {
        const gitLabMaintained = findGitLabMaintainedItem();
        expect(gitLabMaintained.text()).toBe('GitLab-managed');
        expect(gitLabMaintained.findComponent(GlIcon).props('name')).toBe('tanuki-verified');
      });
    });

    describe('when item is a GitLab-maintained third-party flow', () => {
      beforeEach(() => {
        createComponent({
          item: {
            ...mockThirdPartyFlow,
            verificationLevel: 'GITLAB_MAINTAINED',
          },
        });
      });

      it('displays "GitLab-managed" text', () => {
        const gitLabMaintained = findGitLabMaintainedItem();
        expect(gitLabMaintained.text()).toBe('GitLab-managed');
        expect(gitLabMaintained.findComponent(GlIcon).props('name')).toBe('tanuki-verified');
      });
    });

    it('does not display gitlab-maintained metadata when item is not GitLab-maintained', () => {
      createComponent({
        item: {
          ...mockAgent,
          verificationLevel: 'UNVERIFIED',
        },
      });

      expect(findGitLabMaintainedItem().exists()).toBe(false);
    });

    it('keys off verificationLevel, not foundational, when the two disagree', () => {
      createComponent({
        item: {
          ...mockAgent,
          foundational: true,
          verificationLevel: 'UNVERIFIED',
        },
      });

      expect(findGitLabMaintainedItem().exists()).toBe(false);
    });
  });

  describe('external field', () => {
    describe('when item type is AI_CATALOG_TYPE_THIRD_PARTY_FLOW', () => {
      beforeEach(() => {
        createComponent({ item: mockThirdPartyFlow });
      });

      it('displays the "External" label with the correct icon', () => {
        const external = findExternalItem();
        expect(external.exists()).toBe(true);
        expect(external.text()).toContain('External');
        expect(external.findComponent(GlIcon).props('name')).toBe('connected');
      });

      it('has the correct tooltip text', () => {
        expect(getBinding(findExternalItem().element, 'gl-tooltip').value).toBe(
          'Connects to an AI model provider outside GitLab.',
        );
      });
    });

    describe('when item type is not AI_CATALOG_TYPE_THIRD_PARTY_FLOW', () => {
      beforeEach(() => {
        createComponent();
      });

      it('does not display the external metadata', () => {
        expect(findExternalItem().exists()).toBe(false);
      });
    });
  });

  describe('version field', () => {
    beforeEach(() => {
      createComponent();
    });

    it('should show the human-readable version with correct value and icon', () => {
      const version = findVersionItem();
      expect(version.exists()).toBe(true);
      expect(version.findComponent(GlIcon).props('name')).toBe('tag');
      expect(version.text()).toContain('v1.0.0-draft');
    });

    it('should show the version tag for a foundational agent', () => {
      createComponent({
        item: {
          ...mockAgent,
          itemType: AI_CATALOG_TYPE_FOUNDATIONAL_AGENT,
          foundational: true,
          latestVersion: {
            ...mockAgent.latestVersion,
            humanVersionName: '^1.0.0',
            versionName: '^1.0.0',
          },
        },
      });

      const version = findVersionItem();
      expect(version.exists()).toBe(true);
      expect(version.text()).toContain('^1.0.0');
    });
  });

  describe('usage count field', () => {
    const findUsageCountItem = () => wrapper.findByTestId('metadata-usage-count');

    describe('when last30DayUsageCount is defined', () => {
      beforeEach(() => {
        createComponent({
          item: {
            ...mockAgent,
            last30DayUsageCount: 42,
          },
        });
      });

      it('renders the usage count metadata item with chart icon', () => {
        const usageCount = findUsageCountItem();
        expect(usageCount.exists()).toBe(true);
        expect(usageCount.findComponent(GlIcon).props('name')).toBe('chart');
      });

      it('displays the count value from the item', () => {
        const usageCount = findUsageCountItem();
        expect(usageCount.text()).toContain('42');
      });

      it('has the correct tooltip binding', () => {
        expect(getBinding(findUsageCountItem().element, 'gl-tooltip').value).toBe(
          'The number of projects that have used this item in the last 30 days.',
        );
      });
    });

    describe('when last30DayUsageCount is 0', () => {
      beforeEach(() => {
        createComponent();
      });

      it('renders the usage count metadata item displaying 0', () => {
        const usageCount = findUsageCountItem();
        expect(usageCount.exists()).toBe(true);
        expect(usageCount.text()).toContain('0');
      });
    });

    describe('when last30DayUsageCount is undefined', () => {
      beforeEach(() => {
        createComponent({
          item: {
            ...mockAgent,
            last30DayUsageCount: undefined,
          },
        });
      });

      it('does not render the usage count metadata item', () => {
        expect(findUsageCountItem().exists()).toBe(false);
      });
    });
  });
});
