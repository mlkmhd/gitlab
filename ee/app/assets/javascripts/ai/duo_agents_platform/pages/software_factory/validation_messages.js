// Validation messages name the configuration key they are about, as a dotted path such as
// `stages.build.flow`. These map a path onto the field of the editor that shows it.
const STATUS_KEY = 'status';
const STAGES_KEY = 'stages';
const REVIEW_KEY = 'review';
const SEPARATOR = '.';

const joinPath = (...segments) => segments.filter(Boolean).join(SEPARATOR);

export const isUnderPath = (path, prefix) => {
  if (typeof path !== 'string') return false;

  const segments = path.split(SEPARATOR);

  return prefix.split(SEPARATOR).every((segment, index) => segments[index] === segment);
};

export const messagesUnder = (messages, prefix) =>
  messages.filter(({ path }) => isUnderPath(path, prefix));

export const messageTextFor = (messages, path) =>
  messages
    .filter((message) => message.path === path)
    .map(({ message }) => message)
    .join(' ');

export const stageMessagePath = (stageName, field) => joinPath(STAGES_KEY, stageName, field);

export const statusMessagePath = (stageName) => joinPath(STATUS_KEY, stageName);

export const reviewMessagePath = (field) => joinPath(REVIEW_KEY, field);
