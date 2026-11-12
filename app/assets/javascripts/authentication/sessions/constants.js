export const BROADCAST_CHANNEL_SESSION_EXPIRY = 'session-expiry-notifications';
export const BROADCAST_CHANNEL_SAML_SESSION_EXPIRY = 'saml-session-expiry-notifications';
// Signals that the general session-expiry modal is displaying, so subordinate modals
// (the group-SAML reload modal) yield instead of stacking on top of it.
export const BROADCAST_CHANNEL_SESSION_EXPIRE_MODAL_SHOWN = 'session-expire-modal-shown';
export const INTERVAL_SESSION_MODAL = 1 * 1000;
// Mirrors Gitlab::Middleware::SessionExpiryHeader::HEADER. Lowercased for the axios
// interceptor, which lowercases response header keys; Apollo reads it through the Fetch
// Headers.get(), which is case-insensitive, so the same value works there too.
export const SESSION_EXPIRES_AT_HEADER = 'x-gitlab-session-expires-at';
// How long before the deadline a remembered user's session is kept alive. Hidden tabs may
// run timers only once a minute, so this leaves at least one check inside the window.
export const KEEP_ALIVE_LEAD = 2 * 60 * 1000;
export const KEEP_ALIVE_PATH = '/api/:version/version';
