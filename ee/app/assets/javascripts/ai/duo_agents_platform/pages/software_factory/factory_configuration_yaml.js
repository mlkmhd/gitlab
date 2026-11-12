import { Document, LineCounter, isAlias, isMap, parseDocument, visit } from 'yaml';
import { s__, sprintf } from '~/locale';
import {
  DEFAULT_MAX_FIX_RUNS,
  MODE_AUTOMATED,
  MODE_MANUAL,
  STAGE_DEFAULT_FLOW_REFERENCES,
  STAGE_REVIEW,
  STAGES,
} from './constants';

const FACTORY_KEY = 'factory';
const STATUS_KEY = 'status';
const STAGES_KEY = 'stages';
const REVIEW_KEY = 'review';

// The blocks the editor writes into. Anything else in the file is left where it is.
const WRITABLE_KEYS = [STATUS_KEY, STAGES_KEY, REVIEW_KEY];

const DEFAULT_INDENT = 2;

const isBlank = (value) => value === undefined || value === null || value === '';

const isAbsent = (value) => value === undefined || value === null;

const isMapping = (value) => typeof value === 'object' && value !== null && !Array.isArray(value);

const asObject = (value) => (isMapping(value) ? value : {});

// A stage is in the factory when the status block lists it, even before it has a status name.
const readStage = (name, statuses, settings) => {
  if (!Object.hasOwn(statuses, name)) {
    return { name, skipped: true };
  }

  const stage = asObject(settings[name]);

  return {
    name,
    skipped: false,
    status: statuses[name] ?? '',
    start: stage.start ?? MODE_MANUAL,
    exit: stage.exit ?? MODE_MANUAL,
    flow: stage.flow ?? null,
    markMergeRequestsReady: stage.mark_merge_requests_ready === true,
  };
};

const readReview = (value) => {
  const review = asObject(value);

  return {
    reviewer: review.reviewer ?? '',
    maxFixRuns: review.max_fix_runs ?? null,
    label: review.label ?? '',
  };
};

const mappingError = (key) =>
  sprintf(s__('DapSoftwareFactory|The `%{key}` key of the configuration must be a mapping.'), {
    key,
  });

// Every key the editor writes has to hold the kind of value the editor can write back. Rejecting
// the file is the only way to avoid replacing something the author put there by hand.
const findTypeError = (config) => {
  const invalidBlock = WRITABLE_KEYS.find(
    (key) => !isAbsent(config[key]) && !isMapping(config[key]),
  );

  if (invalidBlock) return mappingError(invalidBlock);

  const settings = asObject(config[STAGES_KEY]);
  const invalidStage = Object.keys(settings).find(
    (name) => !isAbsent(settings[name]) && !isMapping(settings[name]),
  );

  if (invalidStage) return mappingError(`${STAGES_KEY}.${invalidStage}`);

  const statuses = asObject(config[STATUS_KEY]);
  const invalidStatus = Object.keys(statuses).find(
    (name) => !isAbsent(statuses[name]) && typeof statuses[name] !== 'string',
  );

  if (invalidStatus) {
    return sprintf(
      s__('DapSoftwareFactory|The `%{key}` key of the configuration must be the name of a status.'),
      { key: `${STATUS_KEY}.${invalidStatus}` },
    );
  }

  return null;
};

// Anchors and aliases are invisible in the plain object the type checks read, because it resolves
// them. Writing to a node that an alias points at changes a stage the author did not edit, and
// writing to the alias itself drops the settings it stood for. Only the blocks the editor writes
// are checked, so an anchor anywhere else in the file is left alone.
const findSharedNode = (doc) =>
  WRITABLE_KEYS.find((key) => {
    if (!doc.has(key)) return false;

    let shared = false;

    visit(doc.get(key, true), {
      Node: (_, node) => {
        if (isAlias(node) || node.anchor) {
          shared = true;
          return visit.BREAK;
        }

        return undefined;
      },
    });

    return shared;
  });

// How far the file indents one block inside another, read from the first block mapping rather
// than from the first indented line, which can belong to a block scalar or a comment and is not
// the indent of anything. Sequences are skipped, because `- a` may sit in its parent's column.
const indentOf = (doc, lineCounter) => {
  const column = (node) => lineCounter.linePos(node.range[0]).col;
  let indent = null;

  visit(doc, {
    Pair: (_, { key, value }) => {
      if (!key?.range || !isMap(value) || value.flow || !value.items.length) return undefined;

      indent = column(value.items[0].key) - column(key);
      return visit.BREAK;
    },
  });

  return indent > 0 ? indent : DEFAULT_INDENT;
};

// An empty file, or one holding only comments, is a factory with no stages rather than an error.
const getDocument = (content) => {
  const lineCounter = new LineCounter();
  const doc = parseDocument(content ?? '', { lineCounter });

  if (doc.errors.length) {
    return { doc, error: doc.errors.map(({ message }) => message).join('\n') };
  }

  let data;

  try {
    data = doc.toJS();
  } catch (e) {
    // An alias with no anchor, and the guard against expanding one too many times, are raised
    // rather than collected in `doc.errors`. Callers are promised a problem back, not a throw.
    return { doc, error: e.message };
  }

  if (!isAbsent(data) && !isMapping(data)) {
    return { doc, error: s__('DapSoftwareFactory|The configuration must be a mapping.') };
  }

  const config = asObject(data);
  const indent = indentOf(doc, lineCounter);
  const sharedKey = findSharedNode(doc);
  const error =
    findTypeError(config) ??
    (sharedKey
      ? sprintf(
          s__(
            'DapSoftwareFactory|The `%{key}` key of the configuration uses a YAML anchor or alias. Edit the file in the repository to change it.',
          ),
          { key: sharedKey },
        )
      : null);

  return { doc, config, error, indent };
};

// Stringifying with the default options reflows the whole file: it folds long lines, re-indents
// every block, and rewrites CRLF line endings.
const stringify = (doc, content, indent = DEFAULT_INDENT) => {
  const result = doc.toString({ indent, lineWidth: 0 });

  return content?.includes('\r\n') ? result.replace(/\n/g, '\r\n') : result;
};

const mutate = (content, fn) => {
  const { doc, error, indent } = getDocument(content);

  if (error) {
    throw new Error(error);
  }

  fn(doc);

  return stringify(doc, content, indent);
};

// `setIn` throws when a key along the path holds anything other than a collection, which an empty
// block does. An empty mapping also stringifies as `{}`, so give it back its block style before
// adding a key to it.
const ensureMapAt = (doc, path) =>
  path.forEach((_, index) => {
    const at = path.slice(0, index + 1);
    const node = doc.getIn(at, true);

    if (!isMap(node)) {
      const map = doc.createNode({});

      // The replaced node takes its comment with it, so carry it onto the block that lands here.
      map.commentBefore = node?.comment;
      doc.setIn(at, map);
    } else if (node.items.length === 0) {
      node.flow = false;
    }
  });

// `deleteIn` throws rather than doing nothing when the path does not lead anywhere.
const deleteAt = (doc, path) => {
  if (doc.hasIn(path)) {
    doc.deleteIn(path);
  }
};

const setAt = (doc, path, value) => {
  ensureMapAt(doc, path.slice(0, -1));
  doc.setIn(path, value);
};

const deleteIfEmpty = (doc, path) => {
  const node = doc.getIn(path, true);

  if (isMap(node) && node.items.length === 0) {
    deleteAt(doc, path);
  }
};

const applyChanges = (doc, path, changes) =>
  Object.entries(changes).forEach(([key, value]) => {
    if (isBlank(value)) {
      deleteAt(doc, [...path, key]);
    } else {
      setAt(doc, [...path, key], value);
    }
  });

// Listing a stage with no status name keeps it in the factory while the author picks one, so a
// blank status is written as null rather than deleted.
const setStatus = (doc, stageName, status) =>
  setAt(doc, [STATUS_KEY, stageName], isBlank(status) ? null : status);

export const parseFactoryConfiguration = (content) => {
  const { config, error } = getDocument(content);

  if (error) {
    return { error, factory: '', stages: [], review: readReview(null) };
  }

  const statuses = asObject(config[STATUS_KEY]);
  const settings = asObject(config[STAGES_KEY]);

  return {
    error: null,
    factory: config[FACTORY_KEY] ?? '',
    stages: STAGES.map((name) => readStage(name, statuses, settings)),
    review: readReview(config[REVIEW_KEY]),
  };
};

export const updateStage = (content, stageName, { status, ...settings } = {}) =>
  mutate(content, (doc) => {
    if (status !== undefined) {
      setStatus(doc, stageName, status);
    }

    applyChanges(doc, [STAGES_KEY, stageName], settings);
    deleteIfEmpty(doc, [STAGES_KEY, stageName]);
    deleteIfEmpty(doc, [STAGES_KEY]);
  });

export const skipStage = (content, stageName) =>
  mutate(content, (doc) => {
    deleteAt(doc, [STATUS_KEY, stageName]);
    deleteAt(doc, [STAGES_KEY, stageName]);
    deleteIfEmpty(doc, [STAGES_KEY]);
  });

export const unskipStage = (content, stageName, { status = '', settings = {} } = {}) =>
  mutate(content, (doc) => {
    setStatus(doc, stageName, status);
    applyChanges(doc, [STAGES_KEY, stageName], settings);
    deleteIfEmpty(doc, [STAGES_KEY, stageName]);
    deleteIfEmpty(doc, [STAGES_KEY]);
  });

export const updateReview = (content, changes) =>
  mutate(content, (doc) => applyChanges(doc, [REVIEW_KEY], changes));

export const findDefaultFlowId = (flows, stageName) => {
  const reference = STAGE_DEFAULT_FLOW_REFERENCES[stageName];

  if (!reference) return null;

  return (
    flows.find(({ foundationalFlowReference }) => foundationalFlowReference === reference)?.id ??
    null
  );
};

// Review starts on merge request events, so it is the only stage whose status starts no flow.
export const startsOnStatus = ({ name, skipped, start }) =>
  !skipped && start === MODE_AUTOMATED && name !== STAGE_REVIEW;

export const findNextActiveStage = (stages, stageName) => {
  const index = stages.findIndex(({ name }) => name === stageName);

  if (index < 0) return null;

  return stages.slice(index + 1).find(({ skipped }) => !skipped) ?? null;
};

export const findUnusedStatus = (stages, statusNames, stageName) => {
  const used = new Set(
    stages
      .filter(({ name, skipped }) => name !== stageName && !skipped)
      .map(({ status }) => status?.toLowerCase())
      .filter(Boolean),
  );

  return statusNames.find((status) => !used.has(status.toLowerCase())) ?? '';
};

// A new file enables no stage, so it starts with nothing to fix. The status block is left out
// because an empty one can only be written inline, which does not match the rest of the file.
export const buildTemplate = (factory = '') =>
  stringify(
    new Document({
      [FACTORY_KEY]: factory,
      [REVIEW_KEY]: { max_fix_runs: DEFAULT_MAX_FIX_RUNS },
    }),
  );
