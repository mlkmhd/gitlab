import { GlEmptyState } from '@gitlab/ui';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ReleasesEmptyState from '~/releases/components/releases_empty_state.vue';

describe('releases_empty_state.vue', () => {
  const documentationPath = 'path/to/releases/documentation';
  const newReleasePath = 'path/to/releases/new-release';
  const illustrationPath = 'path/to/releases/empty/state/illustration';

  let wrapper;

  const createComponent = ({ canCreateRelease = true } = {}) => {
    wrapper = shallowMountExtended(ReleasesEmptyState, {
      provide: {
        documentationPath,
        illustrationPath,
        ...(canCreateRelease ? { newReleasePath } : {}),
      },
    });
  };

  const findEmptyState = () => wrapper.findComponent(GlEmptyState);

  it('renders a GlEmptyState and provides it with the correct props', () => {
    createComponent();

    expect(findEmptyState().props()).toMatchObject({
      title: 'Getting started with releases',
      svgPath: illustrationPath,
      description:
        "Releases are based on Git tags and mark specific points in a project's development history. They can contain information about the type of changes and can also deliver binaries, like compiled versions of your software.",
      primaryButtonLink: newReleasePath,
      primaryButtonText: 'Create a new release',
      secondaryButtonLink: documentationPath,
      secondaryButtonText: 'Learn more about releases',
    });
  });

  describe('when the user cannot create a release', () => {
    beforeEach(() => {
      createComponent({ canCreateRelease: false });
    });

    it('passes no primary button link, so GlEmptyState hides the button', () => {
      expect(findEmptyState().props('primaryButtonLink')).toBe(null);
    });
  });
});
