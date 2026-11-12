<script>
import { GlLoadingIcon } from '@gitlab/ui';
import axios from '~/lib/utils/axios_utils';
import { mergeUrlParams } from '~/lib/utils/url_utility';
import { captureException } from '~/sentry/sentry_browser_wrapper';
import SafeHtml from '~/vue_shared/directives/safe_html';
import blobAuxiliaryViewerQuery from '../queries/blob_auxiliary_viewer.query.graphql';
import { getRefType } from '../utils/ref_type';

export default {
  name: 'BlobAuxiliaryViewer',
  components: {
    GlLoadingIcon,
  },
  directives: {
    SafeHtml,
  },
  props: {
    path: {
      type: String,
      required: true,
    },
    projectPath: {
      type: String,
      required: true,
    },
    currentRef: {
      type: String,
      required: true,
    },
    refType: {
      type: String,
      required: false,
      default: null,
    },
  },
  data() {
    return {
      blob: null,
      html: '',
      isLoadingHtml: false,
    };
  },
  apollo: {
    blob: {
      query: blobAuxiliaryViewerQuery,
      // getBlobInfo overwrites the unnormalized `project.repository` cache entry, causing a refetch.
      fetchPolicy: 'no-cache',
      variables() {
        return {
          projectPath: this.projectPath,
          filePath: this.path,
          ref: this.currentRef,
          refType: getRefType(this.refType),
        };
      },
      update({ project }) {
        return project?.repository?.blobs?.nodes[0] || null;
      },
      result() {
        if (this.blob?.auxiliaryViewer) this.loadHtml();
      },
      error(error) {
        captureException(error, { tags: { vue_component: 'BlobAuxiliaryViewer' } });
      },
    },
  },
  methods: {
    loadHtml() {
      const url = mergeUrlParams(
        { format: 'json', viewer: this.blob.auxiliaryViewer.type },
        this.blob.webPath,
      );

      this.isLoadingHtml = true;

      axios
        .get(url)
        .then(({ data }) => {
          this.html = data.html;
        })
        .catch((error) => {
          captureException(error, { tags: { vue_component: 'BlobAuxiliaryViewer' } });
        })
        .finally(() => {
          this.isLoadingHtml = false;
        });
    },
  },
};
</script>

<template>
  <div
    v-if="isLoadingHtml || html"
    class="blob-auxiliary-viewer gl-border-t gl-px-4 gl-py-3"
    data-testid="blob-auxiliary-viewer"
  >
    <span v-if="isLoadingHtml">
      <gl-loading-icon inline />
      {{ __('Analyzing file…') }}
    </span>
    <div v-else v-safe-html="html"></div>
  </div>
</template>
