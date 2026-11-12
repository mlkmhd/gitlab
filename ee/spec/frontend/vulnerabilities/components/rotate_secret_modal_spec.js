import { GlModal, GlFormGroup, GlFormInput } from '@gitlab/ui';
import { nextTick } from 'vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import RotateSecretModal, {
  CANCEL_ROTATE_LEAKED_TOKEN_MODAL_EVENT,
  CONFIRM_ROTATE_LEAKED_TOKEN_MODAL_EVENT,
} from 'ee/vulnerabilities/components/rotate_secret_modal.vue';

describe('RotateSecretModal', () => {
  let wrapper;

  const createWrapper = (props = {}) => {
    wrapper = shallowMountExtended(RotateSecretModal, {
      propsData: {
        modalId: 'rotate-modal',
        defaultName: 'ROTATED_GITLAB_TOKEN_1',
        leakLocation: '.gitlab-ci.yml:7',
        ...props,
      },
    });
  };

  const findModal = () => wrapper.findComponent(GlModal);
  const findInput = () => wrapper.findComponent(GlFormInput);
  const submit = () => {
    const event = { preventDefault: jest.fn() };
    findModal().vm.$emit('primary', event);
    return event;
  };

  it('prefills the secret name with the default', () => {
    createWrapper();

    expect(findInput().attributes('value')).toBe('ROTATED_GITLAB_TOKEN_1');
  });

  it('lists the three steps of the flow', () => {
    createWrapper();

    expect(wrapper.findByTestId('rotation-steps').findAll('li')).toHaveLength(3);
  });

  it('emits confirm with the trimmed name', () => {
    createWrapper({ defaultName: ' DEPLOY_TOKEN ' });

    const event = submit();

    expect(event.preventDefault).not.toHaveBeenCalled();
    expect(wrapper.emitted('confirm')).toEqual([[{ name: 'DEPLOY_TOKEN' }]]);
  });

  it.each(['has-dash', 'has space', '', 'a'.repeat(256)])(
    'keeps the modal open and does not emit for invalid name %p',
    async (name) => {
      createWrapper({ defaultName: name });

      const event = submit();
      await nextTick();

      expect(event.preventDefault).toHaveBeenCalled();
      expect(wrapper.emitted('confirm')).toBeUndefined();
      expect(findInput().attributes('state')).toBeUndefined();
    },
  );

  it('mentions the length limit in the invalid name feedback', () => {
    createWrapper();

    expect(wrapper.findComponent(GlFormGroup).attributes('invalid-feedback')).toBe(
      "The name must be 255 characters or fewer and can only contain letters, digits, and '_'.",
    );
  });

  it('re-emits visibility changes', () => {
    createWrapper();

    findModal().vm.$emit('change', false);

    expect(wrapper.emitted('change')).toEqual([[false]]);
  });

  describe('tracking', () => {
    const { bindInternalEventDocument } = useMockInternalEventsTracking();

    it('tracks the confirm event and not the cancel event when confirmed', () => {
      createWrapper();
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      submit();
      findModal().vm.$emit('hide', { defaultPrevented: false });

      expect(trackEventSpy).toHaveBeenCalledTimes(1);
      expect(trackEventSpy).toHaveBeenCalledWith(
        CONFIRM_ROTATE_LEAKED_TOKEN_MODAL_EVENT,
        {},
        undefined,
      );
    });

    it('does not track a confirm or cancel event for an invalid name', () => {
      createWrapper({ defaultName: 'has-dash' });
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      submit();
      findModal().vm.$emit('hide', { defaultPrevented: true });

      expect(trackEventSpy).not.toHaveBeenCalled();
    });

    it('tracks the cancel event when closed without confirming', () => {
      createWrapper();
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findModal().vm.$emit('hide', { defaultPrevented: false });

      expect(trackEventSpy).toHaveBeenCalledTimes(1);
      expect(trackEventSpy).toHaveBeenCalledWith(
        CANCEL_ROTATE_LEAKED_TOKEN_MODAL_EVENT,
        {},
        undefined,
      );
    });

    it('does not track visibility changes on their own', () => {
      createWrapper();
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findModal().vm.$emit('change', false);
      findModal().vm.$emit('change', false);

      expect(trackEventSpy).not.toHaveBeenCalled();
    });

    it('tracks the cancel event after a confirmed modal is reopened and closed', () => {
      createWrapper();
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      submit();
      findModal().vm.$emit('show');
      findModal().vm.$emit('hide', { defaultPrevented: false });

      expect(trackEventSpy).toHaveBeenLastCalledWith(
        CANCEL_ROTATE_LEAKED_TOKEN_MODAL_EVENT,
        {},
        undefined,
      );
    });

    it('does not track when the modal opens', () => {
      createWrapper();
      const { trackEventSpy } = bindInternalEventDocument(wrapper.element);

      findModal().vm.$emit('change', true);

      expect(trackEventSpy).not.toHaveBeenCalled();
    });
  });
});
