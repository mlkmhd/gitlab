const triagePreset = (id, posture) => ({
  id: `gid://gitlab/Security::ScanProfile/${id}`,
  name: `Triage and Remediation (${posture})`,
  description: `${posture} triage`,
  scanType: 'TRIAGE_AND_REMEDIATION',
  gitlabRecommended: true,
  triggers: [],
  projectCount: 0,
  triggerSettings: [],
  __typename: 'ScanProfileType',
});

export const conservativePreset = triagePreset(11, 'Conservative');
export const proactivePreset = triagePreset(12, 'Proactive');
export const standardPreset = triagePreset(13, 'Standard');

export const triagePresets = [conservativePreset, proactivePreset, standardPreset];
