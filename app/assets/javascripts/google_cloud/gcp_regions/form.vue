<script>
import { GlButton, GlFormGroup, GlFormSelect } from '@gitlab/ui';

export default {
  name: 'GcpRegionsForm',
  components: { GlButton, GlFormGroup, GlFormSelect },
  props: {
    availableRegions: { required: true, type: Array },
    refs: { required: true, type: Array },
    cancelPath: { required: true, type: String },
  },
};
</script>

<template>
  <div>
    <header class="gl-my-5 gl-border-b-1 gl-border-b-default gl-border-b-solid">
      <h1 class="gl-text-size-h1">{{ __('Configure region for environment') }}</h1>
    </header>

    <gl-form-group
      label-for="ref"
      :label="s__('GoogleCloud|Refs')"
      :description="s__('GoogleCloud|Configured region is linked to the selected branch or tag')"
    >
      <gl-form-select id="ref" name="ref" required>
        <option value="*">{{ __('All') }}</option>
        <option v-for="ref in refs" :key="ref" :value="ref">
          {{ ref }}
        </option>
      </gl-form-select>
    </gl-form-group>

    <gl-form-group
      label-for="gcp_region"
      :label="__('Region')"
      :description="__('List of suitable GCP locations')"
    >
      <gl-form-select id="gcp_region" name="gcp_region" required :list="availableRegions">
        <option v-for="(region, index) in availableRegions" :key="index" :value="region">
          {{ region }}
        </option>
      </gl-form-select>
    </gl-form-group>

    <div class="form-actions row">
      <gl-button type="submit" category="primary" variant="confirm">
        {{ __('Configure region') }}
      </gl-button>
      <gl-button class="gl-ml-1" :href="cancelPath">{{ __('Cancel') }}</gl-button>
    </div>
  </div>
</template>
