import { rowKeyOf } from '~/glql/components/presenters/utils/row_key';

const dimensions = [{ key: 'Group' }, { key: 'language' }];

describe('rowKeyOf', () => {
  it('keys a row by the identity of each dimension value', () => {
    expect(
      rowKeyOf(
        { Group: { id: 'gid://gitlab/Group/2', fullName: 'A' }, language: 'ruby' },
        dimensions,
      ),
    ).toBe('["gid://gitlab/Group/2","ruby"]');
  });

  it('keys a NULL bucket like any other value', () => {
    expect(rowKeyOf({ Group: null, language: 'ruby' }, dimensions)).toBe('[null,"ruby"]');
  });

  it('keeps an absent value apart from a string that reads like one', () => {
    expect(rowKeyOf({ Group: 'null', language: 'ruby' }, dimensions)).not.toBe(
      rowKeyOf({ Group: null, language: 'ruby' }, dimensions),
    );
  });

  it('returns null for a row holding a value nothing can name', () => {
    expect(rowKeyOf({ Group: { fullName: 'A' }, language: 'ruby' }, dimensions)).toBeNull();
  });
});
