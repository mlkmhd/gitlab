<script>
import { getSlotFunction, normalizeRender } from '~/lib/utils/vue3compat/normalize_render';

export default normalizeRender({
  name: 'OrderedLayout',
  props: {
    slotKeys: {
      type: Array,
      required: true,
    },
  },
  render(createElement) {
    return createElement(
      'div',
      {},
      // Nulls pin slot indexes; else Vue 3 remounts the form, hiding posted comments and errors.
      this.slotKeys.map((key) => {
        const scopedSlot = getSlotFunction(this, key);
        if (scopedSlot) {
          return scopedSlot();
        }

        return null;
      }),
    );
  },
});
</script>
