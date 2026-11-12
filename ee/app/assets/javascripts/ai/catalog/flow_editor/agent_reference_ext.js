import { languages, Range } from 'monaco-editor';
import { s__ } from '~/locale';
import { escapeMarkdown } from '~/lib/utils/text_utility';
import { fieldAtPosition, SOURCE_AI_CATALOG } from './include_context';

export const AGENT_REFERENCE_DECORATION_CLASS = 'ai-catalog-agent-reference';

const ITEM_ID_LINE = /item_id:\s*["']?(\d+)["']?/;

const catalogFieldAt = (text, position) => {
  const context = fieldAtPosition(text, position);
  return context?.source === SOURCE_AI_CATALOG ? context : null;
};

export class AgentReferenceExtension {
  static get extensionName() {
    return 'AgentReferenceExtension';
  }

  onSetup(instance, { getAgents }) {
    this.getAgents = getAgents;
    this.disposables = [];
    this.decorationIds = [];
  }

  onUse(instance) {
    const model = instance.getModel();
    const onlyThisModel =
      (fn) =>
      (candidate, ...rest) =>
        candidate === model ? fn(candidate, ...rest) : null;

    this.disposables.push(
      languages.registerHoverProvider('yaml', {
        provideHover: onlyThisModel((m, position) => this.hover(m, position)),
      }),
      instance.onDidChangeModelContent(() => this.decorate(instance)),
      // SourceEditor disposes without calling unuse, and the hover provider is global.
      instance.onDidDispose(() => this.disposeListeners()),
    );
    this.decorate(instance);
  }

  onBeforeUnuse(instance) {
    this.disposeListeners();
    this.decorationIds = instance.deltaDecorations(this.decorationIds, []);
  }

  disposeListeners() {
    this.disposables.forEach((d) => d.dispose());
    this.disposables = [];
  }

  agentById(id) {
    return this.getAgents().find((agent) => agent.id === id);
  }

  hover(model, position) {
    const context = catalogFieldAt(model.getValue(), position);
    if (!context) return null;

    const id = model.getValueInRange(
      new Range(position.lineNumber, context.valueStart, position.lineNumber, context.valueEnd),
    );
    const agent = this.agentById(id);
    const text = agent
      ? `**${escapeMarkdown(agent.name)}**`
      : s__('AICatalog|No agent with this ID is visible to you.');

    return { contents: [{ value: text }] };
  }

  decorate(instance) {
    const model = instance.getModel();
    const text = model.getValue();
    const ranges = [];

    model.getLinesContent().forEach((line, index) => {
      const match = line.match(ITEM_ID_LINE);
      if (!match) return;
      const lineNumber = index + 1;
      const context = catalogFieldAt(text, { lineNumber, column: line.indexOf(match[1]) + 1 });
      if (!context) return;
      ranges.push({
        range: {
          startLineNumber: lineNumber,
          startColumn: context.valueStart,
          endLineNumber: lineNumber,
          endColumn: context.valueEnd,
        },
        options: { inlineClassName: AGENT_REFERENCE_DECORATION_CLASS, stickiness: 1 },
      });
    });

    this.decorationIds = instance.deltaDecorations(this.decorationIds, ranges);
  }
}
