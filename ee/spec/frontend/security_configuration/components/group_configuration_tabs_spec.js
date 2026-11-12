import { GlTab, GlTabs } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import GroupConfigurationTabs from 'ee/security_configuration/components/group_configuration_tabs.vue';
import GroupScannersOverview from 'ee/security_configuration/components/scan_profiles/group_scanners_overview.vue';
import GroupTriageAndRemediationOverview from 'ee/security_configuration/components/scan_profiles/group_triage_and_remediation_overview.vue';
import ConfigureAttributes from 'ee/security_configuration/components/security_attributes/configure_attributes.vue';
import ScanCoverageRecommendationAlert from 'ee/security_configuration/components/scan_coverage_recommendation_alert.vue';

describe('GroupConfigurationTabs', () => {
  let wrapper;

  const createComponent = ({ provide = {} } = {}) => {
    wrapper = shallowMountExtended(GroupConfigurationTabs, {
      stubs: { GlTab },
      provide: {
        canManageAttributes: false,
        canReadScanProfiles: false,
        glFeatures: { triageAndRemediationProfilesUi: false },
        ...provide,
      },
    });
  };

  const findPageHeading = () => wrapper.findComponent(PageHeading);
  const findTabs = () => wrapper.findComponent(GlTabs);
  const findAllTabs = () => wrapper.findAllComponents(GlTab);
  const findTriageAndRemediationTab = () =>
    wrapper.findComponentByTestId('triage-and-remediation-tab');
  const findGroupScannersOverview = () => wrapper.findComponent(GroupScannersOverview);
  const findConfigureAttributes = () => wrapper.findComponent(ConfigureAttributes);
  const findScanCoverageRecommendationAlert = () =>
    wrapper.findComponent(ScanCoverageRecommendationAlert);

  it('renders the "Security configuration" page heading', () => {
    createComponent();

    expect(findPageHeading().props('heading')).toBe('Security configuration');
  });

  it('renders the scan coverage recommendation alert above the tabs', () => {
    createComponent();

    expect(findScanCoverageRecommendationAlert().exists()).toBe(true);
  });

  describe('tab query-param syncing', () => {
    beforeEach(() => {
      createComponent({
        provide: {
          canManageAttributes: true,
          canReadScanProfiles: true,
        },
      });
    });

    it('syncs the active tab with the "tab" query param', () => {
      expect(findTabs().props('syncActiveTabWithQueryParams')).toBe(true);
      expect(findTabs().props('queryParamName')).toBe('tab');
    });

    it('exposes "scanners" and "attributes" as deep-link tab values', () => {
      const values = findAllTabs().wrappers.map((tab) => tab.props('queryParamValue'));
      expect(values).toEqual(['scanners', 'attributes']);
    });
  });

  describe('Scanners tab', () => {
    it('renders GroupScannersOverview when canReadScanProfiles is true', () => {
      createComponent({
        provide: {
          canReadScanProfiles: true,
        },
      });

      expect(findGroupScannersOverview().exists()).toBe(true);
    });

    it('does not render GroupScannersOverview when canReadScanProfiles is false', () => {
      createComponent();

      expect(findGroupScannersOverview().exists()).toBe(false);
    });
  });

  describe('Automated Triage and Remediation tab', () => {
    describe.each`
      flag     | canRead  | result
      ${false} | ${false} | ${false}
      ${false} | ${true}  | ${false}
      ${true}  | ${false} | ${false}
      ${true}  | ${true}  | ${true}
    `(
      'with the flag set to $flag and canReadScanProfiles set to $canRead',
      ({ flag, canRead, result }) => {
        beforeEach(() => {
          createComponent({
            provide: {
              canReadScanProfiles: canRead,
              glFeatures: { triageAndRemediationProfilesUi: flag },
            },
          });
        });

        it('renders the tab only when enabled and readable', () => {
          expect(findTriageAndRemediationTab().exists()).toBe(result);
        });
      },
    );

    describe('when the tab is available', () => {
      beforeEach(() => {
        createComponent({
          provide: {
            canManageAttributes: true,
            canReadScanProfiles: true,
            glFeatures: { triageAndRemediationProfilesUi: true },
          },
        });
      });

      it('is selected by the automated-triage-and-remediation query parameter value', () => {
        expect(findTriageAndRemediationTab().props('queryParamValue')).toBe(
          'automated-triage-and-remediation',
        );
      });

      it('sits between the scanners and attributes tabs', () => {
        const values = findAllTabs().wrappers.map((tab) => tab.props('queryParamValue'));

        expect(values).toEqual(['scanners', 'automated-triage-and-remediation', 'attributes']);
      });

      it('renders GroupTriageAndRemediationOverview', () => {
        expect(wrapper.findComponent(GroupTriageAndRemediationOverview).exists()).toBe(true);
      });
    });
  });

  describe('Security attributes tab', () => {
    it('renders ConfigureAttributes and the tab description when canManageAttributes is true', () => {
      createComponent({ provide: { canManageAttributes: true } });

      expect(findConfigureAttributes().exists()).toBe(true);
    });

    it('does not render the Security attributes tab when canManageAttributes is false', () => {
      createComponent();

      expect(findConfigureAttributes().exists()).toBe(false);
    });
  });
});
