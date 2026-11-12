import { s__ } from '~/locale';

// Mirrors the `SecurityAiFlowFeedbackSentiment` GraphQL enum.
export const SENTIMENT = {
  AGREE: 'AGREE',
  DISAGREE: 'DISAGREE',
};

// Values mirror the `SecurityAiFlowFeedbackReason` GraphQL enum.
export const SAST_FP_REASONS = [
  { value: 'VERDICT_WRONG', text: s__('SecurityAiFlowFeedback|Verdict is wrong') },
  { value: 'IGNORED_DATA_FLOW', text: s__('SecurityAiFlowFeedback|Missed data flow') },
  {
    value: 'EXPLANATION_INACCURATE',
    text: s__('SecurityAiFlowFeedback|Explanation is inaccurate'),
  },
  {
    value: 'CONFIDENCE_MISCALIBRATED',
    text: s__('SecurityAiFlowFeedback|Confidence level is off'),
  },
  { value: 'OTHER', text: s__('SecurityAiFlowFeedback|Other') },
];
