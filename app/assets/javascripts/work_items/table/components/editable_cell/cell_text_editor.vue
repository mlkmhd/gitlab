<script>
import { GlFormInput } from '@gitlab/ui';

export default {
  name: 'CellTextEditor',
  components: {
    GlFormInput,
  },
  inheritAttrs: false,
  props: {
    value: {
      type: [String, Number],
      required: false,
      default: '',
    },
    isSaving: {
      type: Boolean,
      required: false,
      default: false,
    },
    validator: {
      type: Function,
      required: false,
      default: () => true,
    },
    selectOnFocus: {
      type: Boolean,
      required: false,
      default: false,
    },
    cancelInvalidOnBlur: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['submit', 'cancel'],
  data() {
    return {
      editedValue: this.value ?? '',
    };
  },
  computed: {
    isValid() {
      return this.validator(this.editedValue);
    },
  },
  mounted() {
    const input = this.$refs.input?.$el;
    input?.focus();
    if (this.selectOnFocus) input?.select();
  },
  methods: {
    submit() {
      if (!this.isValid || this.isSaving) return;
      this.$emit('submit', this.editedValue);
    },
    handleBlur() {
      if (!this.isValid && this.cancelInvalidOnBlur) {
        this.$emit('cancel');
        return;
      }
      this.submit();
    },
    handleKeydown(event) {
      if (event.key === 'Enter') {
        event.preventDefault();
        this.submit();
      } else if (event.key === 'Escape') {
        event.preventDefault();
        event.stopPropagation();
        this.$emit('cancel');
      }
    },
  },
};
</script>

<template>
  <span class="gl-contents" @click.stop>
    <gl-form-input
      ref="input"
      v-model="editedValue"
      v-bind="$attrs"
      :state="isValid"
      :disabled="isSaving"
      class="-gl-ml-1 gl-min-w-0 gl-flex-grow !gl-px-1 !gl-py-2 !gl-text-sm"
      @keydown="handleKeydown"
      @blur="handleBlur"
    />
  </span>
</template>
