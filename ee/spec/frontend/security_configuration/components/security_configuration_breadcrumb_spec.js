import { shallowMount } from '@vue/test-utils';
import { GlBreadcrumb } from '@gitlab/ui';
import SecurityConfigurationBreadcrumb from 'ee/security_configuration/components/security_configuration_breadcrumb.vue';
import { stubComponent } from 'helpers/stub_component';

const STATIC_BREADCRUMBS = [{ text: 'My Group', href: '/my-group' }];

describe('SecurityConfigurationBreadcrumb', () => {
  let wrapper;

  const createComponent = ({
    route = { name: 'index', params: {}, path: '/', matched: [] },
  } = {}) => {
    wrapper = shallowMount(SecurityConfigurationBreadcrumb, {
      mocks: { $route: route },
      propsData: { staticBreadcrumbs: STATIC_BREADCRUMBS },
      stubs: { GlBreadcrumb: stubComponent(GlBreadcrumb) },
    });
  };

  const findBreadcrumb = () => wrapper.findComponent(GlBreadcrumb);

  describe('on the index route', () => {
    it('includes the static breadcrumbs and a "Security configuration" crumb', () => {
      createComponent();

      expect(findBreadcrumb().props('items')).toEqual([
        ...STATIC_BREADCRUMBS,
        { text: 'Security configuration', to: '/' },
      ]);
    });
  });

  describe('on the scanner_details route', () => {
    beforeEach(() => {
      createComponent({
        route: {
          name: 'scanner_details',
          params: { scanner_key: 'SECRET_DETECTION' },
          path: '/scanners/SECRET_DETECTION',
          matched: [],
        },
      });
    });

    it('includes the static breadcrumbs, the "Security configuration" crumb, and the scanner name crumb', () => {
      expect(findBreadcrumb().props('items')).toEqual([
        ...STATIC_BREADCRUMBS,
        { text: 'Security configuration', to: '/' },
        { text: 'Secret detection configuration', to: '/scanners/SECRET_DETECTION' },
      ]);
    });
  });

  describe('on a wizard route with a breadcrumb', () => {
    it('includes a crumb for the wizard', () => {
      createComponent({
        route: {
          name: 'triage_step_items',
          params: {},
          path: '/enable_triage_and_remediation/items',
          matched: [
            {
              path: '/enable_triage_and_remediation',
              meta: { breadcrumb: 'Roll out Automated Triage and Remediation' },
            },
            { path: '/enable_triage_and_remediation/items', meta: {} },
          ],
        },
      });

      expect(findBreadcrumb().props('items')).toEqual([
        ...STATIC_BREADCRUMBS,
        { text: 'Security configuration', to: '/' },
        { text: 'Roll out Automated Triage and Remediation', to: '/enable_triage_and_remediation' },
      ]);
    });
  });
});
