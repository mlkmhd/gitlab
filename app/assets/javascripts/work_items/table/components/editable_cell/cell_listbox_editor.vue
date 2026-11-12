<script>
import { GlCollapsibleListbox } from '@gitlab/ui';
import { debounce, keyBy, last, unionBy } from 'lodash-es';
import { s__ } from '~/locale';
import { DEFAULT_DEBOUNCE_AND_THROTTLE_MS } from '~/lib/utils/constants';

export default {
  name: 'CellListboxEditor',
  components: {
    GlCollapsibleListbox,
  },
  inheritAttrs: false,
  props: {
    items: {
      type: Array,
      required: false,
      default: () => [],
    },
    selectedOptions: {
      type: Array,
      required: false,
      default: () => [],
    },
    multiple: {
      type: Boolean,
      required: false,
      default: false,
    },
    searching: {
      type: Boolean,
      required: false,
      default: false,
    },
    unselectableValues: {
      type: Array,
      required: false,
      default: () => [],
    },
    isSaving: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
  emits: ['search', 'submit'],
  data() {
    const values = this.selectedOptions.map((option) => option.value);

    return {
      selection: this.multiple ? values : (last(values) ?? null),
      searchTerm: '',
      itemsCache: [...this.selectedOptions],
    };
  },
  computed: {
    pickedValues() {
      if (this.multiple) return this.selection ?? [];
      return this.selection === null ? [] : [this.selection];
    },
    pickedOptions() {
      return this.itemsCache.filter((option) => this.pickedValues.includes(option.value));
    },
    listboxItems() {
      if (!this.pickedValues.length || this.searchTerm || !this.items.length) {
        return this.items;
      }

      if (!this.pickedOptions.length) {
        return this.items;
      }

      return [
        { text: s__('WorkItem|Selected'), options: this.pickedOptions },
        {
          text: s__('WorkItem|All'),
          textSrOnly: true,
          options: this.items.filter((option) => !this.pickedValues.includes(option.value)),
        },
      ];
    },
  },
  watch: {
    items: {
      handler(items) {
        const fresh = keyBy(items, 'value');
        const cached = this.itemsCache.map((option) => fresh[option.value] ?? option);
        this.itemsCache = unionBy(cached, items, 'value');
      },
      immediate: true,
    },
    multiple(multiple) {
      if (multiple) {
        this.selection = this.selection === null ? [] : [this.selection];
      } else {
        this.selection = last(this.selection) ?? null;
      }
    },
  },
  created() {
    this.debouncedSearch = debounce(this.search, DEFAULT_DEBOUNCE_AND_THROTTLE_MS);
    this.$emit('search', this.searchTerm);
  },
  beforeDestroy() {
    this.debouncedSearch?.cancel();
  },
  methods: {
    search(term) {
      this.searchTerm = term;
      this.$emit('search', term);
    },
    handleSelect(selection) {
      const isAllowed = (value) =>
        this.pickedValues.includes(value) || !this.unselectableValues.includes(value);

      if (this.multiple) {
        this.selection = selection.filter((value) => isAllowed(value));
      } else if (selection === null || isAllowed(selection)) {
        this.selection = selection;
      }
    },
    handleReset() {
      this.selection = this.multiple ? [] : null;
    },
    handleHidden() {
      this.$emit('submit', this.selection);
    },
    blockWhileSaving(event) {
      if (this.isSaving) event.stopPropagation();
    },
  },
};
</script>

<template>
  <div class="gl-w-full" @click.capture="blockWhileSaving" @keydown.capture="blockWhileSaving">
    <gl-collapsible-listbox
      v-bind="$attrs"
      :items="listboxItems"
      :selected="selection"
      :multiple="multiple"
      :searching="searching"
      class="gl-w-full"
      block
      start-opened
      searchable
      is-check-centered
      @select="handleSelect"
      @search="debouncedSearch"
      @shown="search('')"
      @hidden="handleHidden"
      @reset="handleReset"
    >
      <template #toggle="{ accessibilityAttributes }">
        <slot name="toggle" v-bind="{ accessibilityAttributes, pickedOptions }">
          <div
            role="button"
            tabindex="0"
            class="gl-truncate gl-text-sm"
            v-bind="accessibilityAttributes"
          >
            {{ pickedOptions.map((option) => option.text).join(', ') }}
          </div>
        </slot>
      </template>
      <template #list-item="{ item }">
        <slot name="list-item" :item="item">{{ item.text }}</slot>
      </template>
    </gl-collapsible-listbox>
  </div>
</template>
