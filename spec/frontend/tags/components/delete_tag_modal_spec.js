import { GlModal, GlFormGroup, GlFormInput } from '@gitlab/ui';
import { mount } from '@vue/test-utils';
import { stubComponent } from 'helpers/stub_component';
import { extendedWrapper } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import DeleteTagModal from '~/tags/components/delete_tag_modal.vue';
import eventHub from '~/tags/event_hub';

let wrapper;

const tagName = 'test-tag';
const path = '/path/to/tag';
const isProtected = false;
const modalHideSpy = jest.fn();
const modalShowSpy = jest.fn();
const formSubmitSpy = jest.spyOn(HTMLFormElement.prototype, 'submit').mockImplementation();

const createComponent = (data = {}) => {
  wrapper = extendedWrapper(
    mount(DeleteTagModal, {
      data() {
        return {
          tagName,
          path,
          isProtected,
          ...data,
        };
      },
      stubs: {
        GlModal: stubComponent(GlModal, {
          template:
            '<div><slot name="modal-title"></slot><slot></slot><slot name="modal-footer"></slot></div>',
          methods: {
            hide: modalHideSpy,
            show: modalShowSpy,
          },
        }),
      },
    }),
  );
};

const findModal = () => wrapper.findComponent(GlModal);
const findModalMessage = () => wrapper.findByTestId('modal-message');
const findDeleteButton = () => wrapper.findComponentByTestId('delete-tag-confirmation-button');
const findCancelButton = () => wrapper.findComponentByTestId('delete-tag-cancel-button');
const findFormGroup = () => wrapper.findComponent(GlFormGroup);
const findFormInput = () => wrapper.findComponent(GlFormInput);
const findForm = () => wrapper.find('form');

describe('Delete tag modal', () => {
  describe('Deleting a regular tag', () => {
    const expectedMessage =
      "You're about to permanently delete the tag test-tag. This cannot be undone.";

    beforeEach(() => {
      createComponent();
    });

    it('renders the modal correctly', () => {
      expect(findModal().props('title')).toBe('Delete tag?');
      expect(findModalMessage().text()).toMatchInterpolatedText(expectedMessage);
      expect(findCancelButton().text()).toBe('Cancel');
      expect(findDeleteButton().text()).toBe('Delete tag');
      expect(findForm().attributes('action')).toBe(path);
    });

    it('does not render the tag name confirmation input', () => {
      expect(findFormGroup().exists()).toBe(false);
    });

    it('submits the form when the delete button is clicked', () => {
      findDeleteButton().vm.$emit('click');

      expect(findForm().attributes('action')).toBe(path);
      expect(formSubmitSpy).toHaveBeenCalledTimes(1);
    });

    it('calls show on the modal when a `openModal` event is received through the event hub', () => {
      eventHub.$emit('openModal', {
        isProtected,
        tagName,
        path,
      });

      expect(modalShowSpy).toHaveBeenCalled();
    });

    it('calls hide on the modal when cancel button is clicked', () => {
      findCancelButton().vm.$emit('click');

      expect(modalHideSpy).toHaveBeenCalled();
    });
  });

  describe('Deleting a protected tag (for owner or maintainer)', () => {
    const expectedMessage =
      "You're about to permanently delete the protected tag test-tag. This cannot be undone.";
    const expectedConfirmationText = 'Enter the following to confirm: test-tag';

    beforeEach(() => {
      createComponent({ isProtected: true });
    });

    describe('rendering the modal correctly for a protected tag', () => {
      it('sets the modal title for a protected tag', () => {
        expect(findModal().props('title')).toBe('Delete protected tag?');
      });

      it('renders the correct text in the modal message', () => {
        expect(findModalMessage().text()).toMatchInterpolatedText(expectedMessage);
      });

      it('renders the protected tag name confirmation form with expected text and action', () => {
        expect(findForm().text()).toMatchInterpolatedText(expectedConfirmationText);
        const input = wrapper.findByLabelText('Enter the following to confirm: test-tag');
        expect(input.exists()).toBe(true);
        expect(findForm().attributes('action')).toBe(path);
      });

      it('renders the buttons with the correct button text', () => {
        expect(findCancelButton().text()).toBe('Cancel');
        expect(findDeleteButton().text()).toBe('Delete protected tag');
      });
    });

    it('opens with the delete button disabled and enables it when tag name is confirmed', async () => {
      expect(findDeleteButton().props('disabled')).toBe(true);

      findFormInput().vm.$emit('input', tagName);

      await waitForPromises();

      expect(findDeleteButton().props('disabled')).not.toBe(true);
    });

    it('clears the entered tag name when the modal is opened again', async () => {
      findFormInput().vm.$emit('input', tagName);
      await waitForPromises();
      expect(findDeleteButton().props('disabled')).not.toBe(true);

      eventHub.$emit('openModal', { isProtected: true, tagName, path });
      await waitForPromises();

      expect(findDeleteButton().props('disabled')).toBe(true);
    });
  });
});
