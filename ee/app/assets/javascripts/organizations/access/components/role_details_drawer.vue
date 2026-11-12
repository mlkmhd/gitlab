<script>
import { GlAvatarLabeled, GlAvatarLink, GlButton, GlDrawer, GlIcon } from '@gitlab/ui';
import { helpPagePath } from '~/helpers/help_page_helper';
import { DRAWER_Z_INDEX } from '~/lib/utils/constants';
import { getContentWrapperHeight } from '~/lib/utils/dom_utils';
import RoleSelector from '~/members/components/role_selector.vue';
import { ACCESS_SUMMARY_I18N } from '../constants';

export default {
  name: 'OrganizationAccessRoleDetailsDrawer',
  components: {
    GlAvatarLabeled,
    GlAvatarLink,
    GlButton,
    GlDrawer,
    GlIcon,
    RoleSelector,
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
  emits: ['close', 'update-role'],
  data() {
    return {
      selectedRoleValue: null,
    };
  },
  computed: {
    roleItems() {
      return this.resource.roles.map(({ value, text, description }) => ({
        value,
        text,
        description,
      }));
    },
    roles() {
      return { formatted: this.roleItems, flatten: this.roleItems };
    },
    selectedRole() {
      return this.resource.roles.find(({ value }) => value === this.selectedRoleValue);
    },
    isRoleChanged() {
      return Boolean(this.member) && this.selectedRoleValue !== this.member.role;
    },
  },
  watch: {
    member: {
      immediate: true,
      // The parent rebuilds row objects on every list change, so reset only when
      // the member or their saved role changes, not on every new object.
      handler(member, previous) {
        if (member?.assignee.id !== previous?.assignee.id || member?.role !== previous?.role) {
          this.selectedRoleValue = member?.role ?? null;
        }
      },
    },
  },
  methods: {
    onRoleInput({ value }) {
      this.selectedRoleValue = value;
    },
    onUpdateRole() {
      this.$emit('update-role', { member: this.member, role: this.selectedRoleValue });
    },
    onCancel() {
      this.selectedRoleValue = this.member.role;
    },
  },
  i18n: ACCESS_SUMMARY_I18N,
  avatarSize: 48,
  roleToggleId: 'organization-access-role-details-role-toggle',
  permissionsHelpPath: helpPagePath('user/permissions'),
  getContentWrapperHeight,
  DRAWER_Z_INDEX,
};
</script>

<template>
  <!-- Mounted on each open because GlDrawer reads its footer slot only once. -->
  <gl-drawer
    v-if="member"
    :header-height="$options.getContentWrapperHeight()"
    :z-index="$options.DRAWER_Z_INDEX"
    header-sticky
    open
    class="gl-overscroll-contain"
    @close="$emit('close')"
  >
    <template #title>
      <h2 class="gl-m-0 gl-text-size-h2">{{ s__('OrganizationAccess|Role details') }}</h2>
    </template>

    <!-- A single root keeps the drawer from padding and bordering each section. -->
    <div>
      <h3 class="gl-mb-3 gl-mt-0 gl-text-base">{{ s__('OrganizationAccess|Account') }}</h3>
      <gl-avatar-link :href="member.assignee.webPath" data-testid="drawer-avatar-link">
        <gl-avatar-labeled
          :size="$options.avatarSize"
          :src="member.assignee.avatarUrl"
          :entity-name="member.assignee.name"
          :label="member.assignee.name"
          :sub-label="`@${member.assignee.username}`"
        />
      </gl-avatar-link>

      <hr />

      <dl class="gl-mb-0">
        <dt class="gl-mb-3">
          <label :for="$options.roleToggleId" class="gl-mb-0">{{
            s__('OrganizationAccess|Role')
          }}</label>
        </dt>
        <dd>
          <role-selector
            :roles="roles"
            :value="selectedRole"
            :toggle-id="$options.roleToggleId"
            :header-text="s__('OrganizationAccess|Select a role')"
            @input="onRoleInput"
          />
        </dd>

        <template v-if="selectedRole">
          <dt class="gl-mb-3 gl-mt-6">{{ s__('OrganizationAccess|Description') }}</dt>
          <dd data-testid="drawer-role-description">{{ selectedRole.detailedDescription }}</dd>

          <dt class="gl-mb-3 gl-mt-6">{{ s__('OrganizationAccess|Permission summary') }}</dt>
          <dd class="gl-mb-0">
            <ul class="gl-mb-4 gl-list-none gl-p-0" data-testid="drawer-permission-summary">
              <li
                v-for="{ text, allowed } in selectedRole.accessSummary"
                :key="text"
                class="gl-mb-3 gl-flex gl-gap-3 last:gl-mb-0"
              >
                <gl-icon
                  :name="allowed ? 'check' : 'close'"
                  :aria-label="allowed ? $options.i18n.allowed : $options.i18n.notAllowed"
                  class="gl-shrink-0"
                />
                <span>{{ text }}</span>
              </li>
            </ul>
            <gl-button
              :href="$options.permissionsHelpPath"
              icon="external-link"
              variant="link"
              target="_blank"
              data-testid="view-permissions-button"
            >
              {{ s__('OrganizationAccess|View permissions') }}
            </gl-button>
          </dd>
        </template>
      </dl>
    </div>

    <template #footer>
      <div v-if="isRoleChanged">
        <gl-button variant="confirm" data-testid="update-role-button" @click="onUpdateRole">
          {{ s__('OrganizationAccess|Update role') }}
        </gl-button>
        <gl-button class="gl-ml-2" data-testid="cancel-button" @click="onCancel">
          {{ __('Cancel') }}
        </gl-button>
      </div>
    </template>
  </gl-drawer>
</template>
