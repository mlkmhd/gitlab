import { GlFormCheckbox, GlToggle } from '@gitlab/ui';
import MockAdapter from 'axios-mock-adapter';
import { nextTick } from 'vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import waitForPromises from 'helpers/wait_for_promises';
import axios from '~/lib/utils/axios_utils';
import { HTTP_STATUS_OK, HTTP_STATUS_UNPROCESSABLE_ENTITY } from '~/lib/utils/http_status';
import { createAlert } from '~/alert';
import CascadingLockIcon from '~/namespaces/cascading_settings/components/cascading_lock_icon.vue';
import AiGovernanceSettingsForm from 'ee/ai/settings/components/ai_governance_settings_form.vue';
import DuoAuditEventStorageForm from 'ee/ai/settings/components/duo_audit_event_storage_form.vue';

jest.mock('~/alert');

const updatePath = '/groups/my-group/-/settings/secure/ai_governance';

describe('AiGovernanceSettingsForm', () => {
  let wrapper;
  let mockAxios;

  const createComponent = ({ props = {}, storageCascadingSettings = {} } = {}) => {
    wrapper = shallowMountExtended(AiGovernanceSettingsForm, {
      propsData: {
        initialAiGovernanceEnabled: false,
        initialLockAiGovernanceEnabled: false,
        initialLockAiAuditEventsStorageEnabled: false,
        cascadingSettings: {},
        updatePath,
        ...props,
      },
      provide: {
        aiAuditEventsStorageEnabled: false,
        aiAuditEventsStorageCascadingSettings: storageCascadingSettings,
      },
      stubs: { GlToggle, GlFormCheckbox },
    });
  };

  const findToggle = () => wrapper.findComponent(GlToggle);
  const findCheckboxByTestId = (testId) =>
    wrapper
      .findAllComponents(GlFormCheckbox)
      .wrappers.find((checkbox) => checkbox.find(`[data-testid="${testId}"]`).exists()) ??
    wrapper.findComponent({ name: 'NonExistent' });
  const findLockCheckbox = () => findCheckboxByTestId('enforce-for-all-subgroups-checkbox');
  const findStorageLockCheckbox = () =>
    findCheckboxByTestId('enforce-storage-for-all-subgroups-checkbox');
  const findLockIcon = () => wrapper.findComponent(CascadingLockIcon);
  const findAuditEventStorageForm = () => wrapper.findComponent(DuoAuditEventStorageForm);
  const requestBody = () => JSON.parse(mockAxios.history.patch[0].data);

  beforeEach(() => {
    mockAxios = new MockAdapter(axios);
    mockAxios.onPatch(updatePath).reply(HTTP_STATUS_OK, {});
  });

  afterEach(() => {
    mockAxios.restore();
  });

  describe('AI Governance toggle', () => {
    it('renders with the initial value and label', () => {
      createComponent({ props: { initialAiGovernanceEnabled: true } });

      expect(findToggle().props('value')).toBe(true);
      expect(findToggle().text()).toContain('Enable AI Governance');
    });

    it('saves the new value and shows a success alert', async () => {
      createComponent();

      findToggle().vm.$emit('change', true);
      await waitForPromises();

      expect(requestBody()).toEqual({ group: { ai_governance_enabled: true } });
      expect(findToggle().props('value')).toBe(true);
      expect(createAlert).toHaveBeenCalledWith({
        message: 'AI Governance settings were successfully updated.',
        variant: 'success',
      });
    });

    it('reverts the value and shows the error when the save fails', async () => {
      mockAxios
        .onPatch(updatePath)
        .reply(HTTP_STATUS_UNPROCESSABLE_ENTITY, { message: 'Setting is locked' });
      createComponent();

      findToggle().vm.$emit('change', true);
      await waitForPromises();

      expect(findToggle().props('value')).toBe(false);
      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({ message: 'Setting is locked', captureError: true }),
      );
    });
  });

  describe('lock checkbox', () => {
    it('renders with the initial value and the cascading settings strings', () => {
      createComponent({ props: { initialLockAiGovernanceEnabled: true } });

      expect(findLockCheckbox().props('checked')).toBe(true);
      expect(findLockCheckbox().text()).toContain('Enforce for all subgroups');
      expect(findLockCheckbox().text()).toContain('Subgroups cannot change this setting.');
    });

    it('saves the lock together with the current value', async () => {
      createComponent({ props: { initialAiGovernanceEnabled: true } });

      findLockCheckbox().vm.$emit('change', true);
      await waitForPromises();

      expect(requestBody()).toEqual({
        group: { ai_governance_enabled: true, lock_ai_governance_enabled: true },
      });
    });
  });

  describe('when not locked', () => {
    beforeEach(() => {
      createComponent({
        props: {
          cascadingSettings: { lockedByAncestor: false, lockedByApplicationSetting: false },
        },
      });
    });

    it('enables the toggle', () => {
      expect(findToggle().props('disabled')).toBe(false);
    });

    it('does not render the lock icon', () => {
      expect(findLockIcon().exists()).toBe(false);
    });

    it('renders the lock checkbox', () => {
      expect(findLockCheckbox().exists()).toBe(true);
    });
  });

  describe.each`
    description                  | cascadingSettings
    ${'by an ancestor'}          | ${{ lockedByAncestor: true, lockedByApplicationSetting: false, ancestorNamespace: { fullName: 'Root', path: '/groups/root/-/edit' } }}
    ${'by the instance setting'} | ${{ lockedByAncestor: false, lockedByApplicationSetting: true }}
  `('when locked $description', ({ cascadingSettings }) => {
    beforeEach(() => {
      createComponent({ props: { cascadingSettings } });
    });

    it('disables the toggle', () => {
      expect(findToggle().props('disabled')).toBe(true);
    });

    it('renders the lock icon', () => {
      expect(findLockIcon().props()).toEqual({
        isLockedByGroupAncestor: cascadingSettings.lockedByAncestor,
        isLockedByApplicationSettings: cascadingSettings.lockedByApplicationSetting,
        ancestorNamespace: cascadingSettings.ancestorNamespace ?? null,
      });
    });

    it('does not render the lock checkbox', () => {
      expect(findLockCheckbox().exists()).toBe(false);
    });
  });

  describe('AI audit event storage', () => {
    it('passes the AI Governance tooltip', () => {
      createComponent();

      expect(findAuditEventStorageForm().props('disabledTooltip')).toBe(
        'Turn on AI Governance to change this setting.',
      );
    });

    it.each`
      initialAiGovernanceEnabled | disabledCheckbox
      ${false}                   | ${true}
      ${true}                    | ${false}
    `(
      'sets disabledCheckbox to $disabledCheckbox when AI Governance is $initialAiGovernanceEnabled',
      ({ initialAiGovernanceEnabled, disabledCheckbox }) => {
        createComponent({ props: { initialAiGovernanceEnabled } });

        expect(findAuditEventStorageForm().props('disabledCheckbox')).toBe(disabledCheckbox);
      },
    );

    it('enables the storage setting after AI Governance is turned on', async () => {
      createComponent();

      findToggle().vm.$emit('change', true);
      await waitForPromises();

      expect(findAuditEventStorageForm().props('disabledCheckbox')).toBe(false);
    });

    it('disables the governance toggle while saving the storage setting', async () => {
      createComponent({ props: { initialAiGovernanceEnabled: true } });

      findAuditEventStorageForm().vm.$emit('change', true);
      await nextTick();

      expect(findToggle().props('disabled')).toBe(true);
      expect(findAuditEventStorageForm().props('disabledCheckbox')).toBe(true);
      expect(findAuditEventStorageForm().props('disabledTooltip')).toBe('');

      await waitForPromises();

      expect(findToggle().props('disabled')).toBe(false);
      expect(findAuditEventStorageForm().props('disabledCheckbox')).toBe(false);
    });

    it('saves the storage setting when it changes', async () => {
      createComponent({ props: { initialAiGovernanceEnabled: true } });

      findAuditEventStorageForm().vm.$emit('change', true);
      await waitForPromises();

      expect(requestBody()).toEqual({ group: { ai_audit_events_storage_enabled: true } });
      expect(findAuditEventStorageForm().props('checked')).toBe(true);
    });

    it('reverts the storage setting and shows the error when the save fails', async () => {
      mockAxios
        .onPatch(updatePath)
        .reply(HTTP_STATUS_UNPROCESSABLE_ENTITY, { message: 'Setting is locked' });
      createComponent({ props: { initialAiGovernanceEnabled: true } });

      findAuditEventStorageForm().vm.$emit('change', true);
      await waitForPromises();

      expect(findAuditEventStorageForm().props('checked')).toBe(false);
      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({ message: 'Setting is locked', captureError: true }),
      );
    });
  });

  describe('AI audit event storage lock checkbox', () => {
    it('renders with the initial value and the cascading settings strings', () => {
      createComponent({ props: { initialLockAiAuditEventsStorageEnabled: true } });

      expect(findStorageLockCheckbox().props('checked')).toBe(true);
      expect(findStorageLockCheckbox().text()).toContain('Enforce for all subgroups');
      expect(findStorageLockCheckbox().text()).toContain('Subgroups cannot change this setting.');
    });

    it('saves the lock together with the current storage value', async () => {
      createComponent({ props: { initialAiGovernanceEnabled: true } });

      findStorageLockCheckbox().vm.$emit('change', true);
      await waitForPromises();

      expect(requestBody()).toEqual({
        group: {
          ai_audit_events_storage_enabled: false,
          lock_ai_audit_events_storage_enabled: true,
        },
      });
      expect(findStorageLockCheckbox().props('checked')).toBe(true);
    });

    it('is independent of the AI Governance lock', async () => {
      createComponent({ props: { initialAiGovernanceEnabled: true } });

      findStorageLockCheckbox().vm.$emit('change', true);
      await waitForPromises();

      expect(findLockCheckbox().props('checked')).toBe(false);
    });

    it('reverts the lock and shows the error when the save fails', async () => {
      mockAxios
        .onPatch(updatePath)
        .reply(HTTP_STATUS_UNPROCESSABLE_ENTITY, { message: 'Setting is locked' });
      createComponent({ props: { initialAiGovernanceEnabled: true } });

      findStorageLockCheckbox().vm.$emit('change', true);
      await waitForPromises();

      expect(findStorageLockCheckbox().props('checked')).toBe(false);
      expect(createAlert).toHaveBeenCalledWith(
        expect.objectContaining({ message: 'Setting is locked', captureError: true }),
      );
    });

    it.each`
      initialAiGovernanceEnabled | disabled
      ${false}                   | ${true}
      ${true}                    | ${false}
    `(
      'sets disabled to $disabled when AI Governance is $initialAiGovernanceEnabled',
      ({ initialAiGovernanceEnabled, disabled }) => {
        createComponent({ props: { initialAiGovernanceEnabled } });

        expect(findStorageLockCheckbox().props('disabled')).toBe(disabled);
      },
    );

    it('is disabled while saving', async () => {
      createComponent({ props: { initialAiGovernanceEnabled: true } });

      findStorageLockCheckbox().vm.$emit('change', true);
      await nextTick();

      expect(findStorageLockCheckbox().props('disabled')).toBe(true);

      await waitForPromises();

      expect(findStorageLockCheckbox().props('disabled')).toBe(false);
    });

    describe.each`
      description                  | storageCascadingSettings
      ${'by an ancestor'}          | ${{ lockedByAncestor: true, lockedByApplicationSetting: false }}
      ${'by the instance setting'} | ${{ lockedByAncestor: false, lockedByApplicationSetting: true }}
    `('when storage is locked $description', ({ storageCascadingSettings }) => {
      it('does not render the checkbox', () => {
        createComponent({ storageCascadingSettings });

        expect(findStorageLockCheckbox().exists()).toBe(false);
      });
    });

    it('is not hidden when only AI Governance is locked', () => {
      createComponent({ props: { cascadingSettings: { lockedByAncestor: true } } });

      expect(findStorageLockCheckbox().exists()).toBe(true);
    });
  });
});
