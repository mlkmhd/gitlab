import Vue from 'vue';
import { mapState } from 'pinia';
import { pinia } from '~/pinia/instance';
import { useFileBrowser } from '~/diffs/stores/file_browser';
import { DiffFile } from '~/rapid_diffs/web_components/diff_file';
import FindFile from '~/vue_shared/components/file_finder/index.vue';
import { Mousetrap } from '~/lib/mousetrap';
import { keysFor, MR_GO_TO_FILE } from '~/behaviors/shortcuts/keybindings';
import { addShortcutsExtension } from '~/behaviors/shortcuts';

function createFileFinderShortcuts(vm) {
  // Extensions are instantiated after the global shortcuts bind `t` (find file),
  // so binding here deterministically gives `t` to the finder.
  return class ShortcutsFileFinder {
    constructor() {
      Mousetrap.bind(keysFor(MR_GO_TO_FILE), (e) => {
        e?.preventDefault?.();
        vm.toggle(!vm.visible);
      });
    }
  };
}

export function initFileFinder() {
  const el = document.getElementById('js-diff-file-finder');
  if (!el) return null;

  const vm = new Vue({
    el,
    name: 'RapidDiffsFileFinder',
    pinia,
    components: { FindFile },
    data() {
      return {
        visible: false,
      };
    },
    computed: {
      ...mapState(useFileBrowser, ['flatBlobsList', 'isLoadingFileBrowser']),
    },
    methods: {
      toggle(value) {
        this.visible = value;
      },
      openFile(file) {
        const diffFile = DiffFile.findByFileHash(file.fileHash);
        if (diffFile) {
          window.mrTabs?.tabShown('diffs');
          diffFile.selectFile();
        }
      },
    },
    render(h) {
      return h('find-file', {
        props: {
          files: this.flatBlobsList,
          visible: this.visible,
          loading: this.isLoadingFileBrowser,
          showDiffStats: true,
          clearSearchOnClose: false,
        },
        on: {
          toggle: this.toggle,
          click: this.openFile,
        },
        class: ['diff-file-finder'],
      });
    },
  });

  addShortcutsExtension(createFileFinderShortcuts(vm));

  return vm;
}
