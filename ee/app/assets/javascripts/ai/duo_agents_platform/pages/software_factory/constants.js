import { s__ } from '~/locale';

export const SOFTWARE_FACTORY_TITLE = s__('DapSoftwareFactory|Software factory');

export const STAGE_TRIAGE = 'triage';
export const STAGE_PLAN = 'plan';
export const STAGE_BUILD = 'build';
export const STAGE_VERIFY = 'verify';
export const STAGE_REVIEW = 'review';
export const STAGE_SHIP = 'ship';

// The order of the stages in the configuration file, and on the page.
export const STAGES = [
  STAGE_TRIAGE,
  STAGE_PLAN,
  STAGE_BUILD,
  STAGE_VERIFY,
  STAGE_REVIEW,
  STAGE_SHIP,
];

export const MODE_AUTOMATED = 'automated';
export const MODE_MANUAL = 'manual';

// The foundational flow a stage runs by default, when the project has it enabled.
export const STAGE_DEFAULT_FLOW_REFERENCES = {
  [STAGE_PLAN]: 'workplan/v1',
  [STAGE_BUILD]: 'developer/v1',
  [STAGE_REVIEW]: 'developer/v1',
};

export const STAGE_ICONS = {
  [STAGE_TRIAGE]: 'label',
  [STAGE_PLAN]: 'planning',
  [STAGE_BUILD]: 'code',
  [STAGE_VERIFY]: 'check-circle',
  [STAGE_REVIEW]: 'merge-request',
  [STAGE_SHIP]: 'rocket',
};

export const STAGE_LABELS = {
  [STAGE_TRIAGE]: s__('DapSoftwareFactory|Triage'),
  [STAGE_PLAN]: s__('DapSoftwareFactory|Plan'),
  [STAGE_BUILD]: s__('DapSoftwareFactory|Build'),
  [STAGE_VERIFY]: s__('DapSoftwareFactory|Verify'),
  [STAGE_REVIEW]: s__('DapSoftwareFactory|Review'),
  [STAGE_SHIP]: s__('DapSoftwareFactory|Ship'),
};

// Mirrors Ai::FlowTriggers::FixLoop::Config::DEFAULT_MAX_FIX_RUNS.
export const DEFAULT_MAX_FIX_RUNS = 3;
