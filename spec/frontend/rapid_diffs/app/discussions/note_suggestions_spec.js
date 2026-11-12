import { ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import { createTestingPinia } from '@pinia/testing';
import { defineStore } from 'pinia';
import NoteSuggestions from '~/rapid_diffs/app/discussions/note_suggestions.vue';
import Suggestions from '~/vue_shared/components/markdown/suggestions.vue';

describe('NoteSuggestions', () => {
  let wrapper;
  let store;

  const useTestStore = defineStore('testMrDiscussions', () => {
    const batchSuggestionsInfo = ref([]);
    const suggestionsCount = ref(0);
    return {
      batchSuggestionsInfo,
      suggestionsCount,
      submitSuggestion: () => Promise.resolve(),
      submitSuggestionBatch: () => Promise.resolve(),
      addSuggestionInfoToBatch: () => {},
      removeSuggestionInfoFromBatch: () => {},
      suggestionsFilePaths: ref([]),
    };
  });

  const createNote = (overrides = {}) => ({
    id: '123',
    discussion_id: 'disc-1',
    note_html: '<p>suggestion content</p>',
    suggestions: [{ id: 1, appliable: true, applied: false }],
    position: { new_path: 'app/models/user.rb' },
    ...overrides,
  });

  const createComponent = (note = createNote(), provide = {}) => {
    wrapper = shallowMount(NoteSuggestions, {
      propsData: { note },
      provide: {
        store,
        suggestionsHelpPath: '/help/suggestions',
        defaultSuggestionCommitMessage: 'Apply %{suggestions_count} suggestion(s)',
        ...provide,
      },
    });
  };

  const findSuggestions = () => wrapper.findComponent(Suggestions);

  beforeEach(() => {
    createTestingPinia({ stubActions: false });
    store = useTestStore();
  });

  it('renders Suggestions with correct props', () => {
    store.suggestionsCount = 3;
    store.batchSuggestionsInfo = [{ suggestionId: 1 }];
    const note = createNote();
    createComponent(note);
    expect(findSuggestions().props()).toMatchObject({
      suggestions: note.suggestions,
      noteHtml: note.note_html,
      helpPagePath: '/help/suggestions',
      suggestionsCount: 3,
      batchSuggestionsInfo: [{ suggestionId: 1 }],
    });
  });

  it('computes commit message from template', () => {
    createComponent();
    expect(findSuggestions().props('defaultCommitMessage')).toBe('Apply 1 suggestion(s)');
  });

  it('fills branch, project and user placeholders', () => {
    createComponent(createNote(), {
      defaultSuggestionCommitMessage:
        '%{branch_name} %{project_name} %{project_path} %{username} %{user_full_name}',
      suggestionCommitMessageValues: {
        branch_name: 'feature',
        project_name: 'Project',
        project_path: 'project',
        username: 'jdoe',
        user_full_name: 'Jane Doe',
      },
    });
    expect(findSuggestions().props('defaultCommitMessage')).toBe(
      'feature Project project jdoe Jane Doe',
    );
  });

  it('does not HTML-escape filled values', () => {
    createComponent(createNote(), {
      defaultSuggestionCommitMessage: '%{project_name} by %{user_full_name}',
      suggestionCommitMessageValues: { project_name: 'R&D', user_full_name: "O'Brien" },
    });
    expect(findSuggestions().props('defaultCommitMessage')).toBe("R&D by O'Brien");
  });

  it('leaves placeholders without a value unchanged', () => {
    createComponent(createNote(), {
      defaultSuggestionCommitMessage: 'Apply to %{branch_name} as %{username}',
      suggestionCommitMessageValues: { branch_name: 'feature' },
    });
    expect(findSuggestions().props('defaultCommitMessage')).toBe('Apply to feature as %{username}');
  });

  it('calls store.submitSuggestion on apply', () => {
    createComponent();
    findSuggestions().vm.$emit('apply', {
      suggestionId: 1,
      flashContainer: document.body,
      message: 'msg',
    });
    expect(store.submitSuggestion).toHaveBeenCalledWith(
      expect.objectContaining({
        suggestionId: 1,
        discussionId: 'disc-1',
        noteId: '123',
        message: 'msg',
      }),
    );
  });

  it('calls store.submitSuggestionBatch on apply-batch', () => {
    createComponent();
    findSuggestions().vm.$emit('apply-batch', { message: 'batch msg' });
    expect(store.submitSuggestionBatch).toHaveBeenCalledWith({ message: 'batch msg' });
  });

  it('calls store.addSuggestionInfoToBatch on add-to-batch', () => {
    createComponent();
    findSuggestions().vm.$emit('add-to-batch', 42);
    expect(store.addSuggestionInfoToBatch).toHaveBeenCalledWith({
      suggestionId: 42,
      discussionId: 'disc-1',
      noteId: '123',
    });
  });

  it('calls store.removeSuggestionInfoFromBatch on remove-from-batch', () => {
    createComponent();
    findSuggestions().vm.$emit('remove-from-batch', 42);
    expect(store.removeSuggestionInfoFromBatch).toHaveBeenCalledWith(42);
  });
});
