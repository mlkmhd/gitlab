import { OTHER_SKIP_REASON, SKIP_REASONS } from 'ee/usage_quotas/usage_billing/constants';
import {
  fillUsageValues,
  formatNumber,
  skipReasonKey,
  skipReasonLabel,
} from 'ee/usage_quotas/usage_billing/utils';

describe('fillUsageValues', () => {
  describe('with complete usage data', () => {
    it('returns the provided values when all properties are present', () => {
      const usage = {
        creditsUsed: 100,
        totalCredits: 500,
        totalCreditsUsed: 550,
        nonBillableCreditsUsed: 5,
      };

      const result = fillUsageValues(usage);

      expect(result).toEqual({
        creditsUsed: 100,
        totalCredits: 500,
        totalCreditsUsed: 550,
        nonBillableCreditsUsed: 5,
      });
    });
  });

  describe('null value coalescing', () => {
    it.each([null, undefined, {}])('returns 0 for all properties when usage is %p', (usage) => {
      expect(fillUsageValues(usage)).toEqual({
        creditsUsed: 0,
        totalCredits: 0,
        totalCreditsUsed: 0,
        nonBillableCreditsUsed: 0,
      });
    });

    it('handles mixed null and undefined values', () => {
      const usage = {
        creditsUsed: null,
        totalCredits: undefined,
        totalCreditsUsed: 200,
        nonBillableCreditsUsed: null,
      };

      const result = fillUsageValues(usage);

      expect(result).toEqual({
        creditsUsed: 0,
        totalCredits: 0,
        totalCreditsUsed: 200,
        nonBillableCreditsUsed: 0,
      });
    });

    it('handles partial usage objects with missing properties', () => {
      const usage = {
        creditsUsed: 100,
        totalCredits: 500,
        // totalCreditsUsed and nonBillableCreditsUsed are missing
      };

      const result = fillUsageValues(usage);

      expect(result).toEqual({
        creditsUsed: 100,
        totalCredits: 500,
        totalCreditsUsed: 0,
        nonBillableCreditsUsed: 0,
      });
    });

    it('handles falsy values that are not null or undefined', () => {
      const usage = {
        creditsUsed: false,
        totalCredits: '',
        totalCreditsUsed: NaN,
        nonBillableCreditsUsed: 0,
      };

      const result = fillUsageValues(usage);

      expect(result).toEqual({
        creditsUsed: false,
        totalCredits: '',
        totalCreditsUsed: NaN,
        nonBillableCreditsUsed: 0,
      });
    });
  });
});

describe('formatNumber', () => {
  describe.each`
    number       | expected
    ${0}         | ${'0'}
    ${0.5}       | ${'0.50'}
    ${0.9001}    | ${'0.90'}
    ${0.9999}    | ${'1.00'}
    ${5.35}      | ${'5.35'}
    ${17.35}     | ${'17.35'}
    ${42}        | ${'42'}
    ${999.2}     | ${'999.20'}
    ${1000}      | ${'1k'}
    ${1500}      | ${'1.5k'}
    ${1777}      | ${'1.8k'}
    ${NaN}       | ${'NaN'}
    ${null}      | ${'null'}
    ${undefined} | ${'undefined'}
  `('$number', ({ number, expected }) => {
    it(`formats the number correctly`, () => {
      const result = formatNumber(number);
      expect(result).toEqual(expected);
    });
  });
});

describe('skipReasonKey', () => {
  it.each`
    skipReason    | expected
    ${'promo'}    | ${'promo'}
    ${'beta'}     | ${'beta'}
    ${'other'}    | ${OTHER_SKIP_REASON}
    ${'unknown'}  | ${OTHER_SKIP_REASON}
    ${null}       | ${OTHER_SKIP_REASON}
    ${undefined}  | ${OTHER_SKIP_REASON}
    ${'toString'} | ${OTHER_SKIP_REASON}
  `('returns $expected for $skipReason', ({ skipReason, expected }) => {
    expect(skipReasonKey(skipReason)).toBe(expected);
  });
});

describe('skipReasonLabel', () => {
  it.each`
    skipReason   | expected
    ${'promo'}   | ${SKIP_REASONS.promo.label}
    ${'beta'}    | ${SKIP_REASONS.beta.label}
    ${'unknown'} | ${SKIP_REASONS[OTHER_SKIP_REASON].label}
    ${null}      | ${SKIP_REASONS[OTHER_SKIP_REASON].label}
  `('returns $expected for $skipReason', ({ skipReason, expected }) => {
    expect(skipReasonLabel(skipReason)).toBe(expected);
  });
});
