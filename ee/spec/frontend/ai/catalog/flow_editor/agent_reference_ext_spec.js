import { editor as monacoEditor, languages } from 'monaco-editor';
import {
  AgentReferenceExtension,
  AGENT_REFERENCE_DECORATION_CLASS,
} from 'ee/ai/catalog/flow_editor/agent_reference_ext';
import { AGENTS, FLOW_AGENT_REFERENCES } from './mock_data';

describe('AgentReferenceExtension', () => {
  let model;
  let instance;
  let extension;
  let hoverProvider;
  let hoverDisposable;

  const lineOf = (needle, nth = 0) =>
    FLOW_AGENT_REFERENCES.split('\n')
      .map((l, i) => (l.includes(needle) ? i + 1 : -1))
      .filter((i) => i > 0)[nth];

  beforeEach(() => {
    model = monacoEditor.createModel(FLOW_AGENT_REFERENCES, 'yaml');
    const listeners = [];
    const disposeListeners = [];
    instance = {
      getModel: () => model,
      onDidChangeModelContent: (fn) => {
        listeners.push(fn);
        return { dispose: jest.fn() };
      },
      onDidDispose: (fn) => {
        disposeListeners.push(fn);
        return { dispose: jest.fn() };
      },
      fireDispose: () => disposeListeners.forEach((fn) => fn()),
      deltaDecorations: jest.fn((old, next) => next.map((_, i) => `d${i}`)),
      fireChange: () => listeners.forEach((fn) => fn()),
    };
    hoverDisposable = { dispose: jest.fn() };
    jest.spyOn(languages, 'registerHoverProvider').mockImplementation((lang, p) => {
      hoverProvider = p;
      return hoverDisposable;
    });

    extension = new AgentReferenceExtension();
    extension.onSetup(instance, { getAgents: () => AGENTS });
    extension.onUse(instance);
  });

  afterEach(() => {
    model.dispose();
  });

  describe('hover', () => {
    it('shows the agent name for a known id', () => {
      const hover = hoverProvider.provideHover(model, {
        lineNumber: lineOf('item_id: "43"'),
        column: 15,
      });

      expect(hover.contents[0].value).toBe('**Generator**');
    });

    it('escapes Markdown in the agent name', () => {
      extension.getAgents = () => [{ id: '43', name: 'Foo**bar [x](y)' }];

      const hover = hoverProvider.provideHover(model, {
        lineNumber: lineOf('item_id: "43"'),
        column: 15,
      });

      expect(hover.contents[0].value).toBe('**Foo\\*\\*bar \\[x\\]\\(y\\)**');
    });

    it('says when no agent matches', () => {
      const hover = hoverProvider.provideHover(model, {
        lineNumber: lineOf('item_id: "99"'),
        column: 15,
      });

      expect(hover.contents[0].value).toBe('No agent with this ID is visible to you.');
    });

    it('returns nothing for an entry that is not from the AI Catalog', () => {
      expect(
        hoverProvider.provideHover(model, { lineNumber: lineOf('item_id: "7"'), column: 15 }),
      ).toBeNull();
    });

    it('returns nothing outside an item_id value', () => {
      expect(hoverProvider.provideHover(model, { lineNumber: 1, column: 1 })).toBeNull();
    });

    it('ignores other models', () => {
      const other = monacoEditor.createModel(FLOW_AGENT_REFERENCES, 'yaml');

      expect(hoverProvider.provideHover(other, { lineNumber: 4, column: 15 })).toBe(null);
      other.dispose();
    });
  });

  describe('teardown', () => {
    it('removes the hover provider when the editor is disposed', () => {
      instance.fireDispose();

      expect(hoverDisposable.dispose).toHaveBeenCalled();
    });

    it('removes the hover provider on unuse', () => {
      extension.onBeforeUnuse(instance);

      expect(hoverDisposable.dispose).toHaveBeenCalled();
    });
  });

  describe('decorations', () => {
    it('underlines each numeric item_id under include or subagents on use', () => {
      const [, ranges] = instance.deltaDecorations.mock.calls.at(-1);

      expect(ranges).toHaveLength(3);
      expect(ranges[0]).toMatchObject({
        range: { startLineNumber: lineOf('item_id: "43"'), startColumn: 15, endColumn: 17 },
        options: { inlineClassName: AGENT_REFERENCE_DECORATION_CLASS },
      });
    });

    it('recomputes when the content changes', () => {
      instance.deltaDecorations.mockClear();

      instance.fireChange();

      expect(instance.deltaDecorations).toHaveBeenCalledTimes(1);
    });

    it('clears them before unuse', () => {
      extension.onBeforeUnuse(instance);

      expect(instance.deltaDecorations).toHaveBeenLastCalledWith(expect.any(Array), []);
    });
  });
});
