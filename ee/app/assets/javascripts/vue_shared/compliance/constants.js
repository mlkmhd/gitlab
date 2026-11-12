import { s__ } from '~/locale';

export const COMPLIANCE_STATUS_OPTIONS = [
  {
    value: 'detected',
    text: s__('ComplianceViolation|Detected'),
  },
  {
    value: 'dismissed',
    text: s__('ComplianceViolation|Dismissed'),
  },
  {
    value: 'in_review',
    text: s__('ComplianceViolation|In review'),
  },
  {
    value: 'resolved',
    text: s__('ComplianceViolation|Resolved'),
  },
];
