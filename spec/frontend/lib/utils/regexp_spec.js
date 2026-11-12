import { awsIamRoleArnRegex } from '~/lib/utils/regexp';

describe('Validates AWS Role ARN', () => {
  it('should return false for invalid AWS role arn', () => {
    expect(awsIamRoleArnRegex.test('arn:aws:iam::test:role/invalid-role')).toBe(false);
  });

  it('should return false for empty AWS role arn', () => {
    expect(awsIamRoleArnRegex.test('')).toBe(false);
  });

  it('should return false for null AWS role arn', () => {
    expect(awsIamRoleArnRegex.test(null)).toBe(false);
  });

  it('should return true for a valid AWS role arn', () => {
    expect(awsIamRoleArnRegex.test('arn:aws:iam::123456789012:role/valid-role')).toBe(true);
  });
});
