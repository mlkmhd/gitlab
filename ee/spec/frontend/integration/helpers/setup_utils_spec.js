import { fullMount } from 'ee_jest/integration/helpers/test_helpers';
import { setFeatureFlags, setLicensedFeatures } from './setup_utils';

// The child sits one level down so it reads the injects the plugins provide on its
// parent, as components deep in a real app do, rather than the root's own `provide`.
const Child = {
  inject: ['glFeatures', 'glLicensedFeatures', 'glAbilities'],
  render(h) {
    return h('div', {
      attrs: {
        'data-testid': 'child',
        'data-features': JSON.stringify(this.glFeatures),
        'data-licensed-features': JSON.stringify(this.glLicensedFeatures),
        'data-abilities': JSON.stringify(this.glAbilities),
        'data-translated': this.__('Save'),
      },
    });
  },
};

const Parent = {
  render(h) {
    return h('div', [h(Child)]);
  },
};

// `test_setup.js` sets these before every test, as lib/gitlab/gon_helper.rb does.
const ALWAYS_ON_FLAGS = { workItemFeaturesField: true };

const findChild = () => document.querySelector('[data-testid="child"]');
const readAttribute = (name) => JSON.parse(findChild().getAttribute(name));

describe('integration harness Vue plugins', () => {
  describe('when feature flags are set with setFeatureFlags', () => {
    beforeEach(() => {
      setFeatureFlags({ firstFlag: true });
      setFeatureFlags({ secondFlag: false });
      fullMount(Parent);
    });

    it('provides the merged flags to nested components through glFeatures', () => {
      expect(readAttribute('data-features')).toEqual({
        ...ALWAYS_ON_FLAGS,
        firstFlag: true,
        secondFlag: false,
      });
    });
  });

  describe('when gon carries licensed features and abilities', () => {
    beforeEach(() => {
      setLicensedFeatures({ epics: true });
      window.gon.abilities = { canEdit: true };
      fullMount(Parent);
    });

    it('provides them through glLicensedFeatures', () => {
      expect(readAttribute('data-licensed-features')).toEqual({ epics: true });
    });

    it('provides them through glAbilities', () => {
      expect(readAttribute('data-abilities')).toEqual({ canEdit: true });
    });
  });

  describe('when no flags are set', () => {
    beforeEach(() => {
      fullMount(Parent);
    });

    it('provides only the always-on flags through glFeatures', () => {
      expect(readAttribute('data-features')).toEqual(ALWAYS_ON_FLAGS);
    });

    it('installs the Translate mixin on every component', () => {
      expect(findChild().dataset.translated).toBe('Save');
    });
  });
});
