<script>
import { GlIcon } from '@gitlab/ui';
import { s__ } from '~/locale';

const ROLE_PERMISSION_SUMMARIES = {
  ARTIFACT_VIEWER: {
    allowed: [
      s__('ArtifactRegistry|View the list of artifacts in this repository'),
      s__('ArtifactRegistry|View artifact metadata (tags, versions, size, upload date)'),
      s__(
        'ArtifactRegistry|Download or pull artifacts (for example, Docker pulls or package installs)',
      ),
    ],
    denied: [
      s__('ArtifactRegistry|Push, upload, or delete artifacts'),
      s__('ArtifactRegistry|Manage roles and settings'),
    ],
  },
  ARTIFACT_CONTRIBUTOR: {
    allowed: [
      s__('ArtifactRegistry|Everything an Artifact Viewer can do'),
      s__('ArtifactRegistry|Push and upload artifacts'),
    ],
    denied: [
      s__('ArtifactRegistry|Delete artifacts'),
      s__('ArtifactRegistry|Manage roles and settings'),
    ],
  },
  ARTIFACT_MANAGER: {
    allowed: [
      s__('ArtifactRegistry|Everything an Artifact Contributor can do'),
      s__('ArtifactRegistry|Delete artifacts'),
      s__('ArtifactRegistry|Configure this repository'),
    ],
    denied: [s__('ArtifactRegistry|Delete this repository'), s__('ArtifactRegistry|Manage roles')],
  },
  ARTIFACT_ADMIN: {
    allowed: [
      s__('ArtifactRegistry|Everything an Artifact Manager can do'),
      s__('ArtifactRegistry|Delete this repository'),
      s__('ArtifactRegistry|Add members to this repository and change their roles'),
      s__('ArtifactRegistry|Remove members from this repository'),
    ],
    denied: [],
  },
};

export default {
  name: 'ArtifactRegistryRoleAccessSummary',
  components: {
    GlIcon,
  },
  props: {
    role: {
      type: String,
      required: true,
    },
  },
  computed: {
    permissions() {
      const { allowed, denied } = ROLE_PERMISSION_SUMMARIES[this.role];
      const { i18n } = this.$options;

      return [
        ...allowed.map((text) => ({
          text,
          testId: 'allowed-permission',
          icon: 'check',
          srLabel: i18n.allowed,
        })),
        ...denied.map((text) => ({
          text,
          testId: 'denied-permission',
          icon: 'close',
          srLabel: i18n.denied,
        })),
      ];
    },
  },
  i18n: {
    title: s__('ArtifactRegistry|Permission summary'),
    allowed: s__('ArtifactRegistry|Allowed:'),
    denied: s__('ArtifactRegistry|Not allowed:'),
  },
};
</script>

<template>
  <div>
    <h3 class="gl-heading-5 gl-mb-3">{{ $options.i18n.title }}</h3>
    <ul class="gl-m-0 gl-flex gl-list-none gl-flex-col gl-gap-2 gl-p-0">
      <li
        v-for="{ text, testId, icon, srLabel } in permissions"
        :key="text"
        class="gl-flex gl-items-center gl-gap-2 gl-text-sm gl-text-subtle"
        :data-testid="testId"
      >
        <gl-icon :name="icon" variant="subtle" />
        <span class="gl-sr-only">{{ srLabel }}</span>
        {{ text }}
      </li>
    </ul>
  </div>
</template>
