import { injectVueAppBreadcrumbs } from '~/lib/utils/breadcrumbs';
import { initSinglePageApplication } from '~/vue_shared/spa';
import AiCatalogBreadcrumbs from 'ee/ai/catalog/router/ai_catalog_breadcrumbs.vue';
import { initDuoAgentsPlatformPage } from 'ee/ai/duo_agents_platform/index';
import { createRouter } from 'ee/ai/duo_agents_platform/router';
import {
  AGENT_PLATFORM_PROJECT_PAGE,
  AGENT_PLATFORM_GROUP_PAGE,
} from 'ee/ai/duo_agents_platform/constants';
import { setHTMLFixture, resetHTMLFixture } from 'helpers/fixtures';

jest.mock('~/vue_shared/spa');
jest.mock('~/lib/utils/breadcrumbs');
jest.mock('ee/ai/duo_agents_platform/init_verification_alert');
jest.mock('ee/ai/duo_agents_platform/router', () => ({ createRouter: jest.fn() }));

const SELECTOR = 'js-duo-agents-platform-page';
const BASE_ROUTE = '/base-route';

describe('initDuoAgentsPlatformPage', () => {
  const mockRouter = { name: 'mockRouter' };

  beforeEach(() => {
    createRouter.mockReturnValue(mockRouter);
    setHTMLFixture(`<div id="${SELECTOR}" data-agents-platform-base-route="${BASE_ROUTE}"></div>`);
  });

  afterEach(() => {
    resetHTMLFixture();
  });

  it.each([AGENT_PLATFORM_PROJECT_PAGE, AGENT_PLATFORM_GROUP_PAGE])(
    'injects breadcrumbs with the full namespace path and no AI Catalog crumb for %s',
    (namespace) => {
      initDuoAgentsPlatformPage({ namespace });

      expect(injectVueAppBreadcrumbs).toHaveBeenCalledWith(mockRouter, AiCatalogBreadcrumbs, null, {
        includeNamespaceBreadcrumbs: true,
        showCatalogRootCrumb: false,
      });
    },
  );

  describe('duoSettings', () => {
    it('assembles duoBetaFeaturesEnabled and duoScheduledTriggersEnabled as booleans', () => {
      setHTMLFixture(`
        <div
          id="${SELECTOR}"
          data-agents-platform-base-route="${BASE_ROUTE}"
          data-duo-beta-features-enabled="false"
          data-duo-scheduled-triggers-enabled="true"
        ></div>
      `);

      initDuoAgentsPlatformPage({ namespace: AGENT_PLATFORM_PROJECT_PAGE });

      expect(initSinglePageApplication).toHaveBeenCalledWith(
        expect.objectContaining({
          provide: expect.objectContaining({
            duoSettings: expect.objectContaining({
              duoBetaFeaturesEnabled: false,
              duoScheduledTriggersEnabled: true,
            }),
          }),
        }),
      );
    });
  });
});
