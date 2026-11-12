import Vue from 'vue';
import { createTestingPinia } from '@pinia/testing';
import { PiniaVuePlugin } from 'pinia';
import { GlFormFields, GlLoadingIcon } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import BadgeForm from '~/badges/components/badge_form.vue';
import Badge from '~/badges/components/badge.vue';
import { useBadgeSettings } from '~/badges/store';
import { createAlert } from '~/alert';

jest.mock('~/alert');

Vue.use(PiniaVuePlugin);

describe('BadgeForm', () => {
  let wrapper;
  let pinia;
  let store;

  const defaultPropsData = {
    isEditing: false,
  };

  const createComponent = ({ propsData = {}, state = {} } = {}) => {
    store.$patch(state);

    wrapper = mountExtended(BadgeForm, {
      pinia,
      attachTo: document.body,
      propsData: {
        ...defaultPropsData,
        ...propsData,
      },
    });
  };

  beforeEach(() => {
    // The form fields are bound to the store state through `updateBadgeInForm`,
    // so it keeps its real implementation while the actions that hit the API are mocked.
    pinia = createTestingPinia({ stubActions: false });
    store = useBadgeSettings();
    jest.spyOn(store, 'renderBadge').mockResolvedValue();
    jest.spyOn(store, 'saveBadge').mockResolvedValue({});
    jest.spyOn(store, 'addBadge').mockResolvedValue({});
  });

  const findNameField = () => wrapper.findByLabelText('Name');
  const findLinkField = () => wrapper.findByLabelText('Link', { exact: false });
  const findBadgeImageUrlField = () => wrapper.findByLabelText('Badge image URL', { exact: false });
  const findSubmitButton = () => wrapper.findByRole('button', { name: 'Add badge' });
  const findCancelButton = () => wrapper.findByRole('button', { name: 'Cancel' });
  const fillFieldsWithValidValues = async () => {
    await findNameField().setValue('foo');
    await findLinkField().setValue('https://foo.bar');
    await findBadgeImageUrlField().setValue('https://foo.bar');
  };

  const submitForm = async () => {
    await findSubmitButton().trigger('click');
  };

  const submitFormWithEmit = () => wrapper.findComponent(GlFormFields).vm.$emit('submit');

  it('renders `Name` field', () => {
    createComponent();

    expect(findNameField().exists()).toBe(true);
  });

  it('renders `Link` field', () => {
    createComponent();

    expect(findLinkField().exists()).toBe(true);
  });

  it('renders `Badge image URL` field', () => {
    createComponent();

    expect(findBadgeImageUrlField().exists()).toBe(true);
  });

  it('shows error if `Name` field is empty', async () => {
    createComponent();

    await submitForm();

    expect(wrapper.findByText('Badge name is required.').exists()).toBe(true);
  });

  it('shows error if `Link` field is empty', async () => {
    createComponent();

    await submitForm();

    expect(wrapper.findByText('Badge link is required.').exists()).toBe(true);
  });

  it('shows error if `Badge image URL` field is empty', async () => {
    createComponent();

    await submitForm();

    expect(wrapper.findByText('Badge image URL is required.').exists()).toBe(true);
  });

  it('shows error if `Link` field is invalid', async () => {
    createComponent();

    await findLinkField().setValue('foo');
    await submitForm();

    expect(wrapper.findByText('Badge link is invalid.').exists()).toBe(true);
  });

  it('shows error if `Badge image URL` field is invalid', async () => {
    createComponent();

    await findBadgeImageUrlField().setValue('foo');
    await submitForm();

    expect(wrapper.findByText('Badge image URL is invalid.').exists()).toBe(true);
  });

  describe('when `Link` field is changed', () => {
    beforeEach(async () => {
      createComponent();
      await findLinkField().setValue('https://foo.bar');
    });

    it('calls `renderBadge` action', () => {
      expect(store.renderBadge).toHaveBeenCalled();
    });
  });

  describe('when `Badge image URL` field is changed', () => {
    beforeEach(async () => {
      createComponent();
      await findBadgeImageUrlField().setValue('https://foo.bar');
    });

    it('calls `renderBadge` action', () => {
      expect(store.renderBadge).toHaveBeenCalled();
    });
  });

  describe('when `isEditing` prop is `false`', () => {
    it('renders `Add badge` and `Cancel` button', () => {
      createComponent();

      expect(findSubmitButton().exists()).toBe(true);
      expect(findCancelButton().exists()).toBe(true);
    });

    describe('when form is submitted', () => {
      it('calls `addBadge` action', async () => {
        createComponent();
        await fillFieldsWithValidValues();
        await submitForm();

        expect(store.addBadge).toHaveBeenCalled();
      });

      describe('when `addBadge` action promise is rejected', () => {
        beforeEach(async () => {
          createComponent();
          store.addBadge.mockRejectedValue();
          await fillFieldsWithValidValues();
          await submitForm();
        });

        it('calls `createAlert`', () => {
          expect(createAlert).toHaveBeenCalledWith({
            message: 'Failed to add new badge. Check the URLs, then try again.',
          });
        });
      });
    });
  });

  describe('when `isEditing` prop is `true`', () => {
    const propsData = { isEditing: true };

    it('does not render buttons', () => {
      createComponent({ propsData });

      expect(findSubmitButton().exists()).toBe(false);
      expect(findCancelButton().exists()).toBe(false);
    });

    describe('when form is submitted', () => {
      it('calls `saveBadge` action', async () => {
        createComponent({ propsData });
        await fillFieldsWithValidValues();
        // Submit form like this because submit button is not rendered when editing
        // This is because form is in a modal so we use the modal buttons to submit the form
        submitFormWithEmit();

        expect(store.saveBadge).toHaveBeenCalled();
      });

      describe('when `saveBadge` action promise is rejected', () => {
        beforeEach(async () => {
          createComponent({ propsData });
          store.saveBadge.mockRejectedValue();
          await fillFieldsWithValidValues();
          // Submit form like this because submit button is not rendered when editing
          // This is because form is in a modal so we use the modal buttons to submit the form
          submitFormWithEmit();
        });

        it('calls `createAlert`', () => {
          expect(createAlert).toHaveBeenCalledWith({
            message: 'Saving the badge failed, please check the entered URLs and try again.',
          });
        });
      });
    });
  });

  describe('when `Cancel` button is clicked', () => {
    beforeEach(async () => {
      createComponent();
      await fillFieldsWithValidValues();
      await findCancelButton().trigger('click');
    });

    it('clears field values', () => {
      expect(findNameField().element.value).toBe('');
      expect(findLinkField().element.value).toBe('');
      expect(findBadgeImageUrlField().element.value).toBe('');
    });

    it('emits `close-add-form` event', () => {
      expect(wrapper.emitted('close-add-form')).toEqual([[]]);
    });
  });

  describe('when there is no image to preview', () => {
    beforeEach(() => {
      createComponent();
    });

    it('displays no preview message', () => {
      expect(wrapper.findByText('No image to preview').exists()).toBe(true);
    });
  });

  describe('when badge is rendering', () => {
    beforeEach(() => {
      createComponent({ state: { isRendering: true } });
    });

    it('shows loading icon', () => {
      expect(wrapper.findComponent(GlLoadingIcon).exists()).toBe(true);
    });
  });

  describe('when badge has rendered', () => {
    const renderedBadge = {
      imageUrl: 'https://example.gitlab.com/%{project_path}',
      linkUrl: 'https://example.gitlab.com/%{project_path}',
      name: null,
      renderedImageUrl: 'https://example.gitlab.com/root/personal',
      renderedLinkUrl: 'https://example.gitlab.com/root/personal',
      isDeleting: false,
    };

    beforeEach(() => {
      createComponent({
        state: { renderedBadge },
      });
    });

    it('shows badge preview', () => {
      expect(wrapper.findComponent(Badge).props()).toMatchObject({
        imageUrl: renderedBadge.renderedImageUrl,
        linkUrl: renderedBadge.renderedLinkUrl,
      });
    });
  });
});
