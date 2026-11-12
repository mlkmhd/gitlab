<script>
import { GlTable, GlButton, GlModal, GlModalDirective, GlSprintf } from '@gitlab/ui';
import { mapState, mapActions } from 'pinia';
import CrudComponent from '~/vue_shared/components/crud_component.vue';
import { __, s__ } from '~/locale';
import { useDeployFreeze } from '../store';

export default {
  name: 'DeployFreezeTable',
  fields: [
    {
      key: 'freezeStart',
      label: s__('DeployFreeze|Freeze start'),
      tdClass: '!gl-align-middle',
    },
    {
      key: 'freezeEnd',
      label: s__('DeployFreeze|Freeze end'),
      tdClass: '!gl-align-middle',
    },
    {
      key: 'cronTimezone',
      label: s__('DeployFreeze|Time zone'),
      tdClass: '!gl-align-middle',
    },
    {
      key: 'actions',
      label: __('Actions'),
      thAlignRight: true,
    },
  ],
  modal: {
    id: 'deleteFreezePeriodModal',
    actionPrimary: {
      text: s__('DeployFreeze|Delete freeze period'),
      attributes: { variant: 'danger', 'data-testid': 'modal-confirm' },
    },
    actionSecondary: {
      text: __('Cancel'),
      attributes: { variant: 'default' },
    },
  },
  components: {
    CrudComponent,
    GlTable,
    GlButton,
    GlModal,
    GlSprintf,
  },
  directives: {
    GlModal: GlModalDirective,
  },
  data() {
    return {
      freezePeriodToDelete: null,
    };
  },
  computed: {
    ...mapState(useDeployFreeze, ['freezePeriods']),
  },
  mounted() {
    this.fetchFreezePeriods();
  },
  methods: {
    ...mapActions(useDeployFreeze, ['fetchFreezePeriods', 'setFreezePeriod', 'deleteFreezePeriod']),
    handleDeleteFreezePeriod(freezePeriod) {
      this.freezePeriodToDelete = freezePeriod;
    },
    confirmDeleteFreezePeriod() {
      this.deleteFreezePeriod(this.freezePeriodToDelete);
      this.freezePeriodToDelete = null;
    },
  },
};
</script>

<template>
  <crud-component
    :title="s__('DeployFreeze|Deploy freezes')"
    icon="deployments"
    :count="freezePeriods.length"
  >
    <template #actions>
      <gl-button v-gl-modal.deploy-freeze-modal size="small" data-testid="add-deploy-freeze">{{
        s__('DeployFreeze|Add deploy freeze')
      }}</gl-button>
    </template>

    <gl-table
      data-testid="deploy-freeze-table"
      :items="freezePeriods"
      :fields="$options.fields"
      show-empty
      stacked="md"
    >
      <template #cell(cronTimezone)="{ item }">
        {{ item.cronTimezone.formattedTimezone }}
      </template>
      <template #cell(actions)="{ item }">
        <div class="-gl-mb-2 -gl-mt-2 gl-flex gl-justify-end gl-gap-2">
          <gl-button
            v-gl-modal.deploy-freeze-modal
            icon="pencil"
            category="tertiary"
            data-testid="edit-deploy-freeze"
            :aria-label="__('Edit deploy freeze')"
            @click="setFreezePeriod(item)"
          />
          <gl-button
            v-gl-modal="$options.modal.id"
            category="tertiary"
            icon="remove"
            :aria-label="$options.modal.actionPrimary.text"
            :loading="item.isDeleting"
            data-testid="delete-deploy-freeze"
            @click="handleDeleteFreezePeriod(item)"
          />
        </div>
      </template>
      <template #empty>
        <p data-testid="empty-freeze-periods" class="gl-mb-0 gl-text-center gl-text-subtle">
          <gl-sprintf
            :message="
              s__(
                'DeployFreeze|No deploy freezes exist for this project. To add one, select %{strongStart}Add deploy freeze%{strongEnd} above.',
              )
            "
          >
            <template #strong="{ content }">
              {{ content }}
            </template>
          </gl-sprintf>
        </p>
      </template>
    </gl-table>
    <gl-modal
      :title="s__('DeployFreeze|Delete deploy freeze?')"
      :modal-id="$options.modal.id"
      :action-primary="$options.modal.actionPrimary"
      :action-secondary="$options.modal.actionSecondary"
      static
      @primary="confirmDeleteFreezePeriod"
    >
      <template v-if="freezePeriodToDelete">
        <gl-sprintf
          :message="
            s__(
              'DeployFreeze|Deploy freeze from %{start} to %{end} in %{timezone} will be removed. Are you sure?',
            )
          "
        >
          <template #start>
            <code>{{ freezePeriodToDelete.freezeStart }}</code>
          </template>
          <template #end>
            <code>{{ freezePeriodToDelete.freezeEnd }}</code>
          </template>
          <template #timezone>{{ freezePeriodToDelete.cronTimezone.formattedTimezone }}</template>
        </gl-sprintf>
      </template>
    </gl-modal>
  </crud-component>
</template>
