import { setHTMLFixture, resetHTMLFixture } from 'helpers/fixtures';
import { initDeepReviewToggle } from 'ee/duo_code_review/init_deep_review_toggle';

describe('initDeepReviewToggle', () => {
  const findCheckbox = () => document.querySelector('.js-duo-code-review-deep-allowed');
  const findStandard = () => document.querySelector('.js-duo-code-review-standard-depth');
  const findDeep = () => document.querySelector('.js-duo-code-review-deep-depth');

  const setUpFixture = ({ allowed = true, depth = 'deep' } = {}) => {
    setHTMLFixture(`
      <form>
        <input type="checkbox" class="js-duo-code-review-deep-allowed" ${allowed ? 'checked' : ''} />
        <input type="radio" name="depth" value="standard" class="js-duo-code-review-standard-depth"
          ${depth === 'standard' ? 'checked' : ''} />
        <input type="radio" name="depth" value="deep" class="js-duo-code-review-deep-depth"
          ${depth === 'deep' ? 'checked' : ''} />
      </form>
    `);
  };

  const setAllowed = (checked) => {
    findCheckbox().checked = checked;
    findCheckbox().dispatchEvent(new Event('change'));
  };

  afterEach(() => {
    resetHTMLFixture();
  });

  it('keeps the depth options enabled when deep reviews are allowed', () => {
    setUpFixture();
    initDeepReviewToggle();

    expect(findStandard().disabled).toBe(false);
    expect(findDeep().disabled).toBe(false);
    expect(findDeep().checked).toBe(true);
  });

  it('disables the depth options on load, without changing the value, when deep reviews are not allowed', () => {
    setUpFixture({ allowed: false });
    initDeepReviewToggle();

    expect(findStandard().disabled).toBe(true);
    expect(findDeep().disabled).toBe(true);
    expect(findDeep().checked).toBe(true);
  });

  it('does not submit the depth while deep reviews are not allowed', () => {
    setUpFixture({ allowed: false });
    initDeepReviewToggle();

    expect(new FormData(document.querySelector('form')).has('depth')).toBe(false);
  });

  it('disables the depth options when the checkbox is cleared', () => {
    setUpFixture();
    initDeepReviewToggle();

    setAllowed(false);

    expect(findStandard().disabled).toBe(true);
    expect(findDeep().disabled).toBe(true);
  });

  it('enables the depth options without changing the value when the checkbox is selected', () => {
    setUpFixture({ allowed: false, depth: 'standard' });
    initDeepReviewToggle();

    setAllowed(true);

    expect(findStandard().disabled).toBe(false);
    expect(findDeep().disabled).toBe(false);
    expect(findStandard().checked).toBe(true);
  });

  it('does nothing when the settings are not on the page', () => {
    setHTMLFixture('<form></form>');

    expect(() => initDeepReviewToggle()).not.toThrow();
  });
});
