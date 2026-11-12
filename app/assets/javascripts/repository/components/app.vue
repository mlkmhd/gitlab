<script>
import FileTreeBrowser from '~/repository/file_tree_browser/file_tree_browser.vue';
import repositoryPathMixin from '~/repository/mixins/repository_path';
import { generateHistoryUrl } from '~/repository/utils/url_utility';
import BlobAuxiliaryViewer from './blob_auxiliary_viewer.vue';
import HeaderArea from './header_area.vue';
import ForkInfo from './fork_info.vue';
import LastCommit from './last_commit.vue';

export default {
  name: 'RepositoryApp',
  components: {
    FileTreeBrowser,
    HeaderArea,
    ForkInfo,
    LastCommit,
    BlobAuxiliaryViewer,
  },
  mixins: [repositoryPathMixin],
  props: {
    projectPath: {
      type: String,
      required: true,
    },
    projectId: {
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
    historyLink: {
      type: String,
      required: true,
    },
    forkInfo: {
      type: Object,
      required: false,
      default: null,
    },
  },
  computed: {
    isBlobRoute() {
      return Boolean(this.$route.name?.startsWith('blobPath'));
    },
    showFileTreeBrowser() {
      return this.$route.name !== 'projectRoot';
    },
    routeRefType() {
      return this.$route.meta.refType || this.$route.query.ref_type;
    },
    historyUrl() {
      return generateHistoryUrl(this.historyLink, this.computedPath, this.routeRefType).href;
    },
  },
};
</script>

<template>
  <!-- Mirrors the legacy .navigation-root flex layout. -->
  <div class="repository-app gl-flex">
    <file-tree-browser
      v-if="showFileTreeBrowser"
      :project-path="projectPath"
      :current-ref="currentRef"
      :ref-type="refType"
    />
    <div class="gl-w-full gl-min-w-0">
      <header-area
        :project-path="projectPath"
        :project-id="projectId"
        :current-ref="currentRef"
        :ref-type="refType"
      />
      <fork-info v-if="forkInfo" v-bind="forkInfo" />
      <div class="info-well project-last-commit gl-mt-5">
        <last-commit
          :current-path="computedPath"
          :ref-type="routeRefType"
          :history-url="historyUrl"
        />
        <!-- Keyed so a blob without a notice does not keep showing the previous blob's notice. -->
        <blob-auxiliary-viewer
          v-if="isBlobRoute"
          :key="computedPath"
          :path="computedPath"
          :project-path="projectPath"
          :current-ref="currentRef"
          :ref-type="routeRefType"
        />
      </div>
      <router-view :key="$route.path" />
    </div>
  </div>
</template>
