import { GlAlert, GlSprintf } from '@gitlab/ui';
import { nextTick } from 'vue';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import InputCopyToggleVisibility from '~/vue_shared/components/input_copy_toggle_visibility/input_copy_toggle_visibility.vue';
import App from 'ee/packages_and_registries/artifact_registry/settings/app.vue';
import ActivationSection from 'ee/packages_and_registries/artifact_registry/settings/activation_section.vue';

describe('ArtifactRegistrySettingsApp', () => {
  let wrapper;

  const createComponent = () => {
    wrapper = shallowMountExtended(App, {
      provide: { organizationId: '42' },
      stubs: { GlSprintf },
    });
  };

  const findSettingsBlock = () => wrapper.findComponentByTestId('artifact-registry-settings');
  const findOrganizationIdBlock = () =>
    wrapper.findComponentByTestId('artifact-registry-organization-id');
  const findOrganizationIdInput = () => wrapper.findComponent(InputCopyToggleVisibility);
  const findActivationSection = () => wrapper.findComponent(ActivationSection);
  // The alert announces on its own: `GlAlert` carries `role="alert"` for the success and
  // danger variants, so wrapping it in a live region would nest one inside another. The
  // screen-reader-only `aria-live` span used elsewhere in this tree is for announcing
  // plain text, which has no alert to carry it.
  const findAlert = () => wrapper.findComponentByTestId('settings-alert-region');
  const findAlerts = () => wrapper.findAllComponents(GlAlert);

  const announce = async (outcome, message) => {
    findActivationSection().vm.$emit(outcome, message);
    await nextTick();
  };

  beforeEach(() => createComponent());

  it('renders the Activation settings block', () => {
    expect(findSettingsBlock().props('title')).toBe('Activation');
  });

  it('describes the section as controlling access rather than creating a registry', () => {
    expect(findSettingsBlock().text()).toContain(
      'Control artifact registry access for this organization. When enabled, all projects and groups have access to a unified registry.',
    );
  });

  it('renders the activation section inside the block', () => {
    expect(findSettingsBlock().findComponent(ActivationSection).exists()).toBe(true);
  });

  describe('the outcome of an action', () => {
    it('announces nothing until an action reports an outcome', () => {
      expect(findAlerts()).toHaveLength(0);
    });

    it('announces a successful action as a success', async () => {
      await announce('success', 'Artifact Registry was disabled.');

      expect(findAlert().props('variant')).toBe('success');
      expect(findAlert().text()).toBe('Artifact Registry was disabled.');
    });

    it('announces a failed action as a failure', async () => {
      await announce('error', 'Something went wrong. Please try again.');

      expect(findAlert().props('variant')).toBe('danger');
      expect(findAlert().text()).toBe('Something went wrong. Please try again.');
    });

    it('replaces the announcement it was showing, so two runs do not read as two outcomes', async () => {
      await announce('success', 'Artifact Registry was enabled.');
      await announce('error', 'Something went wrong. Please try again.');

      expect(findAlerts()).toHaveLength(1);
      expect(findAlerts().at(0).text()).toBe('Something went wrong. Please try again.');
    });

    it('clears the announcement once it is dismissed', async () => {
      await announce('success', 'Artifact Registry was disabled.');

      findAlert().vm.$emit('dismiss');
      await nextTick();

      expect(findAlerts()).toHaveLength(0);
    });
  });

  describe('the organization ID', () => {
    it('renders the Organization ID settings block', () => {
      expect(findOrganizationIdBlock().props('title')).toBe('Organization ID');
    });

    it('explains the ID goes in the organization header', () => {
      expect(findOrganizationIdBlock().text()).toContain(
        'Use this ID in the X-GitLab-Organization-ID header when you call the artifact registry API.',
      );
      expect(findOrganizationIdBlock().find('code').text()).toBe('X-GitLab-Organization-ID');
    });

    it('shows the ID read-only with a copy button and no visibility toggle', () => {
      expect(findOrganizationIdInput().props()).toMatchObject({
        value: '42',
        readonly: true,
        showCopyButton: true,
        showToggleVisibilityButton: false,
        copyButtonTitle: 'Copy organization ID',
      });
    });

    it('labels the input so screen readers can name it', () => {
      wrapper = mountExtended(App, {
        provide: { organizationId: '42' },
        stubs: { ActivationSection: true },
      });

      expect(wrapper.findByLabelText('Organization ID').element.value).toBe('42');
    });
  });
});
