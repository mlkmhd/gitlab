<script>
import { GlModal, GlForm, GlFormGroup, GlFormInput, GlSprintf } from '@gitlab/ui';
import { __, s__, sprintf } from '~/locale';
import { InternalEvents } from '~/tracking';
import { SECRET_NAME_MAX_LENGTH, SECRET_NAME_REGEX } from 'ee/ci/secrets/constants';

export const CONFIRM_ROTATE_LEAKED_TOKEN_MODAL_EVENT = 'confirm_rotate_leaked_token_modal';
export const CANCEL_ROTATE_LEAKED_TOKEN_MODAL_EVENT = 'cancel_rotate_leaked_token_modal';

export default {
  name: 'RotateSecretModal',
  components: {
    GlModal,
    GlForm,
    GlFormGroup,
    GlFormInput,
    GlSprintf,
  },
  mixins: [InternalEvents.mixin()],
  props: {
    modalId: { type: String, required: true },
    visible: { type: Boolean, required: false, default: false },
    defaultName: { type: String, required: true },
    leakLocation: { type: String, required: false, default: '' },
  },
  emits: ['change', 'confirm'],
  data() {
    return {
      name: this.defaultName,
      nameValid: true,
      confirmed: false,
    };
  },
  computed: {
    invalidNameFeedback() {
      return sprintf(
        s__(
          "SecretsManager|The name must be %{max} characters or fewer and can only contain letters, digits, and '_'.",
        ),
        { max: SECRET_NAME_MAX_LENGTH },
      );
    },
  },
  methods: {
    reset() {
      this.name = this.defaultName;
      this.nameValid = true;
      this.confirmed = false;
    },
    validate() {
      const name = this.name?.trim() ?? '';
      this.nameValid = SECRET_NAME_REGEX.test(name) && name.length <= SECRET_NAME_MAX_LENGTH;
      return this.nameValid;
    },
    confirm(event) {
      if (!this.validate()) {
        event.preventDefault();
        return;
      }

      this.confirmed = true;
      this.trackEvent(CONFIRM_ROTATE_LEAKED_TOKEN_MODAL_EVENT);
      this.$emit('confirm', { name: this.name.trim() });
    },
    // `hide` fires once per close attempt, including an invalid confirm that keeps the modal open.
    onHide(event) {
      if (this.confirmed || event.defaultPrevented) return;

      this.trackEvent(CANCEL_ROTATE_LEAKED_TOKEN_MODAL_EVENT);
    },
  },
  actions: {
    primary: {
      text: s__('SecretsManager|Rotate and fix'),
      attributes: { variant: 'confirm' },
    },
    cancel: { text: __('Cancel') },
  },
};
</script>
<template>
  <gl-modal
    :visible="visible"
    :modal-id="modalId"
    :title="s__('SecretsManager|Rotate leaked token and fix with GitLab Duo')"
    :action-primary="$options.actions.primary"
    :action-cancel="$options.actions.cancel"
    @primary="confirm"
    @show="reset"
    @hide="onHide"
    @change="$emit('change', $event)"
  >
    <p v-if="leakLocation">
      <gl-sprintf
        :message="
          s__('SecretsManager|An active GitLab personal access token is exposed in %{location}.')
        "
      >
        <template #location>
          <code>{{ leakLocation }}</code>
        </template>
      </gl-sprintf>
    </p>
    <ol data-testid="rotation-steps">
      <li>
        {{ s__('SecretsManager|Rotate the token. The leaked value stops working.') }}
      </li>
      <li>
        {{
          s__(
            'SecretsManager|Store the new value in GitLab Secrets Manager. The value is never shown to you or to GitLab Duo.',
          )
        }}
      </li>
      <li>
        {{
          s__(
            'SecretsManager|GitLab Duo opens a merge request that replaces the hardcoded token with a reference to the secret.',
          )
        }}
      </li>
    </ol>
    <gl-form @submit.prevent>
      <gl-form-group
        label-for="rotated-secret-name"
        :label="s__('SecretsManager|Secret name')"
        :description="s__('SecretsManager|Letters, digits, and underscores only. Must be unique.')"
        :state="nameValid"
        :invalid-feedback="invalidNameFeedback"
        class="gl-mb-0"
      >
        <gl-form-input
          id="rotated-secret-name"
          v-model="name"
          :state="nameValid"
          data-testid="secret-name-input"
          @input="nameValid = true"
        />
      </gl-form-group>
    </gl-form>
  </gl-modal>
</template>
