import {
  CHILD_ROWS_KEY,
  ROW_KEY,
  childDimensionOf,
  withBreakdown,
  withChildRows,
} from '~/glql/components/presenters/utils/expandable_table';

const group = { key: 'Group', field: 'group', type: 'dimension' };
const project = { key: 'project', type: 'dimension' };
const usersCount = { key: 'usersCount', type: 'metric' };

const platform = { id: 'gid://gitlab/Group/2' };
const api = { id: 'gid://gitlab/Project/1' };
const web = { id: 'gid://gitlab/Project/2' };

describe('expand rows utils', () => {
  describe('childDimensionOf', () => {
    it('returns the dimension the child query adds', () => {
      expect(childDimensionOf([group, usersCount], [group, project, usersCount])).toBe(project);
    });

    it('returns null when the child query adds none', () => {
      expect(childDimensionOf([group, usersCount], [group, usersCount])).toBeNull();
    });

    it('returns null when the child query adds several', () => {
      const user = { key: 'user', type: 'dimension' };

      expect(childDimensionOf([group, usersCount], [group, project, user, usersCount])).toBeNull();
    });
  });

  describe('withChildRows', () => {
    const dimensions = { parentDimensions: [group], childDimensions: [group, project] };

    const childrenKeysOf = (rows) => rows.map((row) => row[CHILD_ROWS_KEY].map((c) => c[ROW_KEY]));

    it('nests each child under the parent with the same parent dimensions', () => {
      const rows = withChildRows(
        [{ Group: platform }, { Group: { id: 'gid://gitlab/Group/3' } }],
        [
          { Group: platform, project: api },
          { Group: platform, project: web },
        ],
        dimensions,
      );

      expect(rows.map((row) => row[ROW_KEY])).toEqual([
        '["gid://gitlab/Group/2"]',
        '["gid://gitlab/Group/3"]',
      ]);
      expect(childrenKeysOf(rows)).toEqual([
        [
          '["gid://gitlab/Group/2","gid://gitlab/Project/1"]',
          '["gid://gitlab/Group/2","gid://gitlab/Project/2"]',
        ],
        [],
      ]);
    });

    it('nests children under the NULL bucket like any other row', () => {
      const rows = withChildRows([{ Group: null }], [{ Group: null, project: api }], dimensions);

      expect(childrenKeysOf(rows)).toEqual([['[null,"gid://gitlab/Project/1"]']]);
    });

    it('leaves out children whose parent is not loaded', () => {
      const rows = withChildRows(
        [{ Group: platform }],
        [{ Group: null, project: api }],
        dimensions,
      );

      expect(childrenKeysOf(rows)).toEqual([[]]);
    });

    it('gives parents that share a key no key and no children', () => {
      const rows = withChildRows(
        [{ Group: null }, { Group: null }],
        [{ Group: null, project: api }],
        dimensions,
      );

      expect(rows.map((row) => [row[ROW_KEY], row[CHILD_ROWS_KEY]])).toEqual([
        [null, []],
        [null, []],
      ]);
    });

    it('keeps children that share a key, without one', () => {
      const rows = withChildRows(
        [{ Group: platform }],
        [
          { Group: platform, project: null },
          { Group: platform, project: null },
        ],
        dimensions,
      );

      expect(childrenKeysOf(rows)).toEqual([[null, null]]);
    });

    it('does not mutate its input', () => {
      const parents = [{ Group: platform }];
      withChildRows(parents, [{ Group: platform, project: api }], dimensions);

      expect(parents).toEqual([{ Group: platform }]);
    });
  });

  describe('withBreakdown', () => {
    const fields = [group, usersCount];
    const data = { count: 1, nodes: [{ Group: platform, usersCount: 3 }] };
    const breakdownData = {
      count: 2,
      fields: [group, project, usersCount],
      nodes: [
        { Group: platform, project: api, usersCount: 2 },
        { Group: platform, project: web, usersCount: 1 },
      ],
    };

    it('keys each row with no children until the breakdown lands', () => {
      expect(withBreakdown({ fields, data, breakdownData: null })).toEqual({
        data: {
          count: 1,
          nodes: [
            {
              Group: platform,
              usersCount: 3,
              [ROW_KEY]: '["gid://gitlab/Group/2"]',
              [CHILD_ROWS_KEY]: [],
            },
          ],
        },
        dimension: null,
        truncatedCount: null,
        error: null,
      });
    });

    it('nests the breakdown rows and names the dimension they add', () => {
      const result = withBreakdown({ fields, data, breakdownData });

      expect(result.dimension).toBe(project);
      expect(result.data.nodes[0][CHILD_ROWS_KEY].map((child) => child.project)).toEqual([
        api,
        web,
      ]);
      expect(result.truncatedCount).toBeNull();
      expect(result.error).toBeNull();
    });

    it('counts the loaded rows when the breakdown stopped short of its total', () => {
      expect(
        withBreakdown({ fields, data, breakdownData: { ...breakdownData, count: 5 } })
          .truncatedCount,
      ).toBe(2);
    });

    it.each([
      ['none', [group, usersCount]],
      ['several', [group, project, { key: 'user', type: 'dimension' }, usersCount]],
    ])('fails when the breakdown adds %s', (_, breakdownFields) => {
      const result = withBreakdown({
        fields,
        data,
        breakdownData: { ...breakdownData, fields: breakdownFields },
      });

      expect(result.error).toBe(
        '`expandRowsBy` must name one dimension the query does not already use.',
      );
      expect(result.data.nodes[0][CHILD_ROWS_KEY]).toEqual([]);
    });
  });
});
