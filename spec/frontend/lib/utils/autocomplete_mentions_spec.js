import { setCurrentUser } from 'helpers/current_user_helper';
import {
  demoteCurrentUser,
  extractMentionedUsernames,
  prioritizeMentionedMembers,
  threadParticipantUsernames,
} from '~/lib/utils/autocomplete_mentions';

describe('extractMentionedUsernames', () => {
  it.each`
    description                         | text                            | expected
    ${'no text'}                        | ${''}                           | ${[]}
    ${'null text'}                      | ${null}                         | ${[]}
    ${'a single mention'}               | ${'hi @deloras'}                | ${['deloras']}
    ${'a mention at the start'}         | ${'@deloras hi'}                | ${['deloras']}
    ${'a trailing period'}              | ${'thanks @deloras.'}           | ${['deloras']}
    ${'a trailing comma'}               | ${'@deloras, hello'}            | ${['deloras']}
    ${'internal dots and hyphens'}      | ${'@foo.bar @foo-bar @foo_bar'} | ${['foo.bar', 'foo-bar', 'foo_bar']}
    ${'a single-character username'}    | ${'@a'}                         | ${['a']}
    ${'mentions in order of first use'} | ${'@deloras @arlie @deloras'}   | ${['deloras', 'arlie']}
    ${'mixed case, lower-cased'}        | ${'@GitLab-Security-Bot'}       | ${['gitlab-security-bot']}
  `('returns $expected for $description', ({ text, expected }) => {
    expect(extractMentionedUsernames(text)).toEqual(expected);
  });

  it('does not treat an email address as a mention', () => {
    expect(extractMentionedUsernames('reach me at deloras@example.com')).toEqual([]);
  });

  it('ignores mentions inside an inline code span', () => {
    expect(extractMentionedUsernames('see `@deloras` and @arlie')).toEqual(['arlie']);
  });

  it('ignores mentions inside a fenced code block', () => {
    expect(extractMentionedUsernames('```\n@deloras\n```\nthen @arlie')).toEqual(['arlie']);
  });

  it('ignores mentions inside a tilde-fenced code block', () => {
    expect(extractMentionedUsernames('~~~\n@deloras\n~~~\nthen @arlie')).toEqual(['arlie']);
  });
});

describe('prioritizeMentionedMembers', () => {
  const members = [{ username: 'root' }, { username: 'milford' }, { username: 'nancee_simonis' }];

  it('returns the members unchanged when nothing is mentioned', () => {
    expect(prioritizeMentionedMembers(members, [])).toBe(members);
  });

  it('floats mentioned members to the top in mention order', () => {
    expect(prioritizeMentionedMembers(members, ['nancee_simonis', 'root'])).toEqual([
      { username: 'nancee_simonis' },
      { username: 'root' },
      { username: 'milford' },
    ]);
  });

  it('matches usernames case-insensitively', () => {
    expect(prioritizeMentionedMembers(members, ['NANCEE_SIMONIS'])).toEqual([
      { username: 'nancee_simonis' },
      { username: 'root' },
      { username: 'milford' },
    ]);
  });

  it('ignores mentioned usernames that are not in the member list', () => {
    expect(prioritizeMentionedMembers(members, ['ghost'])).toEqual(members);
  });

  it('keeps members without a username among the non-prioritized group', () => {
    const withGroup = [{ username: 'root' }, { name: 'No username' }, { username: 'milford' }];

    expect(prioritizeMentionedMembers(withGroup, ['milford'])).toEqual([
      { username: 'milford' },
      { username: 'root' },
      { name: 'No username' },
    ]);
  });
});

describe('threadParticipantUsernames', () => {
  beforeEach(() => {
    setCurrentUser({ username: 'root' });
  });

  it('lists unique authors, most recent first, without the current user', () => {
    const authors = [
      { username: 'milford' },
      { username: 'Nancee_Simonis' },
      { username: 'root' },
      { username: 'milford' },
    ];

    expect(threadParticipantUsernames(authors)).toEqual(['milford', 'nancee_simonis']);
  });

  it('skips notes without an author', () => {
    expect(threadParticipantUsernames([null, { username: 'milford' }])).toEqual(['milford']);
  });

  describe('in a long thread', () => {
    const others = Array.from({ length: 10 }, (_, i) => ({ username: `user${i}` }));

    it('keeps the 8 most recent authors and the one who started the thread', () => {
      const authors = [{ username: 'starter' }, ...others];

      expect(threadParticipantUsernames(authors)).toEqual([
        'user9',
        'user8',
        'user7',
        'user6',
        'user5',
        'user4',
        'user3',
        'user2',
        'starter',
      ]);
    });

    it('keeps the 9 most recent authors when the thread starter replied recently', () => {
      const authors = [{ username: 'starter' }, ...others, { username: 'starter' }];

      expect(threadParticipantUsernames(authors)).toEqual([
        'starter',
        'user9',
        'user8',
        'user7',
        'user6',
        'user5',
        'user4',
        'user3',
        'user2',
      ]);
    });
  });
});

describe('demoteCurrentUser', () => {
  const members = [{ username: 'root' }, { username: 'milford' }, { username: 'nancee_simonis' }];

  it('returns the members unchanged when signed out', () => {
    expect(demoteCurrentUser(members)).toBe(members);
  });

  it('returns the members unchanged when the signed-in user is not listed', () => {
    setCurrentUser({ username: 'ghost' });

    expect(demoteCurrentUser(members)).toBe(members);
  });

  it('moves the signed-in user to the end', () => {
    setCurrentUser({ username: 'ROOT' });

    expect(demoteCurrentUser(members).map(({ username }) => username)).toEqual([
      'milford',
      'nancee_simonis',
      'root',
    ]);
  });

  it('moves the signed-in user to the end of their tier only', () => {
    setCurrentUser({ username: 'root' });
    const tierOf = ({ username }) => (username === 'nancee_simonis' ? 1 : 0);

    expect(demoteCurrentUser(members, tierOf).map(({ username }) => username)).toEqual([
      'milford',
      'root',
      'nancee_simonis',
    ]);
  });
});
