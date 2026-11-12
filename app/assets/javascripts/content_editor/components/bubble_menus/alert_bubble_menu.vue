<script>
import {
  GlButtonGroup,
  GlCollapsibleListbox,
  GlTooltipDirective as GlTooltip,
  GlButton,
} from '@gitlab/ui';
import { __, s__ } from '~/locale';
import Alert from '../../extensions/alert';
import EditorStateObserver from '../editor_state_observer.vue';
import { ALERT_TYPES } from '../../constants/alert_types';
import BubbleMenu from './bubble_menu.vue';

const alertTypes = [
  { text: s__('ContentEditor|Note'), value: ALERT_TYPES.NOTE },
  { text: s__('ContentEditor|Tip'), value: ALERT_TYPES.TIP },
  { text: s__('ContentEditor|Important'), value: ALERT_TYPES.IMPORTANT },
  { text: s__('ContentEditor|Caution'), value: ALERT_TYPES.CAUTION },
  { text: s__('ContentEditor|Warning'), value: ALERT_TYPES.WARNING },
];

export default {
  name: 'AlertBubbleMenu',
  components: {
    BubbleMenu,
    EditorStateObserver,
    GlButton,
    GlCollapsibleListbox,
    GlButtonGroup,
  },
  directives: {
    GlTooltip,
  },
  inject: ['tiptapEditor'],
  data() {
    return {
      alertType: null,
      selectedAlertType: {},
    };
  },
  computed: {
    tippyOptions() {
      return { getReferenceClientRect: this.getReferenceClientRect.bind(this) };
    },
  },
  methods: {
    shouldShow: ({ editor }) => {
      return editor.isActive(Alert.name);
    },

    async updateAlertTypeToState() {
      this.alertType = this.tiptapEditor.getAttributes(Alert.name).type || ALERT_TYPES.NOTE;
      this.selectedAlertType = alertTypes.find((v) => v.value === this.alertType);
    },

    applyAlertType(value) {
      this.selectedAlertType = alertTypes.find((v) => v.value === value);

      this.tiptapEditor
        .chain()
        .focus()
        .updateAttributes(Alert.name, { type: this.selectedAlertType.value })
        .run();
    },

    removeAlert() {
      this.tiptapEditor.chain().focus().deleteNode(Alert.name).run();
    },

    getReferenceClientRect() {
      const { view } = this.tiptapEditor;
      const { from } = this.tiptapEditor.state.selection;
      const node = view.domAtPos(from).node.closest('.markdown-alert');
      return node?.getBoundingClientRect() || new DOMRect(-1000, -1000, 0, 0);
    },
  },
  i18n: {
    alertType: __('Alert type:'),
    removeLabel: __('Remove alert'),
  },
  alertTypes,
};
</script>
<template>
  <editor-state-observer :debounce="0" @transaction="updateAlertTypeToState">
    <bubble-menu
      class="gl-rounded-lg gl-bg-overlap gl-shadow"
      plugin-key="bubbleMenuAlert"
      :should-show="shouldShow"
      :tippy-options="tippyOptions"
    >
      <gl-button-group class="gl-flex gl-items-center">
        <span class="gl-whitespace-nowrap gl-px-3 gl-py-2 gl-text-subtle">
          {{ $options.i18n.alertType }}
        </span>
        <gl-collapsible-listbox
          category="tertiary"
          boundary="viewport"
          :selected="selectedAlertType.value"
          :items="$options.alertTypes"
          :toggle-text="selectedAlertType.text"
          toggle-class="!gl-rounded-none"
          @select="applyAlertType"
        />
        <gl-button
          v-gl-tooltip.bottom
          variant="default"
          category="tertiary"
          size="medium"
          data-testid="remove-alert"
          :aria-label="$options.i18n.removeLabel"
          :title="$options.i18n.removeLabel"
          icon="remove"
          @click="removeAlert"
        />
      </gl-button-group>
    </bubble-menu>
  </editor-state-observer>
</template>
