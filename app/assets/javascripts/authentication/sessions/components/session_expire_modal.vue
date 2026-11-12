<script>
import { GlModal } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { buildApiUrl } from '~/api/api_utils';
import { refreshCurrentPage, visitUrl } from '~/lib/utils/url_utility';
import { __ } from '~/locale';
import {
  BROADCAST_CHANNEL_SESSION_EXPIRE_MODAL_SHOWN,
  INTERVAL_SESSION_MODAL,
  KEEP_ALIVE_LEAD,
  KEEP_ALIVE_PATH,
  SESSION_EXPIRES_AT_HEADER,
} from '../constants';
import { broadcastSessionExpiry } from '../session_expiry';

export default {
  name: 'SessionExpireModal',
  components: {
    GlModal,
  },
  props: {
    // When true, announce this modal's visibility on the shown-channel so subordinate
    // modals (the group-SAML reload modal) yield while it is shown and resume when it is
    // hidden. Only the general modal sets this.
    announceShown: {
      type: Boolean,
      required: false,
      default: false,
    },
    broadcastChannel: {
      type: String,
      required: true,
    },
    message: {
      type: String,
      required: true,
    },
    // When the remember me cookie stops signing the user back in. While it outlasts the
    // session deadline, a reload would sign the user straight back in, so the session is
    // kept alive instead of warning.
    rememberMeExpiresAt: {
      type: Number,
      required: false,
      default: null,
    },
    sessionTimeout: {
      type: Number,
      required: true,
    },
    signInUrl: {
      type: String,
      default: null,
      required: false,
    },
    title: {
      type: String,
      required: true,
    },
  },
  data() {
    return {
      broadcastChannelInstance: null,
      shownChannelInstance: null,
      intervalId: null,
      keptAliveFor: null,
      modalId: uniqueId('expire-session-modal-'),
      showModal: false,
      timeout: this.sessionTimeout,
    };
  },
  computed: {
    reload() {
      const text = this.signInUrl ? __('Sign in') : __('Reload page');
      return { text };
    },
  },
  async created() {
    this.broadcastChannelInstance = new BroadcastChannel(this.broadcastChannel);
    this.broadcastChannelInstance.postMessage(this.timeout);
    this.broadcastChannelInstance.addEventListener('message', this.reset);
    if (this.announceShown) {
      this.shownChannelInstance = new BroadcastChannel(
        BROADCAST_CHANNEL_SESSION_EXPIRE_MODAL_SHOWN,
      );
    }
    this.setEvents();
  },
  beforeDestroy() {
    this.clearEvents();
    this.broadcastChannelInstance.removeEventListener('message', this.reset);
    this.broadcastChannelInstance.close();
    this.shownChannelInstance?.close();
  },
  methods: {
    clearEvents() {
      if (this.intervalId) {
        clearInterval(this.intervalId);
        document.removeEventListener('visibilitychange', this.onDocumentVisible);
        this.intervalId = null;
      }
    },
    announceShownState(shown) {
      this.shownChannelInstance?.postMessage(shown);
    },
    checkStatus() {
      const now = Date.now();

      if (now >= this.timeout) {
        this.showModal = true;
        this.announceShownState(true);
        this.clearEvents();
      } else if (this.shouldKeepAlive(now)) {
        this.keepAlive();
      }
    },
    shouldKeepAlive(now) {
      return (
        this.rememberMeExpiresAt > this.timeout &&
        now >= this.timeout - KEEP_ALIVE_LEAD &&
        this.keptAliveFor !== this.timeout
      );
    },
    // A plain fetch, never tagged as background by idle tracking and uncached, so it always
    // reaches the server and saves the session. It bypasses the axios interceptor, so it
    // rebroadcasts the header itself.
    async keepAlive() {
      this.keptAliveFor = this.timeout;

      try {
        const response = await fetch(buildApiUrl(KEEP_ALIVE_PATH), { cache: 'no-store' });

        broadcastSessionExpiry(response.headers.get(SESSION_EXPIRES_AT_HEADER));
      } catch {
        // Let a later check retry, for example once the network is back after a wake from
        // sleep. The modal still fires at the current deadline.
        this.keptAliveFor = null;
      }
    },
    goTo() {
      if (this.signInUrl) {
        visitUrl(this.signInUrl);
      } else {
        refreshCurrentPage();
      }
    },
    onDocumentVisible() {
      if (document.visibilityState === 'visible') {
        this.checkStatus();
      }
    },
    /** @param {MessageEvent} event */
    reset(event) {
      // Ignore anything that isn't a deadline, so tabs running older code treat
      // future message types on this channel as a no-op.
      const deadline = Number(event.data);
      if (!Number.isFinite(deadline) || deadline <= 0) return;

      this.timeout = deadline;
      if (!this.intervalId) {
        // The modal had already fired; a later deadline hides it again, so tell the
        // subordinate modals they may resume (they yielded when it was shown).
        this.showModal = false;
        this.announceShownState(false);
        this.setEvents();
      }
    },
    setEvents() {
      // Poll rather than a single setTimeout to the deadline: background tabs throttle or
      // defer timers, so a one-shot timer can miss it. The interval plus the
      // visibilitychange re-check stays reliable.
      this.intervalId = setInterval(this.checkStatus, INTERVAL_SESSION_MODAL);
      this.checkStatus();
      document.addEventListener('visibilitychange', this.onDocumentVisible);
    },
  },
  cancel: { text: __('Cancel') },
};
</script>

<template>
  <gl-modal
    v-model="showModal"
    :modal-id="modalId"
    :title="title"
    :action-primary="reload"
    :action-cancel="$options.cancel"
    aria-live="assertive"
    @primary="goTo"
  >
    {{ message }}
  </gl-modal>
</template>
