import { ApolloLink, execute, Observable } from '@apollo/client/core';
// eslint-disable-next-line no-restricted-imports
import realAxios from 'axios';
import MockAdapter from 'axios-mock-adapter';
import waitForPromises from 'helpers/wait_for_promises';
import { apolloSessionExpiryLink } from '~/authentication/sessions/apollo_session_expiry_link';
import {
  BROADCAST_CHANNEL_SESSION_EXPIRY,
  SESSION_EXPIRES_AT_HEADER,
} from '~/authentication/sessions/constants';
import {
  broadcastSessionExpiry,
  registerSessionExpiryInterceptor,
} from '~/authentication/sessions/session_expiry';

describe('session expiry', () => {
  const expiresAtSeconds = 1893456000;
  const expiresAtMs = expiresAtSeconds * 1000;
  let broadcastChannel;
  let onMessage;

  beforeEach(() => {
    onMessage = jest.fn();
    broadcastChannel = new BroadcastChannel(BROADCAST_CHANNEL_SESSION_EXPIRY);
    broadcastChannel.addEventListener('message', onMessage);
  });

  afterEach(() => {
    broadcastChannel.removeEventListener('message', onMessage);
    broadcastChannel.close();
  });

  // jsdom delivers a broadcast one task after the post, so a single flush can observe
  // the channel before the message lands.
  const flushBroadcasts = async () => {
    await waitForPromises();
    await waitForPromises();
  };

  const expectBroadcast = async (expected) => {
    await flushBroadcasts();

    expect(onMessage).toHaveBeenCalledTimes(1);
    expect(onMessage.mock.calls[0][0].data).toBe(expected);
  };

  const expectNoBroadcast = async () => {
    await flushBroadcasts();

    expect(onMessage).not.toHaveBeenCalled();
  };

  describe('broadcastSessionExpiry', () => {
    it('broadcasts the deadline in milliseconds', async () => {
      broadcastSessionExpiry(String(expiresAtSeconds));

      await expectBroadcast(expiresAtMs);
    });

    it.each([undefined, null, '', 'not-a-number', '0', '-1'])(
      'does not broadcast for %p',
      async (headerValue) => {
        broadcastSessionExpiry(headerValue);

        await expectNoBroadcast();
      },
    );
  });

  describe('registerSessionExpiryInterceptor', () => {
    let axios;
    let mock;

    beforeEach(() => {
      axios = realAxios.create();
      mock = new MockAdapter(axios);
      registerSessionExpiryInterceptor(axios);
    });

    afterEach(() => {
      mock.restore();
    });

    it('broadcasts the deadline from a successful response', async () => {
      mock.onGet('/foo').reply(200, {}, { [SESSION_EXPIRES_AT_HEADER]: String(expiresAtSeconds) });

      await axios.get('/foo');

      await expectBroadcast(expiresAtMs);
    });

    it('broadcasts the deadline from an error response', async () => {
      mock.onGet('/foo').reply(500, {}, { [SESSION_EXPIRES_AT_HEADER]: String(expiresAtSeconds) });

      await expect(axios.get('/foo')).rejects.toThrow();

      await expectBroadcast(expiresAtMs);
    });

    it('does not broadcast when the response has no deadline', async () => {
      mock.onGet('/foo').reply(200, {});

      await axios.get('/foo');

      await expectNoBroadcast();
    });
  });

  describe('apolloSessionExpiryLink', () => {
    let subscription;

    afterEach(() => subscription?.unsubscribe());

    const createSubscription = (headers) => {
      const terminatingLink = new ApolloLink(() => Observable.of({ data: { foo: { id: 1 } } }));
      const mockOperation = {
        operationName: 'someMockOperation',
        context: { response: headers ? { headers } : undefined },
      };

      return new Promise((resolve) => {
        subscription = execute(
          apolloSessionExpiryLink.concat(terminatingLink),
          mockOperation,
        ).subscribe(resolve);
      });
    };

    it('broadcasts the deadline from the response headers', async () => {
      await createSubscription({
        get: (name) => (name === SESSION_EXPIRES_AT_HEADER ? String(expiresAtSeconds) : null),
      });

      await expectBroadcast(expiresAtMs);
    });

    it('broadcasts the deadline from an error response', async () => {
      const failingLink = new ApolloLink(
        () => new Observable((observer) => observer.error(new Error('request failed'))),
      );
      const mockOperation = {
        operationName: 'someMockOperation',
        context: { response: { headers: { get: () => String(expiresAtSeconds) } } },
      };

      await new Promise((resolve) => {
        subscription = execute(
          apolloSessionExpiryLink.concat(failingLink),
          mockOperation,
        ).subscribe({ next: () => {}, error: () => resolve() });
      });

      await expectBroadcast(expiresAtMs);
    });

    it('does not broadcast when the response has no deadline', async () => {
      await createSubscription({ get: () => null });

      await expectNoBroadcast();
    });

    it('does not broadcast when there is no response on the context', async () => {
      await createSubscription(null);

      await expectNoBroadcast();
    });

    it('does not modify the response', async () => {
      const response = await createSubscription({
        get: () => String(expiresAtSeconds),
      });

      expect(response.data).toEqual({ foo: { id: 1 } });
    });
  });
});
