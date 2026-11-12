import {
  COVERAGE_CHECK_NAME,
  REPORT_TYPE_CODE_COVERAGE,
  RULE_TYPE_REPORT_APPROVER,
} from 'ee/approvals/constants';
import {
  mergeRequestApprovalSettingsMappers,
  mapApprovalRuleRequest,
  mapApprovalSettingsResponse,
  excludeDuplicatesInResponse,
} from 'ee/approvals/mappers';
import {
  createGroupApprovalsPayload,
  createGroupApprovalsState,
  createProjectRules,
  createNextPageProjectRules,
} from './mocks';

describe('approvals mappers', () => {
  describe('mergeRequestApprovalSettingsMappers', () => {
    const approvalsState = createGroupApprovalsState();
    const approvalsFetchPayload = createGroupApprovalsPayload();
    const approvalsUpdatePayload = {
      allow_author_approval: true,
      allow_overrides_to_approver_list_per_merge_request: true,
      require_password_to_approve: true,
      retain_approvals_on_push: false,
      selective_code_owner_removals: false,
      allow_committer_approval: true,
    };

    it('maps data to state', () => {
      expect(
        mergeRequestApprovalSettingsMappers.mapDataToState(approvalsFetchPayload),
      ).toStrictEqual(approvalsState.settings);
    });

    it('maps state to payload', () => {
      expect(mergeRequestApprovalSettingsMappers.mapStateToPayload(approvalsState)).toStrictEqual(
        approvalsUpdatePayload,
      );
    });
  });

  describe('mapApprovalRuleRequest', () => {
    describe.each`
      ruleName               | expectedReportType           | expectedRuleType
      ${COVERAGE_CHECK_NAME} | ${REPORT_TYPE_CODE_COVERAGE} | ${RULE_TYPE_REPORT_APPROVER}
      ${'Test Name'}         | ${undefined}                 | ${undefined}
    `('with rule name set to $ruleName', ({ ruleName, expectedRuleType, expectedReportType }) => {
      it(`it returns ${expectedRuleType} rule_type for ${ruleName}`, () => {
        expect(mapApprovalRuleRequest({ name: ruleName }).rule_type).toBe(expectedRuleType);
      });
      it(`it returns ${expectedReportType} report_type for ${ruleName}`, () => {
        expect(mapApprovalRuleRequest({ name: ruleName }).report_type).toBe(expectedReportType);
      });
    });
  });

  describe('mapApprovalSettingsResponse', () => {
    describe.each([undefined, false, true])('with filter set to %s', (filter) => {
      it('maps each approval rule', () => {
        const response = [
          { id: 1, approvals_required: 2, source_rule: null },
          { id: 2, approvals_required: 3, source_rule: { id: 4 } },
        ];

        expect(mapApprovalSettingsResponse(response, filter)).toStrictEqual({
          rules: [
            {
              id: 1,
              approvalsRequired: 2,
              sourceRule: null,
              hasSource: false,
              minApprovalsRequired: 0,
            },
            {
              id: 2,
              approvalsRequired: 3,
              sourceRule: { id: 4 },
              hasSource: true,
              minApprovalsRequired: 0,
            },
          ],
          fallbackApprovalsRequired: undefined,
        });
      });

      it('adds a default rule only when the empty response has no filter', () => {
        expect(mapApprovalSettingsResponse([], filter)).toStrictEqual({
          rules: filter
            ? []
            : [
                {
                  id: null,
                  name: '',
                  approvalsRequired: 0,
                  minApprovalsRequired: 0,
                  approvers: [],
                  containsHiddenGroups: false,
                  users: [],
                  groups: [],
                  ruleType: 'any_approver',
                  protectedBranches: [],
                  appliesToAllProtectedBranches: false,
                  overridden: false,
                },
              ],
          fallbackApprovalsRequired: undefined,
        });
      });
    });
  });

  describe('excludeDuplicatesInResponse', () => {
    it('returns the next page rules excluding the duplicates based on existing state', () => {
      const rulesInState = createProjectRules();
      const nextPageProjectRules = createNextPageProjectRules();

      expect(excludeDuplicatesInResponse(nextPageProjectRules, rulesInState)).toStrictEqual(
        nextPageProjectRules.slice(1),
      );
    });
  });
});
