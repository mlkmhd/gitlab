import { GlButton, GlIcon } from '@gitlab/ui';
import { mountExtended, shallowMountExtended } from 'helpers/vue_test_utils_helper';
import AppLink from '~/gitlab_apps/components/app_link.vue';

describe('AppLink', () => {
  let wrapper;

  const app = {
    id: 'gitlab_app_planner',
    title: 'GitLab Planner',
    icon: 'planning',
    link: 'https://planner.example.com/',
  };

  const findButton = () => wrapper.findComponent(GlButton);
  const findExternalIcon = () => wrapper.findComponent(GlIcon);

  beforeEach(() => {
    wrapper = shallowMountExtended(AppLink, { propsData: { app } });
  });

  it('links to the app with its icon and title', () => {
    expect(findButton().props('icon')).toBe('planning');
    expect(findButton().attributes('href')).toBe('https://planner.example.com/');
    expect(findButton().text()).toBe('GitLab Planner');
  });

  it('marks the link as external for assistive technology', () => {
    expect(findExternalIcon().props()).toMatchObject({
      name: 'external-link',
      ariaLabel: '(external link)',
    });
  });

  it('opens the app in a new tab without exposing the opener', () => {
    wrapper = mountExtended(AppLink, { propsData: { app } });

    const link = wrapper.find('a');

    expect(link.attributes('target')).toBe('_blank');
    expect(link.attributes('rel')).toBe('noopener noreferrer');
  });
});
