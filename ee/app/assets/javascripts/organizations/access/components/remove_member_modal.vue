<script>
import { GlFormRadio, GlFormRadioGroup, GlModal, GlSprintf } from '@gitlab/ui';
import { __, n__, s__, sprintf } from '~/locale';

const REMOVAL_SCOPE_DIRECT_AND_INHERITED = 'direct_and_inherited';
const REMOVAL_SCOPE_INHERITED_ONLY = 'inherited_only';

export default {
  name: 'OrganizationAccessRemoveMemberModal',
  components: {
    GlFormRadio,
    GlFormRadioGroup,
    GlModal,
    GlSprintf,
  },
  props: {
    resource: {
      type: Object,
      required: true,
    },
    member: {
      type: Object,
      required: false,
      default: null,
    },
  },
  emits: ['close', 'remove'],
  data() {
    return {
      removalScope: null,
    };
  },
  computed: {
    directRepositoryCount() {
      // Filled in MR 2 of https://gitlab.com/gitlab-org/gitlab/-/work_items/629711.
      // Until then the direct-access options stay dormant.
      return this.member?.directRepositoryCount || 0;
    },
    hasDirectAccess() {
      return this.directRepositoryCount > 0;
    },
    directAccessMessage() {
      return sprintf(
        n__(
          'OrganizationAccess|This user has direct access to %{strongStart}%{count} repository%{strongEnd}.',
          'OrganizationAccess|This user has direct access to %{strongStart}%{count} repositories%{strongEnd}.',
          this.directRepositoryCount,
        ),
        { count: this.directRepositoryCount },
      );
    },
    inheritedOnlyHelp() {
      return sprintf(
        n__(
          'OrganizationAccess|User keeps direct access to %{count} repository',
          'OrganizationAccess|User keeps direct access to %{count} repositories',
          this.directRepositoryCount,
        ),
        { count: this.directRepositoryCount },
      );
    },
    actionPrimary() {
      return {
        text: s__('OrganizationAccess|Remove member'),
        attributes: {
          variant: 'danger',
          disabled: this.hasDirectAccess && !this.removalScope,
        },
      };
    },
  },
  watch: {
    member() {
      this.removalScope = null;
    },
  },
  methods: {
    onPrimary() {
      this.$emit('remove', { member: this.member, removalScope: this.removalScope });
    },
  },
  modalId: 'organization-access-remove-member-modal',
  actionCancel: { text: __('Cancel') },
  REMOVAL_SCOPE_DIRECT_AND_INHERITED,
  REMOVAL_SCOPE_INHERITED_ONLY,
};
</script>

<template>
  <gl-modal
    :modal-id="$options.modalId"
    :visible="Boolean(member)"
    :title="s__('OrganizationAccess|Remove member')"
    :action-primary="actionPrimary"
    :action-cancel="$options.actionCancel"
    @primary="onPrimary"
    @hidden="$emit('close')"
  >
    <template v-if="member">
      <p :class="{ 'gl-mb-0': !hasDirectAccess }">
        <gl-sprintf
          :message="
            s__('OrganizationAccess|Are you sure you want to remove %{name} from %{resource}?')
          "
        >
          <template #name>
            <strong>{{ member.assignee.name }}</strong>
          </template>
          <template #resource>{{ resource.label }}</template>
        </gl-sprintf>
      </p>
      <template v-if="hasDirectAccess">
        <p data-testid="direct-access-message">
          <gl-sprintf :message="directAccessMessage">
            <template #strong="{ content }">
              <strong>{{ content }}</strong>
            </template>
          </gl-sprintf>
        </p>
        <gl-form-radio-group
          v-model="removalScope"
          :aria-label="s__('OrganizationAccess|Choose which access to remove')"
        >
          <gl-form-radio :value="$options.REMOVAL_SCOPE_DIRECT_AND_INHERITED">
            {{ s__('OrganizationAccess|Remove direct and inherited access') }}
            <template #help>
              <gl-sprintf
                :message="
                  s__('OrganizationAccess|User access is removed everywhere in %{resource}')
                "
              >
                <template #resource>{{ resource.label }}</template>
              </gl-sprintf>
            </template>
          </gl-form-radio>
          <gl-form-radio :value="$options.REMOVAL_SCOPE_INHERITED_ONLY">
            {{ s__('OrganizationAccess|Remove only inherited access') }}
            <template #help>{{ inheritedOnlyHelp }}</template>
          </gl-form-radio>
        </gl-form-radio-group>
      </template>
    </template>
  </gl-modal>
</template>
