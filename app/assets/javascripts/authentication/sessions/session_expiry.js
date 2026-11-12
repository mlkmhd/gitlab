import { BROADCAST_CHANNEL_SESSION_EXPIRY, SESSION_EXPIRES_AT_HEADER } from './constants';

/**
 * The server reports the deadline on every session-authenticated response, so
 * rebroadcasting it keeps the modal from warning a user who is still active in a
 * page that never fully reloads.
 *
 * @param {string|null|undefined} headerValue Session expiry as an epoch in seconds.
 */
export const broadcastSessionExpiry = (headerValue) => {
  const expiresAtSeconds = Number(headerValue);

  if (!Number.isFinite(expiresAtSeconds) || expiresAtSeconds <= 0) return;

  const channel = new BroadcastChannel(BROADCAST_CHANNEL_SESSION_EXPIRY);
  channel.postMessage(expiresAtSeconds * 1000);
  channel.close();
};

export const registerSessionExpiryInterceptor = (axiosInstance) => {
  axiosInstance.interceptors.response.use(
    (response) => {
      broadcastSessionExpiry(response.headers?.[SESSION_EXPIRES_AT_HEADER]);

      return response;
    },
    (error) => {
      // A failed request is still activity, so read the deadline off error responses too.
      broadcastSessionExpiry(error.response?.headers?.[SESSION_EXPIRES_AT_HEADER]);

      return Promise.reject(error);
    },
  );
};
