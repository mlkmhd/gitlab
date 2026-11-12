import { h, nextTick, ref } from 'vue';
import { mount } from '@vue/test-utils';
import { Portal, PortalTarget } from '~/lib/utils/vue3compat/portal_vue_vue3';

(process.env.VUE_VERSION === '3' ? describe : describe.skip)('portal_vue_vue3', () => {
  let wrapper;
  let targetClass;

  const createComponent = (rootCount) => {
    targetClass = ref('initial');

    // The target sits in its own component so it can re-render without the portal.
    const TargetHost = {
      render: () => h(PortalTarget, { name: 'footer', class: targetClass.value }),
    };

    wrapper = mount({
      render: () =>
        h('div', [
          h(TargetHost),
          h(
            Portal,
            { to: 'footer' },
            {
              default: () =>
                Array.from({ length: rootCount }, (_, i) =>
                  h('span', { 'data-testid': 'portaled-node' }, `Node ${i}`),
                ),
            },
          ),
        ]),
    });
  };

  const findPortaledText = () =>
    wrapper.findAll('[data-testid="portaled-node"]').wrappers.map((node) => node.text());

  it.each([
    [1, ['Node 0']],
    [2, ['Node 0', 'Node 1']],
  ])('keeps %i root node(s) when the target re-renders', async (rootCount, expected) => {
    createComponent(rootCount);
    await nextTick();

    targetClass.value = 'updated';
    await nextTick();

    expect(findPortaledText()).toEqual(expected);
  });
});
