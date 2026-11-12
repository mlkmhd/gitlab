import { orderByIds, reorderIds } from '~/work_items/utils/ordering';

describe('work_items/utils/ordering', () => {
  const values = [{ id: 'a' }, { id: 'b' }, { id: 'c' }];
  const getId = (value) => value.id;

  describe('orderByIds', () => {
    it('orders values by the id the getter returns, with unknown ones at the end', () => {
      expect(orderByIds({ order: ['c', 'a'], values, getId })).toEqual([
        values[2],
        values[0],
        values[1],
      ]);
    });

    it('returns the values unchanged when there is no stored order', () => {
      expect(orderByIds({ order: [], values, getId })).toBe(values);
    });

    it('ignores stored ids that no longer match a value', () => {
      expect(orderByIds({ order: ['gone', 'b'], values, getId })).toEqual([
        values[1],
        values[0],
        values[2],
      ]);
    });
  });

  describe('reorderIds', () => {
    it('slots the visible ids into the stored order around hidden ones', () => {
      expect(reorderIds({ visibleIds: ['c', 'a'], currentOrder: ['a', 'b', 'c'] })).toEqual([
        'c',
        'b',
        'a',
      ]);
    });

    it('adds visible ids that were not stored yet at the end', () => {
      expect(reorderIds({ visibleIds: ['b', 'a', 'd'], currentOrder: ['a', 'b'] })).toEqual([
        'b',
        'a',
        'd',
      ]);
    });
  });
});
