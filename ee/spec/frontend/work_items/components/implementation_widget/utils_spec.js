import { AGENT_STEP_PILL_VARIANTS } from 'ee/work_items/components/implementation_widget/constants';
import {
  buildWorkplanPageUrl,
  buildWorkplanQuery,
  getVariantColor,
  getLatestDeveloperSession,
  isDeveloperSession,
  isValidReadinessScore,
} from 'ee/work_items/components/implementation_widget/utils';

describe('workplan utils', () => {
  describe('getVariantColor', () => {
    it.each(Object.entries(AGENT_STEP_PILL_VARIANTS))(
      'returns the "%s" color for the "%s" variant',
      (variant, expectedColor) => {
        expect(getVariantColor(variant)).toBe(expectedColor);
      },
    );

    it('uses the neutral icon color for canceled workplans', () => {
      expect(getVariantColor('neutral')).toBe('var(--gl-status-neutral-icon-color)');
    });

    describe('when the variant is unknown', () => {
      it('falls back to the placeholder color', () => {
        expect(getVariantColor('unknown')).toBe(AGENT_STEP_PILL_VARIANTS.placeholder);
      });
    });
  });

  describe('isValidReadinessScore', () => {
    it.each([null, 0, 50, 100])('accepts %s', (score) => {
      expect(isValidReadinessScore(score)).toBe(true);
    });

    it.each([-1, 101, 50.5, undefined, NaN])('rejects %s', (score) => {
      expect(isValidReadinessScore(score)).toBe(false);
    });
  });

  describe('buildWorkplanQuery', () => {
    it.each`
      editing      | query
      ${undefined} | ${{ show: 'workplan' }}
      ${false}     | ${{ show: 'workplan' }}
      ${true}      | ${{ show: 'workplan', workplan_state: 'edit' }}
    `('returns $query when editing is $editing', ({ editing, query }) => {
      expect(buildWorkplanQuery({ editing })).toEqual(query);
    });
  });

  describe('buildWorkplanPageUrl', () => {
    it('appends show=workplan to a relative base for view mode', () => {
      expect(buildWorkplanPageUrl('/group/project/-/work_items/9')).toBe(
        '/group/project/-/work_items/9?show=workplan',
      );
    });

    it('appends the edit state to a relative base for edit mode', () => {
      expect(buildWorkplanPageUrl('/group/project/-/work_items/9', { editing: true })).toBe(
        '/group/project/-/work_items/9?show=workplan&workplan_state=edit',
      );
    });
  });

  describe('isDeveloperSession', () => {
    it.each`
      workflowDefinition | expected
      ${'developer/v1'}  | ${true}
      ${'workplan/v1'}   | ${false}
      ${undefined}       | ${false}
    `('returns $expected for $workflowDefinition', ({ workflowDefinition, expected }) => {
      expect(isDeveloperSession({ workflowDefinition })).toBe(expected);
    });
  });

  describe('getLatestDeveloperSession', () => {
    const olderSession = {
      id: 1,
      workflowDefinition: 'developer/v1',
      createdAt: '2026-01-15T09:00:00Z',
    };
    const newerSession = {
      id: 2,
      workflowDefinition: 'developer/v1',
      createdAt: '2026-01-16T09:00:00Z',
    };
    const newestWorkplanSession = {
      id: 3,
      workflowDefinition: 'workplan/v1',
      createdAt: '2026-01-17T09:00:00Z',
    };

    describe('when there are no Developer flow sessions', () => {
      it('returns nothing', () => {
        expect(getLatestDeveloperSession([newestWorkplanSession])).toBeUndefined();
      });
    });

    describe('when there are Developer flow sessions', () => {
      it('returns the most recently created one', () => {
        expect(getLatestDeveloperSession([olderSession, newestWorkplanSession, newerSession])).toBe(
          newerSession,
        );
      });
    });
  });
});
