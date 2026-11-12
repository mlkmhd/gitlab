// Each key is a category of console message the integration lane tolerates.
// A category that keeps growing signals a missing capability in our test setup.
export const CONSOLE_IGNORES = {
  'apollo-cache-data-may-be-lost': {
    pattern: /^Cache data may be lost when replacing the \w+ field/,
    reason:
      'The Query field has no merge function, so Apollo warns when a second query replaces it.',
    files: [
      'ee/spec/frontend/integration/ai_duo_panel/duo_agentic_chat/additional_context_spec.js',
      'ee/spec/frontend/integration/ai_duo_panel/duo_agentic_chat/stream_adoption_spec.js',
      'ee/spec/frontend/integration/ci/admin_jobs/admin_jobs_spec.js',
    ],
  },
};
