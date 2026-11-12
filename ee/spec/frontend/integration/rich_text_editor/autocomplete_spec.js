import Vue from 'vue';
import VueApollo from 'vue-apollo';
import emojis from 'public/-/emojis/4/emojis.json';
import { initEmojiMock } from 'helpers/emoji';
import {
  getText,
  screen,
  waitForAssertion,
  waitForElement,
  waitForElementToBeNull,
} from 'ee_jest/integration/helpers/test_helpers';
import {
  findContentEditor,
  findMarkdownTextarea,
  placeCursorAfter,
  placeCursorAfterElement,
  pressKey,
  switchToPlainText,
  switchToRichText,
  typeInContentEditor,
  useWorkItemCreateHost,
  waitForFocus,
} from 'ee_jest/integration/rich_text_editor/test_setup';

Vue.use(VueApollo);

describe('Rich text editor - autocomplete', () => {
  useWorkItemCreateHost();

  const findSuggestionsDropdown = () => {
    const dropdown = screen.queryByTestId('content-editor-suggestions-dropdown');
    return dropdown?.closest('[data-tippy-root]').style.visibility === 'hidden' ? null : dropdown;
  };
  const findMention = (text) =>
    [...findContentEditor().querySelectorAll('a.gfm')].find((link) => getText(link) === text);
  const findParagraphTexts = () =>
    [...findContentEditor().querySelectorAll('p')].map((paragraph) => getText(paragraph));

  const waitForSuggestion = (text) =>
    waitForAssertion(() => {
      expect(getText(findSuggestionsDropdown())).toContain(text);
    });

  const waitForEditorText = (text) =>
    waitForAssertion(() => {
      expect(getText(findContentEditor())).toContain(text);
    });

  beforeEach(async () => {
    await initEmojiMock(emojis);
    await switchToRichText();
    await waitForFocus(findContentEditor);
  });

  describe('when an issue reference is expanded', () => {
    beforeEach(() => {
      typeInContentEditor('#1+s ');
    });

    it('displays the full reference name', async () => {
      await waitForEditorText('My Cool Linked Issue');
    });
  });

  describe('when a merge request reference is expanded', () => {
    beforeEach(() => {
      typeInContentEditor('!1+s ');
    });

    it('displays the full reference name', async () => {
      await waitForEditorText('My Cool Merge Request');
    });
  });

  describe('when a quick action is started', () => {
    beforeEach(() => {
      typeInContentEditor('/a');
    });

    it('suggests matching quick actions', async () => {
      await waitForSuggestion('/assign');
      await waitForSuggestion('/label');
    });
  });

  describe.each`
    command         | prefix            | query    | suggestion             | explanation
    ${'/assign'}    | ${'/assign @'}    | ${'abc'} | ${'abc123'}            | ${'Assigns @abc123.'}
    ${'/label'}     | ${'/label ~'}     | ${'My'}  | ${'My Cool Label'}     | ${'Adds a label.'}
    ${'/milestone'} | ${'/milestone %'} | ${'My'}  | ${'My Cool Milestone'} | ${'Sets the milestone to %My Cool Milestone.'}
  `('when $command is chosen', ({ command, prefix, query, suggestion, explanation }) => {
    beforeEach(async () => {
      typeInContentEditor(command);
      await waitForSuggestion(command);
      pressKey('Enter');
      await waitForEditorText(prefix);
    });

    it(`inserts the ${prefix} prefix`, () => {
      expect(getText(findContentEditor())).toContain(prefix);
    });

    describe(`when ${suggestion} is chosen`, () => {
      beforeEach(async () => {
        typeInContentEditor(query);
        await waitForSuggestion(suggestion);
        pressKey('Enter');
      });

      it('explains the quick action', async () => {
        await waitForEditorText(explanation);
      });
    });
  });

  describe('when a member is mentioned', () => {
    beforeEach(async () => {
      typeInContentEditor('@a');
      await waitForSuggestion('abc123');
    });

    describe('when the rest of the username is typed and Enter is pressed', () => {
      beforeEach(async () => {
        typeInContentEditor('bc');
        await waitForSuggestion('abc123');
        pressKey('Enter');
      });

      it('inserts the mention and closes the suggestions', async () => {
        await waitForElementToBeNull(findSuggestionsDropdown);

        expect(getText(findContentEditor())).toContain('@abc123');
      });
    });

    describe('when Tab is pressed', () => {
      beforeEach(() => {
        pressKey('Tab');
      });

      it('inserts the mention and closes the suggestions', async () => {
        await waitForElementToBeNull(findSuggestionsDropdown);

        expect(getText(findContentEditor())).toContain('@abc123');
      });

      describe('when text is typed before the mention', () => {
        beforeEach(async () => {
          await waitForEditorText('@abc123');
          placeCursorAfterElement(findMention('@abc123').closest('[data-node-view-wrapper]'));
          pressKey('ArrowLeft');
          pressKey('ArrowLeft');
          typeInContentEditor('foo ');
          await switchToPlainText();
        });

        it('keeps the text before the mention', () => {
          expect(findMarkdownTextarea().value).toContain('foo @abc123');
        });
      });
    });

    describe('when Escape is pressed', () => {
      beforeEach(async () => {
        pressKey('Escape');
        await waitForElementToBeNull(findSuggestionsDropdown);

        pressKey('Enter');
        typeInContentEditor('foobar');
      });

      it('keeps the typed text in its own paragraph', async () => {
        await waitForAssertion(() => {
          expect(findParagraphTexts()).toEqual(['@a', 'foobar']);
        });
      });
    });

    describe('when more text makes nothing match', () => {
      beforeEach(async () => {
        typeInContentEditor('bfoo');
        await waitForElementToBeNull(findSuggestionsDropdown);

        pressKey('Enter');
        typeInContentEditor('bar');
      });

      it('keeps the typed text in its own paragraph', async () => {
        await waitForAssertion(() => {
          expect(findParagraphTexts()).toEqual(['@abfoo', 'bar']);
        });
      });
    });
  });

  describe('when a suggestion is chosen in the middle of a username', () => {
    beforeEach(async () => {
      typeInContentEditor('@abc123');
      await waitForSuggestion('abc123');

      placeCursorAfter('@abc');
      await waitForSuggestion('abc123');
      pressKey('Enter');

      await waitForElementToBeNull(findSuggestionsDropdown);
      await switchToPlainText();
    });

    it('does not leave the rest of the username behind', () => {
      expect(findMarkdownTextarea().value).toContain('@abc123');
      expect(findMarkdownTextarea().value).not.toContain('@abc123 123');
    });
  });

  describe.each`
    trigger | suggestion                 | inserted
    ${'!'}  | ${'My Cool Merge Request'} | ${'!1'}
    ${'#'}  | ${'My Cool Linked Issue'}  | ${'#1'}
    ${'%'}  | ${'My Cool Milestone'}     | ${'%My Cool Milestone'}
  `('when $trigger is typed', ({ trigger, suggestion, inserted }) => {
    beforeEach(async () => {
      typeInContentEditor(trigger);
      await waitForSuggestion(suggestion);
    });

    describe('when the suggestion is chosen with the keyboard', () => {
      beforeEach(() => {
        pressKey('ArrowDown');
        pressKey('Enter');
      });

      it('inserts the reference', async () => {
        await waitForElementToBeNull(findSuggestionsDropdown);

        expect(getText(findContentEditor())).toContain(inserted);
      });
    });
  });

  describe('when a milestone search matches nothing', () => {
    beforeEach(async () => {
      typeInContentEditor('%');
      await waitForSuggestion('My Cool Milestone');
      typeInContentEditor('x');
    });

    it('hides the suggestions', async () => {
      await waitForElementToBeNull(findSuggestionsDropdown);
    });
  });

  describe('when an emoji is searched', () => {
    beforeEach(async () => {
      typeInContentEditor(':smile');
      await waitForSuggestion('😃 smiley');
    });

    it('suggests matching emoji', () => {
      expect(getText(findSuggestionsDropdown())).toContain('😸 smile_cat');
    });

    describe('when Enter is pressed', () => {
      beforeEach(() => {
        pressKey('Enter');
      });

      it('inserts the emoji', async () => {
        await waitForElementToBeNull(findSuggestionsDropdown);

        expect(getText(findContentEditor())).toContain('😄');
      });
    });
  });

  describe('when a colon is typed after a word', () => {
    describe('when Enter is pressed with no emoji highlighted', () => {
      beforeEach(async () => {
        typeInContentEditor('Steps :');
        await waitForSuggestion('grinning');

        pressKey('Enter');
        await waitForElementToBeNull(findSuggestionsDropdown);
        typeInContentEditor('Open the page');
      });

      it('starts a new paragraph', async () => {
        await waitForAssertion(() => {
          expect(findParagraphTexts()).toEqual(['Steps :', 'Open the page']);
        });
      });
    });

    describe('when a space follows the colon', () => {
      beforeEach(async () => {
        typeInContentEditor('Statut :');
        await waitForSuggestion('grinning');

        typeInContentEditor(' ');
        await waitForElementToBeNull(findSuggestionsDropdown);

        pressKey('Enter');
        typeInContentEditor('Suite');
      });

      it('closes the suggestions without inserting an emoji', async () => {
        await waitForAssertion(() => {
          expect(findParagraphTexts()).toEqual(['Statut :', 'Suite']);
        });

        expect(findContentEditor().querySelector('gl-emoji')).toBe(null);
      });
    });
  });

  describe('when a space follows an emoji query', () => {
    beforeEach(async () => {
      typeInContentEditor(':smiling');
      await waitForSuggestion('smiling');
      typeInContentEditor(' ');
    });

    it('keeps searching', async () => {
      await waitForSuggestion('smiling');
    });
  });

  describe('when a space follows the merge request trigger', () => {
    beforeEach(async () => {
      typeInContentEditor('Bonjour !');
      await waitForSuggestion('My Cool Merge Request');

      typeInContentEditor(' ');
      await waitForElementToBeNull(findSuggestionsDropdown);

      pressKey('Enter');
      typeInContentEditor('Comment');
    });

    it('closes the suggestions and keeps the text', async () => {
      await waitForAssertion(() => {
        expect(findParagraphTexts()).toEqual(['Bonjour !', 'Comment']);
      });
    });
  });

  describe('when a wiki page is linked', () => {
    beforeEach(async () => {
      typeInContentEditor('[[My');
      await waitForSuggestion('My Cool Wiki Page');
      pressKey('Enter');
      await waitForElementToBeNull(findSuggestionsDropdown);
    });

    it('inserts the page title', () => {
      expect(getText(findContentEditor())).toContain('My Cool Wiki Page');
    });

    describe('when switching to plain text', () => {
      beforeEach(async () => {
        await switchToPlainText();
      });

      it('serializes a wiki link', () => {
        expect(findMarkdownTextarea().value).toContain('[[My Cool Wiki Page|My-Cool-Wiki-Page]]');
      });
    });
  });

  describe('when a mention is typed inside a code block', () => {
    beforeEach(async () => {
      typeInContentEditor('``` ');
      await waitForElement(() => findContentEditor().querySelector('pre'));
      typeInContentEditor('@');
    });

    it('does not show suggestions', async () => {
      await waitForAssertion(() => {
        expect(getText(findContentEditor().querySelector('pre'))).toBe('@');
      });

      expect(findSuggestionsDropdown()).toBe(null);
    });
  });
});
