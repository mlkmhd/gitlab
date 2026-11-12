import { getByRole } from '@testing-library/dom';
import { setHTMLFixture, resetHTMLFixture } from 'helpers/fixtures';
import waitForPromises from 'helpers/wait_for_promises';
import { confirmAction } from '~/lib/utils/confirm_via_gl_modal/confirm_action';
import { initPgAshIntervalConfirm } from '~/admin/application_settings/pg_ash_interval_confirm';

jest.mock('~/lib/utils/confirm_via_gl_modal/confirm_action');

describe('initPgAshIntervalConfirm', () => {
  let input;
  let form;
  let submittedByBrowser;

  const saveWithInterval = async (value) => {
    input.value = value;
    getByRole(document.body, 'button', { name: 'Save changes' }).click();
    await waitForPromises();
  };

  beforeEach(() => {
    setHTMLFixture(`
      <form>
        <label for="interval">Sample interval (seconds)</label>
        <input id="interval" type="number" class="js-pg-ash-sample-interval" value="1" min="1" max="60">
        <button type="submit">Save changes</button>
      </form>
    `);
    input = getByRole(document.body, 'spinbutton', { name: 'Sample interval (seconds)' });
    form = input.form;
    form.submit = jest.fn();
    submittedByBrowser = undefined;

    initPgAshIntervalConfirm();
    form.addEventListener('submit', (event) => {
      submittedByBrowser = !event.defaultPrevented;
      event.preventDefault();
    });
  });

  afterEach(() => {
    resetHTMLFixture();
  });

  describe('when the interval differs from the saved one', () => {
    beforeEach(async () => {
      confirmAction.mockResolvedValue(true);
      await saveWithInterval('5');
    });

    it('stops the save to ask with a titled danger confirmation that names the change', () => {
      expect(submittedByBrowser).toBe(false);
      expect(confirmAction).toHaveBeenCalledWith(
        'Changing the sample interval deletes all collected active session history. This action cannot be undone.',
        {
          title: 'Change the sample interval?',
          primaryBtnText: 'Change interval',
          primaryBtnVariant: 'danger',
        },
      );
    });

    it('saves once the change is confirmed', () => {
      expect(form.submit).toHaveBeenCalledTimes(1);
    });
  });

  describe('when the confirmation is cancelled', () => {
    it('does not save', async () => {
      confirmAction.mockResolvedValue(false);
      await saveWithInterval('5');

      expect(form.submit).not.toHaveBeenCalled();
    });
  });

  describe.each(['01', '1.0'])('when the interval is the saved one written as %s', (value) => {
    it('saves without a confirmation', async () => {
      await saveWithInterval(value);

      expect(confirmAction).not.toHaveBeenCalled();
      expect(submittedByBrowser).toBe(true);
    });
  });

  describe('when 10 is saved and 1e1 is entered, which the server saves as 1', () => {
    it('asks for a confirmation', async () => {
      input.defaultValue = '10';
      await saveWithInterval('1e1');

      expect(confirmAction).toHaveBeenCalled();
    });
  });
});
