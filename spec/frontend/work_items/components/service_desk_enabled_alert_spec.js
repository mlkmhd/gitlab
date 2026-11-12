import { GlAlert, GlSprintf } from '@gitlab/ui';
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import * as Sentry from '~/sentry/sentry_browser_wrapper';
import HelpPageLink from '~/vue_shared/components/help_page_link/help_page_link.vue';
import ServiceDeskEnabledAlert from '~/work_items/components/service_desk_enabled_alert.vue';
import serviceDeskEnabledQuery from '~/work_items/graphql/service_desk_enabled.query.graphql';

jest.mock('~/sentry/sentry_browser_wrapper');

Vue.use(VueApollo);

describe('ServiceDeskEnabledAlert', () => {
  let wrapper;

  const fullPath = 'group/project';

  const serviceDeskEnabledHandler = (serviceDeskEnabled) =>
    jest.fn().mockResolvedValue({
      data: {
        project: {
          id: 'gid://gitlab/Project/1',
          serviceDeskEnabled,
          __typename: 'Project',
        },
      },
    });

  const findAlert = () => wrapper.findComponent(GlAlert);
  const findHelpPageLink = () => wrapper.findComponent(HelpPageLink);

  const createComponent = ({ handler = serviceDeskEnabledHandler(true) } = {}) => {
    wrapper = shallowMountExtended(ServiceDeskEnabledAlert, {
      apolloProvider: createMockApollo([[serviceDeskEnabledQuery, handler]]),
      propsData: {
        fullPath,
      },
      stubs: {
        GlSprintf,
      },
    });
  };

  it('does not render an alert when service desk is enabled', async () => {
    createComponent({ handler: serviceDeskEnabledHandler(true) });
    await waitForPromises();

    expect(findAlert().exists()).toBe(false);
  });

  it('renders a warning alert when service desk is disabled', async () => {
    createComponent({ handler: serviceDeskEnabledHandler(false) });
    await waitForPromises();

    expect(findAlert().props('variant')).toBe('warning');
    expect(findAlert().text()).toMatchInterpolatedText(
      'This project does not have Service Desk enabled, so the user who created the issue will no longer receive email notifications about new activity.',
    );
    expect(findHelpPageLink().props('href')).toBe('user/project/service_desk/_index.md');
  });

  it('reports error to Sentry when query fails', async () => {
    const error = new Error('Error');
    createComponent({ handler: jest.fn().mockRejectedValue(error) });
    await waitForPromises();

    expect(Sentry.captureException).toHaveBeenCalledWith(error);
  });
});
