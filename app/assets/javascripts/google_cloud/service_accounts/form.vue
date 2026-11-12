<script>
import { GlButton, GlFormCheckbox, GlFormGroup, GlFormSelect } from '@gitlab/ui';

export default {
  name: 'ServiceAccountsForm',
  ALL_REFS: '*',
  components: { GlButton, GlFormGroup, GlFormSelect, GlFormCheckbox },
  props: {
    gcpProjects: { required: true, type: Array },
    refs: { required: true, type: Array },
    cancelPath: { required: true, type: String },
  },
};
</script>

<template>
  <div>
    <header class="gl-my-5 gl-border-b-1 gl-border-b-default gl-border-b-solid">
      <h2 class="gl-text-size-h1">{{ s__('GoogleCloud|Create service account') }}</h2>
    </header>
    <gl-form-group
      label-for="gcp_project"
      :label="s__('GoogleCloud|Google Cloud project')"
      :description="
        s__('GoogleCloud|New service account is generated for the selected Google Cloud project')
      "
    >
      <gl-form-select id="gcp_project" name="gcp_project" required>
        <option
          v-for="gcpProject in gcpProjects"
          :key="gcpProject.project_id"
          :value="gcpProject.project_id"
        >
          {{ gcpProject.name }}
        </option>
      </gl-form-select>
    </gl-form-group>
    <gl-form-group
      label-for="ref"
      :label="s__('GoogleCloud|Refs')"
      :description="
        s__('GoogleCloud|Generated service account is linked to the selected branch or tag')
      "
    >
      <gl-form-select id="ref" name="ref" required>
        <option :value="$options.ALL_REFS">{{ __('All') }}</option>
        <option v-for="ref in refs" :key="ref" :value="ref">
          {{ ref }}
        </option>
      </gl-form-select>
    </gl-form-group>
    <gl-form-group>
      <gl-form-checkbox name="confirmation" required>
        {{
          s__(
            'GoogleCloud|I understand the responsibilities involved with managing service account keys',
          )
        }}
      </gl-form-checkbox>
    </gl-form-group>

    <div class="form-actions row">
      <gl-button type="submit" category="primary" variant="confirm">
        {{ s__('GoogleCloud|Create service account') }}
      </gl-button>
      <gl-button class="gl-ml-1" :href="cancelPath">{{ s__('GoogleCloud|Cancel') }}</gl-button>
    </div>
  </div>
</template>
