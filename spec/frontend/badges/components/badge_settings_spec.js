import { GlTable, GlModal } from '@gitlab/ui';
import Vue from 'vue';
import { createTestingPinia } from '@pinia/testing';
import { PiniaVuePlugin } from 'pinia';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import BadgeSettings from '~/badges/components/badge_settings.vue';
import BadgeList from '~/badges/components/badge_list.vue';
import BadgeForm from '~/badges/components/badge_form.vue';
import { useBadgeSettings } from '~/badges/store';
import { INITIAL_PAGE } from '~/badges/constants';
import { createDummyBadge } from '../dummy_badge';
import { MOCK_PAGINATION } from '../mock_data';

Vue.use(PiniaVuePlugin);

describe('BadgeSettings component', () => {
  let wrapper;
  let pinia;
  let store;
  const badge = createDummyBadge();

  const createComponent = (isEditing = false) => {
    pinia = createTestingPinia();
    // store is created before the component is rendered
    store = useBadgeSettings();
    store.$patch({
      badges: [badge],
      pagination: MOCK_PAGINATION,
      kind: 'project',
      isEditing,
    });
    store.deleteBadge.mockResolvedValue();

    wrapper = shallowMountExtended(BadgeSettings, {
      pinia,
      stubs: {
        CrudComponent,
        GlTable,
        'badge-list': BadgeList,
        'badge-form': BadgeForm,
      },
    });
  };

  beforeEach(() => {
    createComponent();
  });

  const findModal = () => wrapper.findComponent(GlModal);

  it('calls loadBadges when the component is created', () => {
    createComponent();

    expect(store.loadBadges).toHaveBeenCalledWith({
      page: INITIAL_PAGE,
    });
  });

  it('renders a header with the badge count', () => {
    createComponent();
    const cardTitle = wrapper.findByTestId('crud-title');
    const cardCount = wrapper.findByTestId('crud-count');

    expect(cardTitle.text()).toContain('Your badges');
    expect(cardCount.text()).toContain(MOCK_PAGINATION.total.toString());
  });

  it('displays a table', () => {
    expect(wrapper.findComponent(GlTable).isVisible()).toBe(true);
  });

  it('renders badge add form', () => {
    expect(wrapper.findComponent(BadgeForm).exists()).toBe(true);
  });

  it('renders badge list', () => {
    expect(wrapper.findComponent(BadgeList).isVisible()).toBe(true);
  });

  describe('when editing', () => {
    beforeEach(() => {
      createComponent(true);
    });

    it('sets `GlModal` `visible` prop to `true`', () => {
      expect(wrapper.findComponent(GlModal).props('visible')).toBe(true);
    });

    it('renders `BadgeForm` in modal', () => {
      expect(findModal().findComponent(BadgeForm).props('isEditing')).toBe(true);
    });

    describe('when modal primary event is fired', () => {
      it('emits submit event on form', () => {
        const dispatchEventSpy = jest.spyOn(
          findModal().findComponent(BadgeForm).element,
          'dispatchEvent',
        );
        findModal().vm.$emit('primary', { preventDefault: jest.fn() });

        expect(dispatchEventSpy).toHaveBeenCalledWith(
          new CustomEvent('submit', { cancelable: true }),
        );
      });
    });
  });
});
