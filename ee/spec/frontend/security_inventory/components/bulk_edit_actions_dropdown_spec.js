import { shallowMount } from '@vue/test-utils';
import { GlDisclosureDropdown, GlDisclosureDropdownItem } from '@gitlab/ui';
import BulkEditActionsDropdown from 'ee/security_inventory/components/bulk_edit_actions_dropdown.vue';
import {
  ACTION_TYPE_BULK_EDIT_ATTRIBUTES,
  ACTION_TYPE_BULK_EDIT_SCANNERS,
  ACTION_TYPE_BULK_EDIT_TRIAGE,
  ACTION_TYPE_BULK_TURN_OFF_TRIAGE,
} from 'ee/security_inventory/constants';

describe('BulkEditActionsDropdown', () => {
  let wrapper;

  const createComponent = (provide = {}) => {
    wrapper = shallowMount(BulkEditActionsDropdown, {
      provide: {
        canManageAttributes: false,
        canApplyProfiles: false,
        canReadScanProfiles: true,
        ...provide,
      },
    });
  };

  const findDropdown = () => wrapper.findComponent(GlDisclosureDropdown);
  const findDropdownItems = () => wrapper.findAllComponents(GlDisclosureDropdownItem);

  describe('when user has both canManageAttributes and canApplyProfiles permissions', () => {
    beforeEach(() => {
      createComponent({
        canManageAttributes: true,
        canApplyProfiles: true,
      });
    });

    it('renders dropdown with "Manage security scanners" and "Manage security attributes" actions', () => {
      const dropdown = findDropdown();
      const items = dropdown.props('items');

      expect(items).toHaveLength(2);
      expect(items[0]).toMatchObject({
        text: 'Manage security scanners',
        type: ACTION_TYPE_BULK_EDIT_SCANNERS,
      });
      expect(items[1]).toMatchObject({
        text: 'Manage security attributes',
        type: ACTION_TYPE_BULK_EDIT_ATTRIBUTES,
      });
    });

    it('emits bulk-edit event with SCANNERS type when scanners action is clicked', () => {
      const dropdownItems = findDropdownItems();
      dropdownItems.at(0).vm.$emit('action');

      expect(wrapper.emitted('bulk-edit')).toEqual([[ACTION_TYPE_BULK_EDIT_SCANNERS]]);
    });

    it('emits bulk-edit event with ATTRIBUTES type when attributes action is clicked', () => {
      const dropdownItems = findDropdownItems();
      dropdownItems.at(1).vm.$emit('action');

      expect(wrapper.emitted('bulk-edit')).toEqual([[ACTION_TYPE_BULK_EDIT_ATTRIBUTES]]);
    });
  });

  describe('with the triage_and_remediation_profiles_ui feature flag enabled', () => {
    const glFeatures = { triageAndRemediationProfilesUi: true };

    it('renders the apply action, then the turn off action', () => {
      createComponent({ canManageAttributes: true, canApplyProfiles: true, glFeatures });

      const items = findDropdown().props('items');

      expect(items).toHaveLength(4);
      expect(items[2]).toMatchObject({
        text: 'Apply Automated Triage and Remediation profile',
        type: ACTION_TYPE_BULK_EDIT_TRIAGE,
      });
      expect(items[3]).toMatchObject({
        text: 'Turn off Automated Triage and Remediation',
        type: ACTION_TYPE_BULK_TURN_OFF_TRIAGE,
      });
    });

    it('emits bulk-edit with TURN_OFF_TRIAGE on click', () => {
      createComponent({ canManageAttributes: true, canApplyProfiles: true, glFeatures });

      findDropdownItems().at(3).vm.$emit('action');

      expect(wrapper.emitted('bulk-edit')).toEqual([[ACTION_TYPE_BULK_TURN_OFF_TRIAGE]]);
    });

    it('emits bulk-edit with TRIAGE on click', () => {
      createComponent({ canManageAttributes: true, canApplyProfiles: true, glFeatures });

      findDropdownItems().at(2).vm.$emit('action');

      expect(wrapper.emitted('bulk-edit')).toEqual([[ACTION_TYPE_BULK_EDIT_TRIAGE]]);
    });

    it('hides the triage actions without canApplyProfiles', () => {
      createComponent({ canManageAttributes: true, canApplyProfiles: false, glFeatures });

      const types = findDropdown()
        .props('items')
        .map(({ type }) => type);

      expect(types).not.toContain(ACTION_TYPE_BULK_EDIT_TRIAGE);
      expect(types).not.toContain(ACTION_TYPE_BULK_TURN_OFF_TRIAGE);
    });

    it('hides the triage actions without read access', () => {
      createComponent({ canApplyProfiles: true, canReadScanProfiles: false, glFeatures });

      const types = findDropdown()
        .props('items')
        .map(({ type }) => type);

      expect(types).not.toContain(ACTION_TYPE_BULK_EDIT_TRIAGE);
      expect(types).not.toContain(ACTION_TYPE_BULK_TURN_OFF_TRIAGE);
    });
  });

  describe('when user only has canApplyProfiles permission', () => {
    beforeEach(() => {
      createComponent({
        canManageAttributes: false,
        canApplyProfiles: true,
      });
    });

    it('renders dropdown with only scanners action', () => {
      const dropdown = findDropdown();
      const items = dropdown.props('items');

      expect(items).toHaveLength(1);
      expect(items[0]).toMatchObject({
        text: 'Manage security scanners',
        type: ACTION_TYPE_BULK_EDIT_SCANNERS,
      });
    });
  });

  describe('when user only has canManageAttributes permission', () => {
    beforeEach(() => {
      createComponent({
        canManageAttributes: true,
        canApplyProfiles: false,
      });
    });

    it('renders dropdown with only attributes action', () => {
      const dropdown = findDropdown();
      const items = dropdown.props('items');

      expect(items).toHaveLength(1);
      expect(items[0]).toMatchObject({
        text: 'Manage security attributes',
        type: ACTION_TYPE_BULK_EDIT_ATTRIBUTES,
      });
    });
  });
});
