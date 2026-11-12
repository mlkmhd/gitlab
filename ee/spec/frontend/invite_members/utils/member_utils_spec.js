import { baseBindingAttributes } from 'ee/invite_members/utils/member_utils';

describe('baseBindingAttributes', () => {
  it.each([
    [true, { 'has-error-during-invite': true }],
    [false, { 'has-error-during-invite': false }],
  ])('returns correct attributes', (hasInvalidMembers, expected) => {
    expect(baseBindingAttributes(hasInvalidMembers)).toEqual(expected);
  });
});
