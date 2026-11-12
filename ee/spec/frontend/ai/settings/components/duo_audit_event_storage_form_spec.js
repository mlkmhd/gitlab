import { shallowMount } from '@vue/test-utils';
import { GlFormCheckbox, GlFormGroup } from '@gitlab/ui';
import { extendedWrapper } from 'helpers/vue_test_utils_helper';
import { createMockDirective, getBinding } from 'helpers/vue_mock_directive';
import CascadingLockIcon from '~/namespaces/cascading_settings/components/cascading_lock_icon.vue';
import DuoAuditEventStorageForm from 'ee/ai/settings/components/duo_audit_event_storage_form.vue';

describe('DuoAuditEventStorageForm', () => {
  let wrapper;

  const createComponent = ({
    props = {},
    injectedProps = {},
    mockTooltipDirective = true,
  } = {}) => {
    wrapper = extendedWrapper(
      shallowMount(DuoAuditEventStorageForm, {
        provide: {
          aiAuditEventsStorageEnabled: false,
          aiAuditEventsStorageCascadingSettings: null,
          ...injectedProps,
        },
        propsData: {
          ...props,
        },
        stubs: {
          GlFormCheckbox,
          GlFormGroup,
        },
        // Under Vue 3, the mock tooltip directive prevents `setProps` from updating props.
        directives: mockTooltipDirective ? { GlTooltip: createMockDirective('gl-tooltip') } : null,
      }),
    );
  };

  const findTitle = () => wrapper.findComponent(GlFormGroup);
  const findCheckbox = () => wrapper.findComponent(GlFormCheckbox);
  const findCascadingLockIcon = () => wrapper.findComponent(CascadingLockIcon);

  beforeEach(() => {
    createComponent();
  });

  it('has the correct title', () => {
    expect(findTitle().attributes('label')).toBe('AI audit event storage');
  });

  it('has the correct label', () => {
    expect(findCheckbox().text()).toContain('Store AI audit events');
  });

  it('has the correct help text', () => {
    expect(findCheckbox().text()).toContain(
      'When you turn on this setting, GitLab stores new AI audit events to the database or ClickHouse and to the audit log file (audit_json.log). Real-time streaming of AI audit events is not affected.',
    );
  });

  it('renders the checkbox unchecked by default', () => {
    expect(findCheckbox().props('checked')).toBe(false);
  });

  it.each`
    aiAuditEventsStorageEnabled | description
    ${true}                     | ${'checked'}
    ${false}                    | ${'unchecked'}
  `(
    'renders the checkbox as $description when aiAuditEventsStorageEnabled is set to $aiAuditEventsStorageEnabled',
    ({ aiAuditEventsStorageEnabled }) => {
      createComponent({ injectedProps: { aiAuditEventsStorageEnabled } });

      expect(findCheckbox().props('checked')).toBe(aiAuditEventsStorageEnabled);
    },
  );

  describe('checked prop', () => {
    it('keeps the injected value when the checked prop is not passed', () => {
      createComponent({ injectedProps: { aiAuditEventsStorageEnabled: true } });

      expect(findCheckbox().props('checked')).toBe(true);
    });

    it('updates the checkbox when the checked prop changes', async () => {
      createComponent({
        props: { checked: true },
        injectedProps: { aiAuditEventsStorageEnabled: true },
        mockTooltipDirective: false,
      });

      await wrapper.setProps({ checked: false });

      expect(findCheckbox().props('checked')).toBe(false);
    });
  });

  it('emits change event with the new value when the checkbox is toggled', () => {
    findCheckbox().vm.$emit('input', true);
    findCheckbox().vm.$emit('change', true);

    expect(wrapper.emitted('change')).toEqual([[true]]);
  });

  it('disables the checkbox when disabledCheckbox prop is true', () => {
    createComponent({ props: { disabledCheckbox: true } });

    expect(findCheckbox().props('disabled')).toBe(true);
  });

  it('does not disable the checkbox when disabledCheckbox prop is false', () => {
    createComponent({ props: { disabledCheckbox: false } });

    expect(findCheckbox().props('disabled')).toBe(false);
  });

  describe('disabled tooltip', () => {
    const findTooltip = () =>
      getBinding(wrapper.findByTestId('ai-audit-events-storage-label').element, 'gl-tooltip');

    it('shows the default tooltip when the checkbox is disabled', () => {
      createComponent({ props: { disabledCheckbox: true } });

      expect(findTooltip().value).toBe('This setting only applies when GitLab Duo is available.');
    });

    it('shows the disabledTooltip prop when provided', () => {
      createComponent({
        props: { disabledCheckbox: true, disabledTooltip: 'Turn on AI Governance first.' },
      });

      expect(findTooltip().value).toBe('Turn on AI Governance first.');
    });

    it('does not show a tooltip when the checkbox is enabled', () => {
      createComponent({ props: { disabledTooltip: 'Turn on AI Governance first.' } });

      expect(findTooltip().value).toBe('');
    });
  });

  describe('cascading lock icon', () => {
    it('does not render when cascading settings are null', () => {
      createComponent({ injectedProps: { aiAuditEventsStorageCascadingSettings: null } });

      expect(findCascadingLockIcon().exists()).toBe(false);
    });

    it('does not render when cascading settings are empty', () => {
      createComponent({ injectedProps: { aiAuditEventsStorageCascadingSettings: {} } });

      expect(findCascadingLockIcon().exists()).toBe(false);
    });

    it('renders when cascading settings are present', () => {
      createComponent({
        injectedProps: {
          aiAuditEventsStorageCascadingSettings: {
            lockedByAncestor: false,
            lockedByApplicationSetting: false,
            ancestorNamespace: null,
          },
        },
      });

      expect(findCascadingLockIcon().exists()).toBe(true);
      expect(findCascadingLockIcon().props()).toMatchObject({
        isLockedByGroupAncestor: false,
        isLockedByApplicationSettings: false,
        ancestorNamespace: null,
      });
    });

    it.each`
      lockedByAncestor | lockedByApplicationSetting
      ${true}          | ${false}
      ${false}         | ${true}
    `(
      'disables the checkbox when locked (lockedByAncestor: $lockedByAncestor, lockedByApplicationSetting: $lockedByApplicationSetting)',
      ({ lockedByAncestor, lockedByApplicationSetting }) => {
        createComponent({
          injectedProps: {
            aiAuditEventsStorageCascadingSettings: { lockedByAncestor, lockedByApplicationSetting },
          },
        });

        expect(findCheckbox().props('disabled')).toBe(true);
      },
    );

    it('does not disable the checkbox when not locked', () => {
      createComponent({
        injectedProps: {
          aiAuditEventsStorageCascadingSettings: {
            lockedByAncestor: false,
            lockedByApplicationSetting: false,
          },
        },
      });

      expect(findCheckbox().props('disabled')).toBe(false);
    });
  });
});
