import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import DuoReadinessInheritedList from 'ee/ai/settings/readiness/components/duo_readiness_inherited_list.vue';

const ITEMS = [
  { reference: 'code_review/v1', name: 'Code Review' },
  { reference: 'developer/v1', name: 'Developer' },
];

describe('DuoReadinessInheritedList', () => {
  let wrapper;

  const createComponent = ({ props = {} } = {}) => {
    wrapper = shallowMountExtended(DuoReadinessInheritedList, {
      propsData: { items: ITEMS, ...props },
    });
  };

  const findList = () => wrapper.find('ul');

  it('lists the names of the items the top-level group picked', () => {
    createComponent();

    expect(
      findList()
        .findAll('li')
        .wrappers.map((item) => item.text()),
    ).toEqual(['Code Review', 'Developer']);
    expect(findList().classes()).not.toContain('gl-text-subtle');
  });

  it('mutes the names while the parent row is off', () => {
    createComponent({ props: { disabled: true } });

    expect(findList().classes()).toContain('gl-text-subtle');
  });
});
