<script>
import {
  GlDropdown,
  GlDropdownDivider,
  GlDropdownItem,
  GlFormGroup,
  GlFormInput,
  GlIcon,
  GlModal,
  GlSprintf,
  GlModalDirective,
  GlToastMixin,
} from '@gitlab/ui';
import { s__, sprintf } from '~/locale';
import glFeatureFlagsMixin from '~/vue_shared/mixins/gl_feature_flags_mixin';
import getStatesQuery from '../graphql/queries/get_states.query.graphql';
import addDataToState from '../graphql/mutations/add_data_to_state.mutation.graphql';
import deletePermanentlyState from '../graphql/mutations/delete_permanently_state.mutation.graphql';
import lockState from '../graphql/mutations/lock_state.mutation.graphql';
import removeState from '../graphql/mutations/remove_state.mutation.graphql';
import restoreState from '../graphql/mutations/restore_state.mutation.graphql';
import unlockState from '../graphql/mutations/unlock_state.mutation.graphql';
import InitCommandModal from './init_command_modal.vue';

export default {
  name: 'StatesTableActions',
  components: {
    GlDropdown,
    GlDropdownDivider,
    GlDropdownItem,
    GlFormGroup,
    GlFormInput,
    GlIcon,
    GlModal,
    GlSprintf,
    InitCommandModal,
  },
  directives: {
    GlModalDirective,
  },
  mixins: [GlToastMixin, glFeatureFlagsMixin()],
  props: {
    state: {
      required: true,
      type: Object,
    },
    terraformAdmin: {
      required: true,
      type: Boolean,
    },
  },
  data() {
    return {
      showRemoveModal: false,
      removeConfirmText: '',
      showCommandModal: false,
    };
  },
  i18n: {
    deletePermanently: s__('Terraform|Delete permanently'),
  },
  computed: {
    cancelModalProps() {
      return {
        text: s__('Terraform|Cancel'),
        attributes: {},
      };
    },
    disableModalSubmit() {
      return this.removeConfirmText !== this.state.name;
    },
    delayedDeletionEnabled() {
      return Boolean(this.glFeatures.terraformStateDelayedDeletion);
    },
    loading() {
      return this.state.loadingLock || this.state.loadingRemove || this.state.loadingRestore;
    },
    modalHeader() {
      return this.isPendingDeletion
        ? s__('Terraform|Are you sure you want to remove the Terraform State %{name} permanently?')
        : s__('Terraform|Are you sure you want to remove the Terraform State %{name}?');
    },
    modalBody() {
      if (this.isPendingDeletion) {
        return s__(
          'Terraform|This will permanently delete the state file %{name} and all its versions. This action cannot be undone.',
        );
      }

      return this.delayedDeletionEnabled && this.state.latestVersion
        ? s__(
            'Terraform|You are about to remove the state file %{name}. The state will be scheduled for deletion. You can restore it from the state list within 7 days.',
          )
        : s__(
            'Terraform|You are about to remove the state file %{name}. This will permanently delete all the State versions and history. The infrastructure provisioned previously will remain intact, and only the state file with all its versions will be removed. This action cannot be undone.',
          );
    },
    isPendingDeletion() {
      return this.delayedDeletionEnabled && Boolean(this.state.deletedAt);
    },
    showActionsMenu() {
      return this.terraformAdmin || !this.isPendingDeletion;
    },
    primaryModalProps() {
      return {
        text: this.isPendingDeletion
          ? this.$options.i18n.deletePermanently
          : s__('Terraform|Remove'),
        attributes: {
          disabled: this.disableModalSubmit,
          variant: 'danger',
          type: 'submit',
          form: this.$options.removeFormId,
        },
      };
    },
    commandModalId() {
      return `init-command-modal-${this.state.name}`;
    },
    modalInputId() {
      return `terraform-state-remove-input-${this.state.name}`;
    },
  },
  methods: {
    hideModal() {
      this.showRemoveModal = false;
      this.removeConfirmText = '';
    },
    lock() {
      this.updateStateCache({
        _showDetails: false,
        errorMessages: [],
        loadingLock: true,
        loadingRemove: false,
      });

      this.stateActionMutation(lockState);
    },
    unlock() {
      this.updateStateCache({
        _showDetails: false,
        errorMessages: [],
        loadingLock: true,
        loadingRemove: false,
      });

      this.stateActionMutation(unlockState);
    },
    updateStateCache(newData) {
      this.$apollo.mutate({
        mutation: addDataToState,
        variables: {
          terraformState: {
            ...this.state,
            ...newData,
          },
        },
      });
    },
    remove() {
      if (!this.disableModalSubmit) {
        this.hideModal();

        this.updateStateCache({
          _showDetails: false,
          errorMessages: [],
          loadingLock: false,
          loadingRemove: true,
        });

        if (this.isPendingDeletion) {
          // The backend deletes asynchronously, so a refetch can still return this state.
          // Drop it from the cached list instead.
          this.stateActionMutation(
            deletePermanentlyState,
            sprintf(s__('Terraform|%{name} permanently deleted'), { name: this.state.name }),
            { update: this.removeStateFromCache },
          );
        } else {
          this.stateActionMutation(
            removeState,
            sprintf(s__('Terraform|%{name} successfully removed'), { name: this.state.name }),
          );
        }
      }
    },
    restore() {
      this.updateStateCache({
        _showDetails: false,
        errorMessages: [],
        loadingLock: false,
        loadingRemove: false,
        loadingRestore: true,
      });

      this.stateActionMutation(
        restoreState,
        sprintf(s__('Terraform|%{name} successfully restored'), { name: this.state.name }),
      );
    },
    removeStateFromCache(cache, { data }) {
      if (data?.terraformStateDeletePermanently?.errors?.length) return;

      const projectRefs = [];
      cache.modify({
        fields: {
          project: (projectRef) => {
            projectRefs.push(projectRef);
            return projectRef;
          },
        },
      });

      projectRefs.forEach((projectRef) => {
        cache.modify({
          id: cache.identify(projectRef),
          fields: {
            terraformStates: (connection, { readField }) => {
              const nodes = connection.nodes.filter(
                (node) => readField('id', node) !== this.state.id,
              );

              if (nodes.length === connection.nodes.length) return connection;

              return { ...connection, count: connection.count - 1, nodes };
            },
          },
        });
      });
    },
    stateActionMutation(
      mutation,
      successMessage = null,
      mutationOptions = { refetchQueries: [getStatesQuery], awaitRefetchQueries: true },
    ) {
      let errorMessages = [];

      this.$apollo
        .mutate({
          mutation,
          variables: {
            stateID: this.state.id,
          },
          notifyOnNetworkStatusChange: true,
          ...mutationOptions,
        })
        .then(({ data }) => {
          errorMessages =
            data?.terraformStateDelete?.errors ||
            data?.terraformStateLock?.errors ||
            data?.terraformStateUnlock?.errors ||
            data?.terraformStateRestore?.errors ||
            data?.terraformStateDeletePermanently?.errors ||
            [];

          if (errorMessages.length === 0 && successMessage) {
            this.$toast.show(successMessage);
          }
        })
        .catch(() => {
          errorMessages = [s__('Terraform|An error occurred while changing the state file')];
        })
        .finally(() => {
          this.updateStateCache({
            _showDetails: Boolean(errorMessages.length),
            errorMessages,
            loadingLock: false,
            loadingRemove: false,
            loadingRestore: false,
          });
        });
    },
    copyInitCommand() {
      this.showCommandModal = true;
    },
  },
  removeFormId: 'remove-state-form',
};
</script>

<template>
  <div>
    <gl-dropdown
      v-if="showActionsMenu"
      icon="ellipsis_v"
      category="tertiary"
      right
      :data-testid="`terraform-state-actions-${state.name}`"
      :disabled="loading"
      toggle-class="!gl-px-3 !gl-shadow-none"
    >
      <template #button-content>
        <gl-icon class="gl-mr-0" name="ellipsis_v" />
      </template>

      <template v-if="isPendingDeletion">
        <gl-dropdown-item data-testid="terraform-state-restore" @click="restore">
          {{ s__('Terraform|Restore') }}
        </gl-dropdown-item>

        <gl-dropdown-divider />

        <gl-dropdown-item
          data-testid="terraform-state-delete-permanently"
          @click="showRemoveModal = true"
        >
          <span class="gl-text-danger">{{ $options.i18n.deletePermanently }}</span>
        </gl-dropdown-item>
      </template>

      <template v-else>
        <gl-dropdown-item
          v-gl-modal-directive="commandModalId"
          data-testid="terraform-state-copy-init-command"
          @click="copyInitCommand"
        >
          {{ s__('Terraform|Copy Terraform init command') }}
        </gl-dropdown-item>

        <gl-dropdown-item
          v-if="state.latestVersion"
          data-testid="terraform-state-download"
          :download="`${state.name}.json`"
          :href="state.latestVersion.downloadPath"
        >
          {{ s__('Terraform|Download JSON') }}
        </gl-dropdown-item>

        <template v-if="terraformAdmin">
          <gl-dropdown-item
            v-if="state.lockedAt"
            data-testid="terraform-state-unlock"
            @click="unlock"
          >
            {{ s__('Terraform|Unlock') }}
          </gl-dropdown-item>

          <gl-dropdown-item v-else data-testid="terraform-state-lock" @click="lock">
            {{ s__('Terraform|Lock') }}
          </gl-dropdown-item>

          <gl-dropdown-divider />

          <gl-dropdown-item data-testid="terraform-state-remove" @click="showRemoveModal = true">
            <span class="gl-text-danger">{{ s__('Terraform|Remove') }}</span>
          </gl-dropdown-item>
        </template>
      </template>
    </gl-dropdown>

    <gl-modal
      :modal-id="`terraform-state-actions-remove-modal-${state.name}`"
      :visible="showRemoveModal"
      :action-primary="primaryModalProps"
      :action-cancel="cancelModalProps"
      @ok="remove"
      @cancel="hideModal"
      @close="hideModal"
      @hide="hideModal"
    >
      <template #modal-title>
        <gl-sprintf :message="modalHeader">
          <template #name>
            <span>{{ state.name }}</span>
          </template>
        </gl-sprintf>
      </template>

      <form :id="$options.removeFormId" @submit.prevent="remove">
        <p>
          <gl-sprintf :message="modalBody">
            <template #name>
              <code>{{ state.name }}</code>
            </template>
          </gl-sprintf>
        </p>

        <gl-form-group :label-for="modalInputId">
          <template #label>
            <gl-sprintf
              :message="
                s__('Terraform|To remove the State file and its versions, type %{name} to confirm:')
              "
            >
              <template #name>
                <code>{{ state.name }}</code>
              </template>
            </gl-sprintf>
          </template>
          <gl-form-input :id="modalInputId" ref="input" v-model="removeConfirmText" type="text" />
        </gl-form-group>
      </form>
    </gl-modal>

    <init-command-modal
      v-if="showCommandModal"
      :modal-id="commandModalId"
      :state-name="state.name"
    />
  </div>
</template>
