export const MODAL_ID = 'feature-library-modal';

export const SHIMMER_CALLOUT_FEATURE_NAME = 'feature_library_shimmer_seen';

export const TIERS = Object.freeze({
  FREE: 'free',
  PREMIUM: 'premium',
  ULTIMATE: 'ultimate',
  ADD_ON: 'add_on',
});

export const ITEMS_PER_RENDER_FRAME = 18;

export const SENTRY_CONTEXT = Object.freeze({ tags: { feature_category: 'onboarding' } });

export const ITEM_VARIANTS = Object.freeze({
  DEFAULT: 'default',
  LOCKED: 'locked',
});

// The `label.type` the catalog endpoint sends for an item that's new with the page's plan.
export const LABEL_TYPE_NEW = 'new';
