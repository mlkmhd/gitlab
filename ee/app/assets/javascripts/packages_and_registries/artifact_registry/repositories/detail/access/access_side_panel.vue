<script>
import { GlLink } from '@gitlab/ui';
import { uniqueId } from 'lodash-es';
import { MountingPortal } from 'portal-vue';
import { s__, sprintf } from '~/locale';
import DynamicPanel from '~/vue_shared/components/dynamic_panel.vue';
import AddMembersModal from './add_members_modal.vue';
import DirectMembersCard from './direct_members_card.vue';

export default {
  name: 'ArtifactRegistryAccessSidePanel',
  components: {
    AddMembersModal,
    DirectMembersCard,
    DynamicPanel,
    GlLink,
    MountingPortal,
  },
  inject: {
    organizationAccessPath: { default: null },
  },
  props: {
    open: {
      type: Boolean,
      required: true,
    },
    repositoryId: {
      type: String,
      required: true,
    },
    repositoryName: {
      type: String,
      required: true,
    },
    permissions: {
      type: Object,
      required: false,
      default: null,
    },
  },
  emits: ['close'],
  data() {
    return {
      headingId: uniqueId('access-side-panel-heading-'),
      showAddMembers: false,
      excludedMemberIds: [],
      addMembersTrigger: null,
    };
  },
  computed: {
    title() {
      return sprintf(
        s__('ArtifactRegistry|Access for %{name}'),
        { name: this.repositoryName },
        false,
      );
    },
  },
  watch: {
    open(open) {
      if (open) {
        this.focus();
      }
    },
  },
  mounted() {
    document.addEventListener('keydown', this.handleKeydown);
  },
  beforeDestroy() {
    document.removeEventListener('keydown', this.handleKeydown);
  },
  methods: {
    focus() {
      this.$nextTick(() => this.$refs.panel?.$el.focus());
    },
    hasPriorEscapeHandler() {
      const active = document.activeElement;

      return (
        document.body.classList.contains('modal-open') ||
        document.querySelector('.gl-drawer') != null ||
        active?.closest('.js-editor') != null ||
        active?.closest('[contenteditable]:not([contenteditable="false"])') != null ||
        active?.tagName === 'INPUT' ||
        active?.tagName === 'TEXTAREA'
      );
    },
    handleKeydown({ key }) {
      if (key === 'Escape' && this.open && !this.hasPriorEscapeHandler()) {
        this.$emit('close');
      }
    },
    openAddMembers({ trigger, memberIds }) {
      this.addMembersTrigger = trigger;
      this.excludedMemberIds = memberIds;
      this.showAddMembers = true;
    },
  },
};
</script>

<template>
  <mounting-portal v-if="open" mount-to="#contextual-panel-portal" append>
    <dynamic-panel
      ref="panel"
      role="region"
      :aria-labelledby="headingId"
      tabindex="-1"
      data-testid="access-side-panel"
      @close="$emit('close')"
    >
      <template #header>
        <h2 :id="headingId" class="panel-header-inner-text gl-m-0" data-testid="access-heading">
          {{ title }}
        </h2>
      </template>

      <div class="gl-my-5 gl-flex gl-flex-col gl-gap-5">
        <direct-members-card
          :repository-id="repositoryId"
          :permissions="permissions"
          @add-members="openAddMembers"
        />
        <div class="gl-flex gl-flex-col gl-items-start gl-gap-1">
          <p class="gl-mb-0 gl-text-subtle" data-testid="organization-access-note">
            {{
              s__(
                'ArtifactRegistry|Members with a role in Organization access also have access to this repository.',
              )
            }}
          </p>
          <gl-link
            v-if="organizationAccessPath"
            :href="organizationAccessPath"
            data-testid="organization-access-link"
          >
            {{ s__('ArtifactRegistry|Manage Organization access') }}
          </gl-link>
        </div>
      </div>

      <add-members-modal
        v-model="showAddMembers"
        :repository-id="repositoryId"
        :repository-name="repositoryName"
        :excluded-member-ids="excludedMemberIds"
        :return-focus="addMembersTrigger"
      />
    </dynamic-panel>
  </mounting-portal>
</template>
