<script>
import {
  GlButton,
  GlForm,
  GlFormCheckbox,
  GlFormGroup,
  GlFormInput,
  GlFormInputGroup,
  GlFormPasswordInput,
  GlLink,
  GlMultiStepFormTemplate,
  GlToastMixin,
} from '@gitlab/ui';
import csrf from '~/lib/utils/csrf';
import { visitUrl, isReasonableGitUrl } from '~/lib/utils/url_utility';
import { s__, sprintf } from '~/locale';
import { helpPagePath } from '~/helpers/help_page_helper';
import SharedProjectCreationFields from './shared_project_creation_fields.vue';
import { checkRepositoryConnection } from './utils';

export default {
  name: 'ImportByUrlForm',
  components: {
    SharedProjectCreationFields,
    GlButton,
    GlForm,
    GlFormCheckbox,
    GlFormGroup,
    GlFormInput,
    GlFormInputGroup,
    GlFormPasswordInput,
    GlLink,
    GlMultiStepFormTemplate,
  },
  mixins: [GlToastMixin],
  inject: {
    importByUrlValidatePath: {
      default: null,
    },
    hasRepositoryMirrorsFeature: {
      default: false,
    },
    newProjectPath: {
      default: null,
    },
    newProjectFormPath: {
      default: null,
    },
  },
  props: {
    namespace: {
      type: Object,
      required: true,
    },
  },

  data() {
    return {
      repositoryUrl: '',
      repositoryUsername: '',
      repositoryPassword: '',
      repositoryMirror: false,
      isPrivateRepository: false,
      isCheckingConnection: false,
      urlValidationState: null,
      isProjectPathValid: false,
      isUsernameTouched: false,
      isPasswordTouched: false,
    };
  },
  computed: {
    areCredentialsMissing() {
      if (!this.isPrivateRepository) return false;
      // The git connection check only sends the credentials if both
      // are provided. Require both to limit the need for retry
      return this.isUsernameEmpty || this.isPasswordEmpty;
    },
    usernameValidationState() {
      return this.isUsernameTouched && this.isUsernameEmpty ? false : null;
    },
    passwordValidationState() {
      return this.isPasswordTouched && this.isPasswordEmpty ? false : null;
    },
    isSubmitDisabled() {
      return (
        this.urlValidationState !== true || !this.isProjectPathValid || this.areCredentialsMissing
      );
    },
    isUsernameEmpty() {
      return this.repositoryUsername === '';
    },
    isPasswordEmpty() {
      return this.repositoryPassword === '';
    },
  },
  watch: {
    isPrivateRepository(isPrivate) {
      if (isPrivate) return;

      this.repositoryUsername = '';
      this.repositoryPassword = '';
      this.isUsernameTouched = false;
      this.isPasswordTouched = false;
    },
  },
  methods: {
    async checkConnection() {
      if (this.areCredentialsMissing) {
        this.isUsernameTouched = true;
        this.isPasswordTouched = true;
        return;
      }

      this.isCheckingConnection = true;

      const result = await checkRepositoryConnection(this.importByUrlValidatePath, {
        url: this.repositoryUrl,
        user: this.repositoryUsername,
        password: this.repositoryPassword,
      });

      if (!result.isValid) {
        this.isCheckingConnection = false;
        this.urlValidationState = false;
        return;
      }

      this.$toast.show(this.connectionResultMessage(result));
      this.isCheckingConnection = false;
    },
    connectionResultMessage({ success, message }) {
      if (success) return s__('ProjectImportByURL|Connection successful.');

      if (this.isPrivateRepository) {
        return sprintf(s__('ProjectImportByURL|Connection failed: %{error}.'), { error: message });
      }

      return sprintf(
        s__(
          'ProjectImportByURL|Connection failed: %{error}. If the repository is private, select "This repository is private".',
        ),
        { error: message },
      );
    },
    onBack() {
      visitUrl(this.newProjectPath);
    },
    onBlur() {
      this.urlValidationState =
        this.repositoryUrl === '' ? null : isReasonableGitUrl(this.repositoryUrl);
    },
    onInput() {
      this.urlValidationState = null;
    },
    onProjectFieldsValidate(val) {
      this.isProjectPathValid = val;
    },
  },
  csrf,
  repositoryUrlPlaceholder: 'https://gitlab.company.com/group/project.git',
  repositoryMirrorHelpPath: helpPagePath('user/project/repository/mirror/pull.md', {
    anchor: 'how-pull-mirroring-works',
  }),
};
</script>

<template>
  <gl-form method="post" :action="newProjectFormPath">
    <input :value="$options.csrf.token" type="hidden" name="authenticity_token" />
    <gl-multi-step-form-template :title="s__('ProjectImportByURL|Import repository by URL')">
      <template #default>
        <gl-form-group
          :label="__('Git repository URL')"
          label-for="repository-url"
          :invalid-feedback="s__('ProjectImportByURL|Enter a valid URL')"
          :state="urlValidationState"
          data-testid="repository-url-form-group"
          :label-description="
            s__(
              'ProjectImportByURL|The repository must be accessible over http://, https:// or git://',
            )
          "
        >
          <gl-form-input-group>
            <gl-form-input
              id="repository-url"
              v-model.trim="repositoryUrl"
              name="project[import_url]"
              autocomplete="off"
              data-testid="repository-url"
              type="url"
              required
              :state="urlValidationState"
              :placeholder="$options.repositoryUrlPlaceholder"
              @blur="onBlur"
              @input="onInput"
            />
            <template #append>
              <gl-button
                :loading="isCheckingConnection"
                data-testid="check-connection"
                @click="checkConnection"
              >
                {{ s__('ProjectImportByURL|Check connection') }}
              </gl-button>
            </template>
          </gl-form-input-group>
        </gl-form-group>

        <gl-form-group>
          <gl-form-checkbox
            id="private-repository"
            v-model="isPrivateRepository"
            data-testid="private-repository-checkbox"
          >
            {{ s__('ProjectImportByURL|This repository is private') }}
          </gl-form-checkbox>
        </gl-form-group>

        <template v-if="isPrivateRepository">
          <p id="credentials-hint" class="gl-text-subtle" data-testid="credentials-hint">
            {{
              s__(
                'ProjectImportByURL|For GitHub or GitLab, use a personal access token instead of your account password.',
              )
            }}
          </p>

          <div class="gl-grid gl-grid-cols-2 gl-gap-5">
            <gl-form-group
              :label="__('Username')"
              label-for="repository-username"
              :invalid-feedback="s__('ProjectImportByURL|Enter a username.')"
              :state="usernameValidationState"
              data-testid="repository-username-form-group"
            >
              <gl-form-input
                id="repository-username"
                v-model="repositoryUsername"
                trim
                name="project[import_url_user]"
                data-testid="repository-username"
                autocomplete="off"
                aria-describedby="credentials-hint"
                :state="usernameValidationState"
                @blur="isUsernameTouched = true"
              />
            </gl-form-group>

            <gl-form-group
              :label="s__('ProjectImportByURL|Password or access token')"
              label-for="repository-password"
              :invalid-feedback="s__('ProjectImportByURL|Enter a password or token.')"
              :state="passwordValidationState"
              data-testid="repository-password-form-group"
            >
              <gl-form-password-input
                id="repository-password"
                v-model="repositoryPassword"
                name="project[import_url_password]"
                data-testid="repository-password"
                autocomplete="off"
                aria-describedby="credentials-hint"
                :state="passwordValidationState"
                @blur="isPasswordTouched = true"
              />
            </gl-form-group>
          </div>
        </template>

        <gl-form-group :label="__('Mirror repository')" label-for="repository-mirror">
          <gl-form-checkbox
            id="repository-mirror"
            v-model="repositoryMirror"
            name="project[mirror]"
            :disabled="!hasRepositoryMirrorsFeature"
            data-testid="import-project-by-url-repo-mirror"
          >
            {{
              __(
                "Automatically update this project's branches and tags from the upstream repository.",
              )
            }}
            <gl-link :href="$options.repositoryMirrorHelpPath" target="_blank">
              {{ __('How does pull mirroring work?') }}
            </gl-link>
          </gl-form-checkbox>
        </gl-form-group>

        <shared-project-creation-fields
          :namespace="namespace"
          @on-validate-project-fields="onProjectFieldsValidate"
        />
      </template>

      <template #next>
        <gl-button
          type="submit"
          category="primary"
          variant="confirm"
          :disabled="isSubmitDisabled"
          data-testid="import-project-by-url-button"
        >
          {{ __('Create project') }}
        </gl-button>
      </template>
      <template #back>
        <gl-button
          category="primary"
          variant="default"
          data-testid="import-project-by-url-back-button"
          @click="onBack"
        >
          {{ __('Go back') }}
        </gl-button>
      </template>
    </gl-multi-step-form-template>
  </gl-form>
</template>
