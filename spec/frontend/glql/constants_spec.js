import {
  DISPLAY_TYPES,
  MODE_ANALYTICS,
  MODE_STANDARD,
  PAGINATION_AUTO,
  PAGINATION_BY_DISPLAY_TYPE,
  PAGINATION_LOAD_MORE,
  PAGINATION_PAGED,
} from '~/glql/constants';

describe('GLQL constants', () => {
  describe('PAGINATION_BY_DISPLAY_TYPE', () => {
    it('assigns pagination strategies to every display type', () => {
      expect(Object.keys(PAGINATION_BY_DISPLAY_TYPE).sort()).toEqual(
        Object.values(DISPLAY_TYPES).sort(),
      );
    });

    it.each(Object.entries(PAGINATION_BY_DISPLAY_TYPE))(
      'names a known strategy for each known mode for %s',
      (_display, strategies) => {
        expect(Object.keys(strategies).length).toBeGreaterThan(0);

        Object.entries(strategies).forEach(([mode, strategy]) => {
          expect([MODE_STANDARD, MODE_ANALYTICS]).toContain(mode);
          expect([PAGINATION_LOAD_MORE, PAGINATION_AUTO, PAGINATION_PAGED]).toContain(strategy);
        });
      },
    );
  });
});
