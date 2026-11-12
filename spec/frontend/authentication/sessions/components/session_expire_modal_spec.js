import { GlModal } from '@gitlab/ui';
import { shallowMount } from '@vue/test-utils';
import { nextTick } from 'vue';
import waitForPromises from 'helpers/wait_for_promises';
import SessionExpireModal from '~/authentication/sessions/components/session_expire_modal.vue';
import {
  BROADCAST_CHANNEL_SESSION_EXPIRE_MODAL_SHOWN,
  BROADCAST_CHANNEL_SESSION_EXPIRY,
  INTERVAL_SESSION_MODAL,
  KEEP_ALIVE_LEAD,
  SESSION_EXPIRES_AT_HEADER,
} from '~/authentication/sessions/constants';
import { broadcastSessionExpiry } from '~/authentication/sessions/session_expiry';
import { refreshCurrentPage, visitUrl } from '~/lib/utils/url_utility';

jest.useFakeTimers();
jest.mock('~/lib/utils/url_utility', () => ({
  ...jest.requireActual('~/lib/utils/url_utility'),
  refreshCurrentPage: jest.fn(),
  visitUrl: jest.fn(),
}));
jest.mock('~/authentication/sessions/session_expiry');

describe('SessionExpireModal', () => {
  const message = 'Modal message';
  const sessionTimeout = 0;
  const signInUrl = 'http://gitlab.example.com/users/sign_in?redirect_to_referer=yes';
  const title = 'Modal title';
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMount(SessionExpireModal, {
      propsData: {
        broadcastChannel: BROADCAST_CHANNEL_SESSION_EXPIRY,
        message,
        sessionTimeout,
        signInUrl,
        title,
        ...props,
      },
    });
  };

  const findModal = () => wrapper.findComponent(GlModal);

  it('initially, it does not show the modal', () => {
    createComponent({ sessionTimeout: Date.now() + 1 });

    expect(findModal().props()).toMatchObject({
      visible: false,
      title,
      actionPrimary: {
        text: 'Sign in',
      },
      actionCancel: {
        text: 'Cancel',
      },
    });
    expect(findModal().attributes()).toMatchObject({
      'aria-live': 'assertive',
    });
  });

  describe('when there is an expiring session', () => {
    it('shows the modal triggered by time elapsed', async () => {
      jest.spyOn(global, 'setInterval');
      jest.spyOn(global, 'clearInterval');
      createComponent();

      expect(setInterval).toHaveBeenCalledTimes(1);
      expect(setInterval).toHaveBeenCalledWith(expect.any(Function), INTERVAL_SESSION_MODAL);

      jest.advanceTimersByTime(INTERVAL_SESSION_MODAL);
      await nextTick();

      expect(findModal().props('visible')).toBe(true);
      expect(clearInterval).toHaveBeenCalledTimes(1);
      expect(clearInterval).toHaveBeenCalledWith(expect.any(Number));
    });

    it('shows the modal triggered by changevisibility event', async () => {
      jest.spyOn(document, 'addEventListener');
      jest.spyOn(document, 'removeEventListener');
      createComponent();

      nextTick();
      expect(document.addEventListener).toHaveBeenCalledTimes(1);
      expect(document.addEventListener).toHaveBeenCalledWith(
        'visibilitychange',
        expect.any(Function),
      );

      document.dispatchEvent(new Event('visibilitychange'));
      await nextTick();

      expect(findModal().props('visible')).toBe(true);
      expect(document.removeEventListener).toHaveBeenCalledTimes(1);
      expect(document.removeEventListener).toHaveBeenCalledWith(
        'visibilitychange',
        expect.any(Function),
      );
    });

    describe('when a broadcast message is emitted', () => {
      let broadcastChannel;

      beforeEach(() => {
        broadcastChannel = new BroadcastChannel(BROADCAST_CHANNEL_SESSION_EXPIRY);
        return waitForPromises();
      });
      afterEach(() => {
        broadcastChannel.close();
      });

      it('hides the modal triggered by a broadcast message event', async () => {
        createComponent();
        jest.advanceTimersByTime(INTERVAL_SESSION_MODAL);
        await nextTick();
        expect(findModal().props('visible')).toBe(true);

        broadcastChannel.postMessage(Date.now() + 1000);
        await waitForPromises();

        expect(findModal().props('visible')).toBe(false);
      });

      it('ignores a non-numeric broadcast so future message types leave the countdown untouched', async () => {
        createComponent();
        jest.advanceTimersByTime(INTERVAL_SESSION_MODAL);
        await nextTick();
        expect(findModal().props('visible')).toBe(true);

        // A future, non-deadline message shape must be ignored (unlike the numeric
        // deadline above, which re-arms and hides the modal).
        broadcastChannel.postMessage({ type: 'signed_out' });
        await waitForPromises();

        expect(findModal().props('visible')).toBe(true);
      });
    });

    it('shows the correct modal content', async () => {
      createComponent();
      await nextTick();

      expect(findModal().text()).toBe(message);
    });

    it('navigates to the singInUrl', () => {
      createComponent();
      expect(findModal().props('actionPrimary')).toMatchObject({ text: 'Sign in' });

      findModal().vm.$emit('primary');
      expect(visitUrl).toHaveBeenCalledWith(signInUrl);
    });

    describe('when no signInUrl prop', () => {
      it('triggers a refresh of the current page', () => {
        createComponent({ signInUrl: null });
        expect(findModal().props('actionPrimary')).toMatchObject({ text: 'Reload page' });

        findModal().vm.$emit('primary');
        expect(refreshCurrentPage).toHaveBeenCalledTimes(1);
      });
    });
  });

  describe('announceShown', () => {
    let shownChannel;
    let onShown;

    beforeEach(() => {
      onShown = jest.fn();
      shownChannel = new BroadcastChannel(BROADCAST_CHANNEL_SESSION_EXPIRE_MODAL_SHOWN);
      shownChannel.addEventListener('message', onShown);
      return waitForPromises();
    });
    afterEach(() => {
      shownChannel.removeEventListener('message', onShown);
      shownChannel.close();
    });

    it('announces on the shown channel when the modal displays', async () => {
      createComponent({ announceShown: true });
      await waitForPromises();

      expect(findModal().props('visible')).toBe(true);
      expect(onShown).toHaveBeenCalledTimes(1);
      expect(onShown.mock.calls[0][0].data).toBe(true);
    });

    it('announces false when a later deadline hides the modal, so subordinates can resume', async () => {
      const broadcastChannel = new BroadcastChannel(BROADCAST_CHANNEL_SESSION_EXPIRY);
      createComponent({ announceShown: true });
      await waitForPromises();
      expect(findModal().props('visible')).toBe(true);

      broadcastChannel.postMessage(Date.now() + 100000);
      // Two BroadcastChannel hops: the deadline reaches reset (hides the modal), which then
      // posts on the shown channel; flush both before asserting the shown-channel receipt.
      await waitForPromises();
      await waitForPromises();

      expect(findModal().props('visible')).toBe(false);
      expect(onShown).toHaveBeenCalledTimes(2);
      expect(onShown.mock.calls[1][0].data).toBe(false);

      broadcastChannel.close();
    });

    it('does not announce when announceShown is not set', async () => {
      createComponent();
      await waitForPromises();

      expect(findModal().props('visible')).toBe(true);
      expect(onShown).not.toHaveBeenCalled();
    });
  });

  describe('keeping a remembered session alive', () => {
    // Legacy fake timers do not move Date.now(), so the clock is advanced by hand.
    let now;
    const sessionDeadline = 10 * 60 * 1000;
    const newDeadlineSeconds = '1800000000';

    const advance = async (ms) => {
      now += ms;
      jest.advanceTimersByTime(ms);
      await waitForPromises();
    };
    const advanceToKeepAliveWindow = () => advance(sessionDeadline - KEEP_ALIVE_LEAD);

    beforeEach(() => {
      now = 0;
      jest.spyOn(Date, 'now').mockImplementation(() => now);
      window.gon = { api_version: 'v4' };
      global.fetch = jest.fn().mockResolvedValue({
        headers: {
          get: (name) => (name === SESSION_EXPIRES_AT_HEADER ? newDeadlineSeconds : null),
        },
      });
    });

    afterEach(() => {
      window.gon = {};
      delete global.fetch;
    });

    it('sends one request inside the window and rebroadcasts its deadline', async () => {
      createComponent({
        sessionTimeout: sessionDeadline,
        rememberMeExpiresAt: sessionDeadline + 1,
      });

      await advance(sessionDeadline - KEEP_ALIVE_LEAD - INTERVAL_SESSION_MODAL);
      expect(global.fetch).not.toHaveBeenCalled();

      await advance(INTERVAL_SESSION_MODAL);
      await advance(INTERVAL_SESSION_MODAL * 5);

      expect(global.fetch).toHaveBeenCalledTimes(1);
      expect(global.fetch).toHaveBeenCalledWith('/api/v4/version', { cache: 'no-store' });
      expect(broadcastSessionExpiry).toHaveBeenCalledWith(newDeadlineSeconds);
    });

    it('does not send a request when the cookie expires before the session', async () => {
      createComponent({
        sessionTimeout: sessionDeadline,
        rememberMeExpiresAt: sessionDeadline - 1,
      });

      await advanceToKeepAliveWindow();

      expect(global.fetch).not.toHaveBeenCalled();
    });

    it('does not send a request without a remember me cookie', async () => {
      createComponent({ sessionTimeout: sessionDeadline });

      await advanceToKeepAliveWindow();

      expect(global.fetch).not.toHaveBeenCalled();
    });

    it('shows the modal instead when the deadline has already passed', async () => {
      now = sessionDeadline + 1;
      createComponent({
        sessionTimeout: sessionDeadline,
        rememberMeExpiresAt: sessionDeadline * 2,
      });
      await waitForPromises();

      expect(global.fetch).not.toHaveBeenCalled();
      expect(findModal().props('visible')).toBe(true);
    });

    it('does not send another request while one is in flight', async () => {
      global.fetch.mockReturnValue(new Promise(() => {}));
      createComponent({
        sessionTimeout: sessionDeadline,
        rememberMeExpiresAt: sessionDeadline + 1,
      });

      await advanceToKeepAliveWindow();
      await advance(INTERVAL_SESSION_MODAL);
      await advance(INTERVAL_SESSION_MODAL);

      expect(global.fetch).toHaveBeenCalledTimes(1);
    });

    it('retries on the next check after a failed request', async () => {
      global.fetch.mockRejectedValueOnce(new Error('offline'));
      createComponent({
        sessionTimeout: sessionDeadline,
        rememberMeExpiresAt: sessionDeadline + 1,
      });

      await advanceToKeepAliveWindow();
      expect(global.fetch).toHaveBeenCalledTimes(1);
      expect(broadcastSessionExpiry).not.toHaveBeenCalled();

      await advance(INTERVAL_SESSION_MODAL);

      expect(global.fetch).toHaveBeenCalledTimes(2);
      expect(broadcastSessionExpiry).toHaveBeenCalledWith(newDeadlineSeconds);
    });

    it('still shows the modal at the deadline when every request fails', async () => {
      global.fetch.mockRejectedValue(new Error('offline'));
      createComponent({
        sessionTimeout: sessionDeadline,
        rememberMeExpiresAt: sessionDeadline + 1,
      });

      await advanceToKeepAliveWindow();
      await advance(INTERVAL_SESSION_MODAL);
      await advance(KEEP_ALIVE_LEAD);

      expect(broadcastSessionExpiry).not.toHaveBeenCalled();
      expect(findModal().props('visible')).toBe(true);
    });
  });
});
