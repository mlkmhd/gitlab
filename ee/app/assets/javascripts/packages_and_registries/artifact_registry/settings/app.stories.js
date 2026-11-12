import createMockApollo from 'helpers/mock_apollo_helper';
import {
  CLIENT_BASE_URL,
  ORGANIZATION_GID,
  mockArtifactRegistry,
  mockArtifactRegistryResponse,
} from 'ee_jest/packages_and_registries/artifact_registry/mock_data';
import getArtifactRegistryQuery from '../graphql/queries/get_artifact_registry.query.graphql';
import App from './app.vue';
// The page loads this bundle; it spaces and divides the settings blocks.
import '../../../../../../../app/assets/stylesheets/page_bundles/settings.scss';

export default {
  component: App,
  title: 'ee/packages_and_registries/artifact_registry/settings/app',
};

const Template = (registryHandler) => () => ({
  components: { App },
  apolloProvider: createMockApollo([[getArtifactRegistryQuery, registryHandler]]),
  provide: {
    organizationGid: ORGANIZATION_GID,
    organizationId: '1',
    clientBaseUrl: CLIENT_BASE_URL,
  },
  template: '<app />',
});

export const Default = Template(() =>
  Promise.resolve(mockArtifactRegistryResponse(mockArtifactRegistry())),
);
