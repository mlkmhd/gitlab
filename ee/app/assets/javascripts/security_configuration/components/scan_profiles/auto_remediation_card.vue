<script>
import { uniqueId } from 'lodash-es';
import { GlButton, GlEmptyState, GlIcon, GlPopover } from '@gitlab/ui';
import EMPTY_STATE_SVG from '@gitlab/svgs/dist/illustrations/empty-state/empty-secure-md.svg?url';
import { s__ } from '~/locale';

export default {
  name: 'AutoRemediationCard',
  components: {
    GlButton,
    GlEmptyState,
    GlIcon,
    GlPopover,
  },
  props: {
    profile: {
      type: Object,
      required: false,
      default: null,
    },
    canApplyProfiles: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['select-profile', 'view-profile'],
  data() {
    return {
      popoverId: uniqueId('auto-remediation-profile-info-'),
    };
  },
  methods: {
    // eslint-disable-next-line vue/no-unused-properties -- called through a ref by the section
    focusProfileLink() {
      this.$refs.profileLink?.$el.focus();
    },
  },
  EMPTY_STATE_SVG,
  PROFILE_INFO_TITLE: s__('SecurityConfiguration|What is a profile?'),
};
</script>

<template>
  <dl
    v-if="profile"
    class="gl-m-0 gl-flex gl-flex-col gl-gap-3"
    data-testid="auto-remediation-attached"
  >
    <div class="gl-flex gl-items-baseline gl-gap-5">
      <dt class="gl-flex gl-w-20 gl-shrink-0 gl-items-center gl-font-normal gl-text-subtle">
        {{ s__('SecurityConfiguration|Profile') }}
        <gl-icon
          :id="popoverId"
          name="information-o"
          :size="14"
          class="gl-ml-1"
          tabindex="0"
          :aria-label="$options.PROFILE_INFO_TITLE"
          data-testid="auto-remediation-profile-info"
        />
        <gl-popover
          :target="popoverId"
          placement="top"
          triggers="hover focus"
          :title="$options.PROFILE_INFO_TITLE"
        >
          {{
            s__(
              'SecurityConfiguration|A profile sets which capabilities run, on which severities, and how. Apply one profile to many projects to keep them consistent.',
            )
          }}
        </gl-popover>
      </dt>
      <dd class="gl-m-0 gl-w-3/5" data-testid="auto-remediation-profile-name">
        <gl-button
          ref="profileLink"
          variant="link"
          data-testid="auto-remediation-profile-link"
          @click="$emit('view-profile')"
        >
          {{ profile.name }}
        </gl-button>
      </dd>
    </div>
    <div class="gl-flex gl-items-baseline gl-gap-5">
      <dt class="gl-w-20 gl-shrink-0 gl-font-normal gl-text-subtle">
        {{ s__('SecurityConfiguration|Description') }}
      </dt>
      <dd class="gl-m-0 gl-w-3/5" data-testid="auto-remediation-profile-description">
        {{ profile.description }}
      </dd>
    </div>
  </dl>

  <gl-empty-state
    v-else
    :svg-path="$options.EMPTY_STATE_SVG"
    :title="s__('SecurityConfiguration|No profile applied')"
    :description="
      s__(
        'SecurityConfiguration|Apply a profile to choose how GitLab triages and fixes vulnerabilities in this project.',
      )
    "
    data-testid="auto-remediation-empty"
  >
    <template v-if="canApplyProfiles" #actions>
      <gl-button
        variant="confirm"
        data-testid="auto-remediation-button"
        @click="$emit('select-profile')"
      >
        {{ s__('SecurityConfiguration|Apply profile') }}
      </gl-button>
    </template>
  </gl-empty-state>
</template>
