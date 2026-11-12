<script>
import { GlButton, GlFormGroup, GlFormInput, GlFormTextarea } from '@gitlab/ui';
// eslint-disable-next-line no-restricted-imports
import { mapState, mapActions } from 'vuex';
import { uniqueId } from 'lodash-es';
import { __ } from '~/locale';
import RefSelector from '~/vue_shared/components/ref/components/ref_selector.vue';

export default {
  name: 'TagCreate',
  components: {
    GlButton,
    GlFormGroup,
    GlFormInput,
    GlFormTextarea,
    RefSelector,
  },
  model: {
    prop: 'value',
    event: 'change',
  },
  props: {
    value: { type: String, required: true },
  },
  emits: ['cancel', 'change', 'create'],
  data() {
    return {
      nameId: uniqueId('tag-name-'),
      refId: uniqueId('ref-'),
      messageId: uniqueId('message-'),
    };
  },
  computed: {
    ...mapState('editNew', ['projectId', 'release', 'createFrom']),
  },
  methods: {
    ...mapActions('editNew', ['updateReleaseTagMessage', 'updateCreateFrom']),
  },
  i18n: {
    refSelector: {
      noRefSelected: __('No source selected'),
      searchPlaceholder: __('Search branches, tags, and commits'),
      dropdownHeader: __('Select source'),
    },
  },
};
</script>
<template>
  <div class="gl-p-3" data-testid="create-from-field">
    <gl-form-group class="gl-mb-3" :label="__('Tag name')" :label-for="nameId" label-sr-only>
      <gl-form-input :id="nameId" :value="value" autofocus @input="$emit('change', $event)" />
    </gl-form-group>
    <gl-form-group class="gl-mb-3" :label="__('Create from')" :label-for="refId" label-sr-only>
      <ref-selector
        :id="refId"
        :project-id="projectId"
        :value="createFrom"
        :translations="$options.i18n.refSelector"
        @input="updateCreateFrom"
      />
    </gl-form-group>
    <gl-form-group
      class="gl-mb-3"
      :label="s__('CreateGitTag|Set tag message')"
      :label-for="messageId"
      label-sr-only
    >
      <gl-form-textarea
        :id="messageId"
        :placeholder="
          s__(
            'CreateGitTag|Add a message to the tag. Leaving this blank creates a lightweight tag.',
          )
        "
        :no-resize="false"
        :value="release.tagMessage"
        @input="updateReleaseTagMessage"
      />
    </gl-form-group>
    <gl-button class="gl-mr-3" variant="confirm" @click="$emit('create')">
      {{ __('Save') }}
    </gl-button>
    <gl-button @click="$emit('cancel')">{{ s__('Release|Select another tag') }}</gl-button>
  </div>
</template>
