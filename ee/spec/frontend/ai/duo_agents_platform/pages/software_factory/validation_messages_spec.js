import {
  isUnderPath,
  messagesUnder,
  messageTextFor,
  reviewMessagePath,
  stageMessagePath,
  statusMessagePath,
} from 'ee/ai/duo_agents_platform/pages/software_factory/validation_messages';

describe('validation_messages', () => {
  describe('isUnderPath', () => {
    it.each([
      ['stages.build', 'stages.build', true],
      ['stages.build.flow', 'stages.build', true],
      ['stages.builder', 'stages.build', false],
      ['stages', 'stages.build', false],
      [null, 'stages.build', false],
    ])('returns %s under %s as %s', (path, prefix, expected) => {
      expect(isUnderPath(path, prefix)).toBe(expected);
    });
  });

  describe('messagesUnder', () => {
    it('returns messages under the prefix', () => {
      const messages = [
        { path: 'stages.build.flow', message: 'a' },
        { path: 'stages.plan', message: 'b' },
        { path: null, message: 'c' },
      ];

      expect(messagesUnder(messages, 'stages.build')).toEqual([messages[0]]);
    });
  });

  describe('messageTextFor', () => {
    it('joins the messages for an exact path', () => {
      const messages = [
        { path: 'review.reviewer', message: 'Required.' },
        { path: 'review.reviewer', message: 'Unknown user.' },
        { path: 'review', message: 'Ignored.' },
      ];

      expect(messageTextFor(messages, 'review.reviewer')).toBe('Required. Unknown user.');
    });
  });

  describe('path builders', () => {
    it('builds the path of a block and of a field in it', () => {
      expect(stageMessagePath('build')).toBe('stages.build');
      expect(stageMessagePath('build', 'flow')).toBe('stages.build.flow');
      expect(statusMessagePath('build')).toBe('status.build');
      expect(reviewMessagePath()).toBe('review');
      expect(reviewMessagePath('label')).toBe('review.label');
    });
  });
});
