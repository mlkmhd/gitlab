import Vue from 'vue';
import VueApollo from 'vue-apollo';
import {
  screen,
  setInputValue,
  waitForAssertion,
  waitForElement,
  within,
} from 'ee_jest/integration/helpers/test_helpers';
import {
  findMarkdownTextarea,
  pressKey,
  setPlainTextContent,
  stubUnsupportedExecCommand,
  useWorkItemCreateHost,
} from 'ee_jest/integration/rich_text_editor/test_setup';

Vue.use(VueApollo);

describe('Plain text editor', () => {
  useWorkItemCreateHost();
  stubUnsupportedExecCommand();

  const findMarkdownArea = () => findMarkdownTextarea()?.closest('.md-area') ?? null;
  const findToolbarButtonByLabel = (label) =>
    within(findMarkdownArea()).queryByLabelText(new RegExp(`^${label}`), { selector: 'button' });
  const findPreviewToggle = () =>
    findMarkdownArea()?.querySelector('[data-testid="preview-toggle"]');
  const findWriteHolder = () => findMarkdownArea()?.querySelector('.md-write-holder');
  const findPreviewHolder = () => findMarkdownArea()?.querySelector('.md-preview-holder');
  const findTitleInput = () => screen.queryByTestId('work-item-title-input');

  const enterText = async (text) => {
    await setPlainTextContent(text);
    findMarkdownTextarea().focus();
  };

  const enterAndSelect = async (text, start = 0, end = text.length) => {
    await enterText(text);
    findMarkdownTextarea().setSelectionRange(start, end);
  };

  const showPreview = async () => {
    (await waitForElement(findPreviewToggle)).click();
    await waitForAssertion(() => {
      expect(findWriteHolder().style.display).toBe('none');
    });
  };

  const hidePreview = async () => {
    findPreviewToggle().click();
    await waitForAssertion(() => {
      expect(findWriteHolder().style.display).toBe('');
    });
  };

  const togglePreview = async () => {
    await showPreview();
    await hidePreview();
  };

  describe.each`
    context                                 | setup
    ${'when the preview was never shown'}   | ${() => {}}
    ${'when the preview was toggled first'} | ${togglePreview}
  `('$context', ({ setup }) => {
    beforeEach(async () => {
      await waitForElement(findMarkdownTextarea);
      await setup();
    });

    describe.each`
      shortcut          | key    | modifiers                            | text               | expected
      ${'Ctrl+B'}       | ${'b'} | ${{ ctrlKey: true }}                 | ${'bold'}          | ${'**bold**'}
      ${'Ctrl+I'}       | ${'i'} | ${{ ctrlKey: true }}                 | ${'italic'}        | ${'_italic_'}
      ${'Ctrl+Shift+X'} | ${'X'} | ${{ ctrlKey: true, shiftKey: true }} | ${'strikethrough'} | ${'~~strikethrough~~'}
      ${'Ctrl+K'}       | ${'k'} | ${{ ctrlKey: true }}                 | ${'link'}          | ${'[link](url)'}
    `('when $shortcut is pressed on selected text', ({ key, modifiers, text, expected }) => {
      beforeEach(async () => {
        await enterAndSelect(text);
        pressKey(key, modifiers);
      });

      it(`formats the text as ${expected}`, () => {
        expect(findMarkdownTextarea().value).toBe(expected);
      });
    });

    describe('when a link is added and its URL is typed', () => {
      beforeEach(async () => {
        await enterAndSelect('link');
        pressKey('k', { ctrlKey: true });

        const textarea = findMarkdownTextarea();
        textarea.setRangeText(
          'https://example.com',
          textarea.selectionStart,
          textarea.selectionEnd,
          'end',
        );
        textarea.dispatchEvent(new Event('input', { bubbles: true }));
      });

      it('replaces the URL placeholder', () => {
        expect(findMarkdownTextarea().value).toBe('[link](https://example.com)');
      });
    });

    describe.each`
      shortcut    | key    | text
      ${'Meta+B'} | ${'b'} | ${'bold'}
      ${'Meta+I'} | ${'i'} | ${'italic'}
      ${'Meta+K'} | ${'k'} | ${'link'}
    `('when $shortcut is pressed on selected text', ({ key, text }) => {
      beforeEach(async () => {
        await enterAndSelect(text);
        pressKey(key, { metaKey: true });
      });

      it('leaves the text unformatted', () => {
        expect(findMarkdownTextarea().value).toBe(text);
      });
    });

    describe('when Ctrl+B is pressed in the title field', () => {
      beforeEach(() => {
        const title = findTitleInput();
        title.focus();
        setInputValue(title, 'some text');
        pressKey('b', { ctrlKey: true });
      });

      it('keeps focus on the title and leaves the description empty', () => {
        expect(document.activeElement).toBe(findTitleInput());
        expect(findMarkdownTextarea().value).toBe('');
      });
    });
  });

  describe('when Add bold text is clicked after showing the preview', () => {
    beforeEach(async () => {
      await enterText('test');
      await showPreview();
      await waitForAssertion(() => {
        expect(findPreviewHolder().querySelector('.md > p')?.textContent).toBe('test');
      });
      await hidePreview();

      findMarkdownTextarea().setSelectionRange(0, 4);
      findToolbarButtonByLabel('Add bold text').click();
    });

    it('formats the selected text', () => {
      expect(findMarkdownTextarea().value).toBe('**test**');
    });
  });
});
