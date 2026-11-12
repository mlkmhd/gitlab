import { parsePolicyYaml, stringifyPolicyYaml } from 'ee/security_orchestration/policy_yaml';

describe('parsePolicyYaml', () => {
  it('keeps the last value of a duplicate key', () => {
    expect(parsePolicyYaml('name: first\nname: second')).toEqual({ name: 'second' });
  });

  it('resolves merge keys', () => {
    expect(
      parsePolicyYaml('base: &base\n  enabled: true\npolicy:\n  <<: *base\n  name: a'),
    ).toEqual({ base: { enabled: true }, policy: { enabled: true, name: 'a' } });
  });

  it('throws on invalid YAML', () => {
    expect(() => parsePolicyYaml('rules: [')).toThrow();
  });
});

describe('stringifyPolicyYaml', () => {
  it.each(['on', 'yes', 'no', '10:30', '1_000', '2026-01-01', ''])(
    'quotes "%s" so that a YAML 1.1 reader keeps it a string',
    (value) => {
      expect(stringifyPolicyYaml({ value })).toBe(`value: '${value}'\n`);
    },
  );

  it('writes a shared object out in full instead of as an alias', () => {
    const branches = ['main'];

    expect(stringifyPolicyYaml({ a: branches, b: branches })).toBe('a:\n  - main\nb:\n  - main\n');
  });

  it('leaves out a key whose value is undefined', () => {
    expect(stringifyPolicyYaml({ name: 'a', description: undefined })).toBe('name: a\n');
  });
});
