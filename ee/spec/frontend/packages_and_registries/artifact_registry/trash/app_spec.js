import { shallowMount } from '@vue/test-utils';
import PageHeading from '~/vue_shared/components/page_heading.vue';
import App from 'ee/packages_and_registries/artifact_registry/trash/app.vue';

describe('ArtifactRegistryTrashApp', () => {
  let wrapper;

  const findPageHeading = () => wrapper.findComponent(PageHeading);

  beforeEach(() => {
    wrapper = shallowMount(App);
  });

  it('renders the Trash heading', () => {
    expect(findPageHeading().props('heading')).toBe('Trash');
  });
});
