import { waitFor } from '@testing-library/vue';
import { lastRequestVariables } from 'ee_jest/integration/core/operation_helpers';
import { setQueryVariant } from 'ee_jest/integration/helpers/setup_utils';
import { getText, waitAndClick, waitForElement } from 'ee_jest/integration/helpers/test_helpers';
import groupSettingsVariants from './fixture_variants/get_orbit_group_settings';
import orbitUpdateVariants, { ORBIT_UPDATE_ERROR } from './fixture_variants/orbit_update';
import {
  ORBIT_PATH,
  findActionError,
  findSettingsPage,
  findStatusAlert,
  findToggle,
  findTrialEndedAlert,
  findTurnOnConfirmButton,
  mountGroupSettings,
} from './test_setup';

const turnOn = async () => {
  await waitAndClick(findToggle);
  await waitAndClick(findTurnOnConfirmButton);
};

describe('Orbit group settings page', () => {
  describe('when Orbit is off', () => {
    beforeEach(() => {
      mountGroupSettings();
    });

    describe('and the user turns it on', () => {
      beforeEach(async () => {
        await turnOn();
      });

      it('shows the indexing state', async () => {
        const alert = await waitForElement(findStatusAlert);

        expect(getText(alert)).toContain('GitLab Orbit is indexing orbit-fixtures');
      });

      it('shows the toggle on', async () => {
        await waitFor(() => expect(findToggle().getAttribute('aria-checked')).toBe('true'));
      });

      it('sends the group path to the update', async () => {
        await waitFor(() =>
          expect(lastRequestVariables('orbitUpdate')).toEqual({
            input: { groupPath: 'orbit-fixtures', enabled: true },
          }),
        );
      });
    });

    describe('when the update fails', () => {
      beforeEach(() => {
        setQueryVariant(orbitUpdateVariants).withError();
      });

      describe('and the user turns it on', () => {
        beforeEach(async () => {
          await turnOn();
        });

        it('shows the error', async () => {
          const error = await waitForElement(findActionError);

          expect(getText(error)).toContain(ORBIT_UPDATE_ERROR);
        });

        it('keeps the toggle off', async () => {
          await waitForElement(findActionError);
          await waitFor(() => expect(findToggle().getAttribute('aria-checked')).toBe('false'));

          expect(findStatusAlert()).toBeNull();
        });
      });
    });
  });

  describe('when Orbit is on', () => {
    describe('and indexing is ready', () => {
      beforeEach(() => {
        setQueryVariant(groupSettingsVariants).ready();
        mountGroupSettings();
      });

      it('links to the Orbit dashboard', async () => {
        const alert = await waitForElement(findStatusAlert);

        expect(getText(alert)).toContain('GitLab Orbit is ready for orbit-fixtures');
        expect(alert.querySelector(`a[href="${ORBIT_PATH}"]`)).not.toBeNull();
      });
    });
  });

  describe('when the trial has ended', () => {
    beforeEach(() => {
      setQueryVariant(groupSettingsVariants).trialEnded();
      mountGroupSettings();
    });

    it('shows the trial ended alert', async () => {
      expect(await waitForElement(findTrialEndedAlert)).not.toBeNull();
    });

    it('hides the toggle', async () => {
      await waitForElement(findTrialEndedAlert);

      expect(findSettingsPage()).not.toBeNull();
      expect(findToggle()).toBeNull();
    });
  });
});
