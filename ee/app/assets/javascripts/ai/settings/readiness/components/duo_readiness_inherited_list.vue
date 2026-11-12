<script>
/**
 * The foundational agents or flows a top-level group picked, listed read-only under the row that
 * reports them on a subgroup's or a project's readiness card.
 */
export default {
  name: 'DuoReadinessInheritedList',
  props: {
    // [{ reference, name }]
    items: {
      type: Array,
      required: true,
    },
    // The parent row is off, so the names are muted with it.
    disabled: {
      type: Boolean,
      required: false,
      default: false,
    },
  },
};
</script>

<template>
  <div class="gl-border-t gl-bg-subtle gl-py-3 gl-pl-9 gl-pr-4">
    <ul class="gl-m-0 gl-list-none gl-p-0 gl-text-sm" :class="{ 'gl-text-subtle': disabled }">
      <li v-for="item in items" :key="item.reference" class="gl-py-1">
        {{ item.name }}
      </li>
    </ul>
  </div>
</template>
