import { GlLink } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import EnableScannersLink from 'ee/security_inventory/components/enable_scanners_link.vue';

describe('EnableScannersLink', () => {
  let wrapper;

  const findLink = () => wrapper.findComponent(GlLink);

  const createComponent = (propsData = {}) => {
    wrapper = shallowMountExtended(EnableScannersLink, { propsData });
  };

  describe('when a web path is given', () => {
    beforeEach(() => {
      createComponent({ webPath: '/groups/gitlab-org' });
    });

    it('links to the enable scanners wizard', () => {
      expect(findLink().text()).toBe('Enable scanners');
      expect(findLink().attributes('href')).toBe(
        '/groups/gitlab-org/-/security/configuration#/enable_scanners',
      );
    });
  });

  describe('when no web path is given', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders nothing', () => {
      expect(findLink().exists()).toBe(false);
    });
  });
});
