import {
  effectiveVisibleGroups,
  exceedsGroupLimit,
  isGroupVisible,
  toggleGroupVisibility,
} from '~/work_items/board/grouping/visibility';

describe('work_items/board/grouping/visibility', () => {
  const groupBy = { property: 'status' };
  const values = [
    { id: 'a', name: 'A' },
    { id: 'b', name: 'B' },
    { id: 'c', name: 'C' },
  ];
  const groupId = (value) => `status:${value.id}`;

  describe('isGroupVisible', () => {
    describe.each`
      scenario       | visibleGroups
      ${'null'}      | ${null}
      ${'undefined'} | ${undefined}
    `('when visibleGroups is $scenario', ({ visibleGroups }) => {
      it('returns true for every value', () => {
        values.forEach((value) => {
          expect(isGroupVisible(visibleGroups, groupBy, value)).toBe(true);
        });
      });
    });

    describe('when visibleGroups is an explicit list', () => {
      const visibleGroups = [groupId(values[0])];

      it('returns true for a value in the list', () => {
        expect(isGroupVisible(visibleGroups, groupBy, values[0])).toBe(true);
      });

      it('returns false for a value missing from the list', () => {
        expect(isGroupVisible(visibleGroups, groupBy, values[1])).toBe(false);
      });
    });
  });

  describe('exceedsGroupLimit', () => {
    it.each`
      groupCount | expected
      ${0}       | ${false}
      ${25}      | ${false}
      ${26}      | ${true}
    `('returns $expected for $groupCount groups', ({ groupCount, expected }) => {
      expect(exceedsGroupLimit(groupCount)).toBe(expected);
    });
  });

  describe('effectiveVisibleGroups', () => {
    const manyValues = Array.from({ length: 26 }, (_, index) => ({
      id: `${index}`,
      name: `${index}`,
    }));

    describe('when visibleGroups is null', () => {
      it('stays null while the group count is within the limit', () => {
        expect(
          effectiveVisibleGroups({
            visibleGroups: null,
            groupBy,
            values: manyValues.slice(0, 25),
          }),
        ).toBeNull();
      });

      it('becomes the first 25 group ids once the group count passes the limit', () => {
        expect(
          effectiveVisibleGroups({ visibleGroups: null, groupBy, values: manyValues }),
        ).toEqual(manyValues.slice(0, 25).map((value) => groupId(value)));
      });
    });

    describe('when visibleGroups is an explicit list', () => {
      it('returns the list unchanged whatever the group count', () => {
        const visibleGroups = [groupId(manyValues[0])];

        expect(effectiveVisibleGroups({ visibleGroups, groupBy, values: manyValues })).toBe(
          visibleGroups,
        );
      });
    });
  });

  describe('toggleGroupVisibility', () => {
    describe('when every group is visible', () => {
      it('excludes the toggled value', () => {
        expect(
          toggleGroupVisibility({
            visibleGroups: null,
            groupBy,
            value: values[1],
            allGroups: values,
          }),
        ).toEqual([groupId(values[0]), groupId(values[2])]);
      });
    });

    describe('when the last hidden group is toggled back on', () => {
      let afterFirstToggle;

      beforeEach(() => {
        afterFirstToggle = toggleGroupVisibility({
          visibleGroups: null,
          groupBy,
          value: values[1],
          allGroups: values,
        });
      });

      it('collapses back to null', () => {
        expect(
          toggleGroupVisibility({
            visibleGroups: afterFirstToggle,
            groupBy,
            value: values[1],
            allGroups: values,
          }),
        ).toBeNull();
      });
    });

    describe('when visibleGroups is an explicit list', () => {
      const visibleGroups = [groupId(values[0]), groupId(values[1])];

      it('adds a hidden value to the list', () => {
        expect(
          toggleGroupVisibility({
            visibleGroups: [groupId(values[0])],
            groupBy,
            value: values[1],
            allGroups: values,
          }),
        ).toEqual([groupId(values[0]), groupId(values[1])]);
      });

      it('removes a visible value from the list', () => {
        expect(
          toggleGroupVisibility({ visibleGroups, groupBy, value: values[0], allGroups: values }),
        ).toEqual([groupId(values[1])]);
      });

      it('returns an empty list, not null, when the last visible value is removed', () => {
        expect(
          toggleGroupVisibility({
            visibleGroups: [groupId(values[0])],
            groupBy,
            value: values[0],
            allGroups: values,
          }),
        ).toEqual([]);
      });
    });
  });
});
