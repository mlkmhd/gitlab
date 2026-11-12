import { parse, stringify } from 'yaml';

// Like the backend's Psych, keep the last of duplicate keys and resolve `<<` merge keys.
export const parsePolicyYaml = (manifest) => parse(manifest, { uniqueKeys: false, merge: true });

// The backend reads policies as YAML 1.1, where unquoted `on`, `yes` or `10:30` are not strings.
export const stringifyPolicyYaml = (value) =>
  stringify(value, { version: '1.1', singleQuote: true, aliasDuplicateObjects: false });
