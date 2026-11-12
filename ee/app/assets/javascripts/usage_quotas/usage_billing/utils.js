import { THOUSAND, MILLION } from '~/lib/utils/constants';
import { OTHER_SKIP_REASON, SKIP_REASONS } from './constants';

export const fillUsageValues = (usage) => {
  const { creditsUsed, totalCredits, totalCreditsUsed, nonBillableCreditsUsed } = usage ?? {};

  return {
    creditsUsed: creditsUsed ?? 0,
    totalCredits: totalCredits ?? 0,
    totalCreditsUsed: totalCreditsUsed ?? 0,
    nonBillableCreditsUsed: nonBillableCreditsUsed ?? 0,
  };
};

/**
 * Formats number with a fixed fraction digits if below 1000, or with a metric prefix
 *
 * @param {number} value
 * @returns {string}
 */
export const formatNumber = (value) => {
  if (value === 0) return '0';
  if (!value) return `${value}`;
  if (value < THOUSAND) {
    if (Number.isInteger(value)) return `${value}`;
    const FRACTION_DIGITS = 2;
    const multiplier = 10 ** FRACTION_DIGITS;
    return (Math.round(value * multiplier) / multiplier).toFixed(FRACTION_DIGITS);
  }

  const THOUSAND_FRACTION_DIGITS = 1;
  // Handle metric prefix with custom fraction digits
  if (value < MILLION) {
    return `${Number((value / THOUSAND).toFixed(THOUSAND_FRACTION_DIGITS))}k`;
  }
  return `${Number((value / MILLION).toFixed(THOUSAND_FRACTION_DIGITS))}m`;
};

export const skipReasonKey = (skipReason) =>
  Object.hasOwn(SKIP_REASONS, skipReason) ? skipReason : OTHER_SKIP_REASON;

export const skipReasonLabel = (skipReason) => SKIP_REASONS[skipReasonKey(skipReason)].label;
