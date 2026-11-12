import * as epicUtils from 'ee/roadmap/utils/epic_utils';

describe('addIsChildEpicTrueProperty', () => {
  const title = 'Lorem ipsum dolar sit';
  const description = 'Beatae suscipit dolorum nihil quidem est accusamus';
  const obj = {
    title,
    description,
  };
  let newObj;

  beforeEach(() => {
    newObj = epicUtils.addIsChildEpicTrueProperty(obj);
  });

  it('adds `isChildEpic` property with value `true`', () => {
    expect(newObj.isChildEpic).toBe(true);
  });

  it('has original properties in returned object', () => {
    expect(newObj.title).toBe(title);
    expect(newObj.description).toBe(description);
  });
});

describe('generateKey', () => {
  it('returns epic namespaced key for an epic object', () => {
    const obj = {
      id: 3,
      title: 'Lorem ipsum dolar sit',
      isChildEpic: false,
    };

    expect(epicUtils.generateKey(obj)).toBe('epic-3');
  });

  it('returns child-epic- namespaced key for a child epic object', () => {
    const obj = {
      id: 3,
      title: 'Lorem ipsum dolar sit',
      isChildEpic: true,
    };

    expect(epicUtils.generateKey(obj)).toBe('child-epic-3');
  });
});

describe('scrollToCurrentDay', () => {
  const createShell = ({ withIndicator = true } = {}) => {
    document.body.innerHTML = `
      <div class="js-roadmap-shell">
        <div class="section">
          ${withIndicator ? '<span class="js-current-day-indicator"></span>' : ''}
        </div>
      </div>`;

    const shell = document.querySelector('.js-roadmap-shell');
    const section = document.querySelector('.section');
    const indicator = document.querySelector('.js-current-day-indicator');

    jest.spyOn(shell, 'getBoundingClientRect').mockReturnValue({ left: 100 });
    Object.defineProperty(shell, 'clientWidth', { value: 400, configurable: true });
    shell.scrollLeft = 50;

    if (indicator) {
      jest.spyOn(indicator, 'scrollIntoView').mockImplementation();
      jest.spyOn(indicator, 'getBoundingClientRect').mockReturnValue({ left: 700, width: 2 });
    }

    return { shell, section, indicator };
  };

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('horizontally centers the current day indicator within the roadmap shell', () => {
    const { shell, section } = createShell();

    epicUtils.scrollToCurrentDay(section);

    // 700 - 100 + 50 (offset in content) + 1 (half indicator) - 200 (half shell)
    expect(shell.scrollLeft).toBe(451);
  });

  it('does not call `scrollIntoView`, which would scroll ancestors and vertically', () => {
    const { section, indicator } = createShell();

    epicUtils.scrollToCurrentDay(section);

    expect(indicator.scrollIntoView).not.toHaveBeenCalled();
  });

  it('does nothing when there is no current day indicator', () => {
    const { shell, section } = createShell({ withIndicator: false });

    epicUtils.scrollToCurrentDay(section);

    expect(shell.scrollLeft).toBe(50);
  });

  it('does nothing when there is no roadmap shell', () => {
    document.body.innerHTML =
      '<div class="section"><span class="js-current-day-indicator"></span></div>';
    const section = document.querySelector('.section');
    const indicator = document.querySelector('.js-current-day-indicator');
    jest.spyOn(indicator, 'scrollIntoView').mockImplementation();

    expect(() => epicUtils.scrollToCurrentDay(section)).not.toThrow();
    expect(indicator.scrollIntoView).not.toHaveBeenCalled();
  });
});

describe('transformFetchEpicFilterParams', () => {
  it('should return congregated `not[]` params in a single key', () => {
    const filterParams = {
      'not[authorUsername]': 'foo',
      'not[myReactionEmoji]': ':emoji:',
      authorUsername: 'baz',
    };

    expect(epicUtils.transformFetchEpicFilterParams(filterParams)).toEqual({
      not: {
        authorUsername: 'foo',
        myReactionEmoji: ':emoji:',
      },
      authorUsername: 'baz',
    });
  });

  it('should return congregated `or[]` params in a single key', () => {
    const filterParams = {
      'or[labelName]': ['foo', 'bar'],
      'or[authorUsername]': ['boo', 'baa'],
      authorUsername: 'baz',
    };

    expect(epicUtils.transformFetchEpicFilterParams(filterParams)).toEqual({
      or: {
        labelName: ['foo', 'bar'],
        authorUsername: ['boo', 'baa'],
      },
      authorUsername: 'baz',
    });
  });
});
