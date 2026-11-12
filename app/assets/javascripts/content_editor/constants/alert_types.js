export const ALERT_TYPES = {
  NOTE: 'note',
  TIP: 'tip',
  IMPORTANT: 'important',
  CAUTION: 'caution',
  WARNING: 'warning',
};

// Must match the default titles in the rendered Markdown, so do not translate.
// Use translated labels only for UI such as the alert type dropdown.
/* eslint-disable @gitlab/require-i18n-strings */
export const DEFAULT_ALERT_TITLES = {
  [ALERT_TYPES.NOTE]: 'Note',
  [ALERT_TYPES.TIP]: 'Tip',
  [ALERT_TYPES.IMPORTANT]: 'Important',
  [ALERT_TYPES.CAUTION]: 'Caution',
  [ALERT_TYPES.WARNING]: 'Warning',
};
/* eslint-enable @gitlab/require-i18n-strings */
