<script>
import { GlButton } from '@gitlab/ui';

const FEEDBACK_ISSUE_URL = 'https://gitlab.com/gitlab-org/gitlab/-/issues/517386';

export default {
  name: 'DuoCodeReviewFeedbackLink',
  components: {
    GlButton,
  },
  FEEDBACK_ISSUE_URL,
};
</script>

<template>
  <span>
    <span class="gl-mx-2" aria-hidden="true">&middot;</span>
    <gl-button variant="link" :href="$options.FEEDBACK_ISSUE_URL">
      {{ __('Leave feedback') }}
    </gl-button>
  </span>
</template>
