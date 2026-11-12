import {
  getAbsolutePermalinkPath,
  isBlobRoute,
  withContinueTo,
  withGitpodTarget,
} from '~/repository/components/header_area/utils';
import * as urlUtility from '~/lib/utils/url_utility';

describe('isBlobRoute', () => {
  it.each`
    route                          | expected
    ${{ name: 'blobPathDecoded' }} | ${true}
    ${{ name: 'treePathDecoded' }} | ${false}
    ${{}}                          | ${false}
    ${undefined}                   | ${false}
  `('returns $expected for $route', ({ route, expected }) => {
    expect(isBlobRoute(route)).toBe(expected);
  });
});

describe('withContinueTo', () => {
  // Shape of TreeHelper#breadcrumb_data_attributes fork paths, encoded by Rails `to_query`
  const forkPath =
    '/group/project/-/forks?continue%5Bnotice%5D=You+forked+it.+Try+again.&continue%5Bnotice_now%5D=Forking+now&continue%5Bto%5D=%2Fgroup%2Fproject%2F-%2Ftree%2Fmain%2Fold&namespace_key=42';

  const paramsOf = (url) => urlUtility.queryToObject(url.split('?')[1]);

  it.each(['', null, undefined])('returns %p unchanged', (path) => {
    expect(withContinueTo(path, '/group/project/-/tree/main/new')).toBe(path);
  });

  it('replaces only `continue[to]`', () => {
    expect(paramsOf(withContinueTo(forkPath, '/group/project/-/tree/main/new'))).toEqual({
      'continue[notice]': 'You forked it. Try again.',
      'continue[notice_now]': 'Forking now',
      'continue[to]': '/group/project/-/tree/main/new',
      namespace_key: '42',
    });
  });

  it('keeps the path and fragment', () => {
    const result = withContinueTo(`${forkPath}#fragment`, '/new');

    expect(result.startsWith('/group/project/-/forks?')).toBe(true);
    expect(result.endsWith('#fragment')).toBe(true);
  });

  it.each`
    description        | to
    ${'spaces'}        | ${'/group/project/-/tree/main/dir%20with%20spaces'}
    ${'a hash'}        | ${'/group/project/-/tree/main/a%23b'}
    ${'non-ASCII'}     | ${'/group/project/-/tree/main/%C3%BCber'}
    ${'a query param'} | ${'/group/project/-/tree/main/dir?ref_type=heads'}
  `('round-trips a destination with $description', ({ to }) => {
    expect(paramsOf(withContinueTo(forkPath, to))['continue[to]']).toBe(to);
  });
});

describe('withGitpodTarget', () => {
  const target = 'https://gitlab.com/group/project/-/tree/main/new';

  it.each(['', null, undefined])('returns an empty string when the Gitpod URL is %p', (url) => {
    expect(withGitpodTarget(url, target)).toBe('');
  });

  it.each`
    description                                 | gitpodUrl                                                                     | expected
    ${'replaces the target'}                    | ${'https://gitpod.io/#https://gitlab.com/group/project/-/tree/main/old'}      | ${`https://gitpod.io/#${target}`}
    ${'splits at the last #'}                   | ${'https://gitpod.io/#/app#https://gitlab.com/group/project/-/tree/main/old'} | ${`https://gitpod.io/#/app#${target}`}
    ${'ignores an encoded # in the old target'} | ${'https://gitpod.io/#https://gitlab.com/group/project/-/tree/main/a%23b'}    | ${`https://gitpod.io/#${target}`}
    ${'appends a target when none exists'}      | ${'https://gitpod.io/'}                                                       | ${`https://gitpod.io/#${target}`}
  `('$description', ({ gitpodUrl, expected }) => {
    expect(withGitpodTarget(gitpodUrl, target)).toBe(expected);
  });

  it('sets a target that contains an encoded #, spaces and non-ASCII characters', () => {
    const encodedTarget = 'https://gitlab.com/group/project/-/tree/main/a%23b/c%20d/%C3%BCber';

    expect(withGitpodTarget('https://gitpod.io/#https://gitlab.com/old', encodedTarget)).toBe(
      `https://gitpod.io/#${encodedTarget}`,
    );
  });
});

describe('getAbsolutePermalinkPath', () => {
  const permalinkPath = '/project/repo/-/blob/main/file.js';
  const baseUrl = 'https://gitlab.example.com';
  const absolutePath = 'https://gitlab.example.com/project/repo/-/blob/main/file.js';

  beforeEach(() => {
    jest.spyOn(urlUtility, 'getBaseURL').mockReturnValue(baseUrl);
    jest.spyOn(urlUtility, 'relativePathToAbsolute').mockReturnValue(absolutePath);
  });

  describe('when hash is not provided', () => {
    it.each([
      ['null', null],
      ['empty string', ''],
      ['undefined', undefined],
    ])('returns absolute path when hash is %s', (_, hash) => {
      expect(getAbsolutePermalinkPath(permalinkPath, hash)).toBe(absolutePath);
    });
  });

  describe('when handling different hash formats', () => {
    it.each([
      ['line number format', '#L6', '#L6'],
      ['line number range format', '#L10-19', '#L10-19'],
      [
        'anchor hash',
        '#developer-certificate-of-origin--license',
        '#developer-certificate-of-origin--license',
      ],
    ])('handles %s (%s)', (_, hash, expectedHash) => {
      expect(getAbsolutePermalinkPath(permalinkPath, hash)).toBe(`${absolutePath}${expectedHash}`);
    });
  });

  describe('when hash normalization is needed', () => {
    it.each([
      ['line number', 'L6', '#L6'],
      ['line number range', 'L10-19', '#L10-19'],
      [
        'complex anchor',
        'developer-certificate-of-origin--license',
        '#developer-certificate-of-origin--license',
      ],
    ])('normalizes %s hash by adding # prefix when missing', (_, hash, expectedHash) => {
      expect(getAbsolutePermalinkPath(permalinkPath, hash)).toBe(`${absolutePath}${expectedHash}`);
    });
  });

  describe('when additional query params are provided', () => {
    it('includes blame=1 in the permalink URL', () => {
      expect(getAbsolutePermalinkPath(permalinkPath, '#L6', { blame: '1' })).toBe(
        `${absolutePath}?blame=1#L6`,
      );
    });

    it('ignores empty or null query param values', () => {
      expect(getAbsolutePermalinkPath(permalinkPath, '#L6', { blame: '' })).toBe(
        `${absolutePath}#L6`,
      );
    });

    it('does not include blame when queryParams is empty', () => {
      expect(getAbsolutePermalinkPath(permalinkPath, '#L6', {})).toBe(`${absolutePath}#L6`);
    });
  });
});
