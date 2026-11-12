import { GlButton } from '@gitlab/ui';
import { nextTick } from 'vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import ConversationForm from 'ee/merge_requests/ai_overview/components/conversation_form.vue';
import MarkdownEditor from '~/vue_shared/components/markdown/markdown_editor.vue';

describe('AI Overview conversation form', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(ConversationForm, {
      propsData: { placeholder: 'Reply…', submitText: 'Reply', ...props },
      provide: { projectPath: 'group/proj', iid: '1' },
    });
  };

  const findEditor = () => wrapper.findComponent(MarkdownEditor);
  const findSubmit = () => wrapper.findComponentByTestId('conversation-form-submit');
  const findCancel = () => wrapper.findAllComponents(GlButton).at(1);

  const type = async (value) => {
    findEditor().vm.$emit('input', value);
    await nextTick();
  };

  describe('by default', () => {
    beforeEach(() => {
      createComponent();
    });

    it('renders a markdown editor with quick actions', () => {
      expect(findEditor().props()).toMatchObject({
        renderMarkdownPath: '/group/proj/-/preview_markdown?target_type=MergeRequest&target_id=1',
        markdownDocsPath: '/help/user/markdown',
        noteableType: 'MergeRequest',
        supportsQuickActions: true,
        autofocus: true,
        disabled: false,
      });
      expect(findEditor().props('formFieldProps')).toMatchObject({
        placeholder: 'Reply…',
        'aria-label': 'Reply…',
      });
    });

    it('cannot be submitted while empty', () => {
      expect(findSubmit().props('disabled')).toBe(true);
    });

    it('emits the text on submit', async () => {
      await type('On it.');
      await wrapper.find('form').trigger('submit');

      expect(wrapper.emitted('submit')).toEqual([['On it.']]);
    });

    it.each(['metaKey', 'ctrlKey'])('emits the text on Enter with %s', async (modifier) => {
      await type('On it.');
      findEditor().vm.$emit(
        'keydown',
        new KeyboardEvent('keydown', { key: 'Enter', [modifier]: true }),
      );

      expect(wrapper.emitted('submit')).toEqual([['On it.']]);
    });

    it('does not submit on Enter alone', async () => {
      await type('On it.');
      findEditor().vm.$emit('keydown', new KeyboardEvent('keydown', { key: 'Enter' }));

      expect(wrapper.emitted('submit')).toBeUndefined();
    });

    it('emits cancel', () => {
      findCancel().vm.$emit('click');

      expect(wrapper.emitted('cancel')).toHaveLength(1);
    });
  });

  it('does not focus the editor when autofocus is off', () => {
    createComponent({ autofocus: false });

    expect(findEditor().props('autofocus')).toBe(false);
  });

  describe('while posting', () => {
    beforeEach(() => {
      createComponent({ loading: true });
    });

    it('disables the editor and shows the submit button as loading', () => {
      expect(findEditor().props('disabled')).toBe(true);
      expect(findSubmit().props('loading')).toBe(true);
    });

    it('does not submit again from the keyboard', async () => {
      await type('On it.');
      findEditor().vm.$emit(
        'keydown',
        new KeyboardEvent('keydown', { key: 'Enter', metaKey: true }),
      );

      expect(wrapper.emitted('submit')).toBeUndefined();
    });
  });
});
