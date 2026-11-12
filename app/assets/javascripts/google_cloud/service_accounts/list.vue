<script>
import { GlAlert, GlButton, GlEmptyState, GlLink, GlSprintf, GlTable } from '@gitlab/ui';
import { setUrlParams } from 'jh_else_ce/lib/utils/url_utility';
import { DOCS_URL } from '~/constants';
import { __ } from '~/locale';

const GOOGLE_CONSOLE_URL = 'https://console.cloud.google.com/iam-admin/serviceaccounts';

export default {
  name: 'ServiceAccountsList',
  components: { GlAlert, GlButton, GlEmptyState, GlLink, GlSprintf, GlTable },
  props: {
    list: {
      type: Array,
      required: true,
    },
    createUrl: {
      type: String,
      required: true,
    },
    emptyIllustrationUrl: {
      type: String,
      required: true,
    },
  },
  tableFields: [
    { key: 'ref', label: __('Environment'), sortable: true, isRowHeader: true },
    { key: 'gcp_project', label: __('Google Cloud Project'), sortable: true },
    { key: 'service_account_exists', label: __('Service Account'), sortable: true },
    { key: 'service_account_key_exists', label: __('Service Account Key'), sortable: true },
  ],
  i18n: {
    createServiceAccount: __('Create service account'),
    found: __('✔'),
    notFound: __('Not found'),
  },
  methods: {
    gcpProjectUrl(id) {
      return setUrlParams({ project: id }, { url: GOOGLE_CONSOLE_URL });
    },
  },
  GOOGLE_CONSOLE_URL,
  secretsDocsLink: `${DOCS_URL}/ci/secrets/`,
};
</script>

<template>
  <div>
    <gl-empty-state
      v-if="list.length === 0"
      :title="__('No service accounts')"
      :description="
        __('Service Accounts keys authorize GitLab to deploy your Google Cloud project')
      "
      :primary-button-link="createUrl"
      :primary-button-text="$options.i18n.createServiceAccount"
      :svg-path="emptyIllustrationUrl"
      :svg-height="150"
    />

    <div v-else>
      <h2 class="gl-text-size-h2">{{ __('Service accounts') }}</h2>
      <p>{{ __('Service Accounts keys authorize GitLab to deploy your Google Cloud project') }}</p>

      <gl-table :items="list" :fields="$options.tableFields">
        <template #cell(gcp_project)="{ value }">
          <gl-link :href="gcpProjectUrl(value)">{{ value }}</gl-link>
        </template>
        <template #cell(service_account_exists)="{ value }">
          {{ value ? $options.i18n.found : $options.i18n.notFound }}
        </template>
        <template #cell(service_account_key_exists)="{ value }">
          {{ value ? $options.i18n.found : $options.i18n.notFound }}
        </template>
      </gl-table>

      <gl-button :href="createUrl" category="primary" variant="confirm">
        {{ $options.i18n.createServiceAccount }}
      </gl-button>

      <gl-alert class="gl-mt-5" :dismissible="false" variant="tip">
        <gl-sprintf
          :message="
            __(
              'Enhance security by storing service account keys in secret managers - learn more about %{docLinkStart}secret management with GitLab%{docLinkEnd}',
            )
          "
        >
          <template #docLink="{ content }">
            <gl-link :href="$options.secretsDocsLink">
              {{ content }}
            </gl-link>
          </template>
        </gl-sprintf>
      </gl-alert>
    </div>
  </div>
</template>
