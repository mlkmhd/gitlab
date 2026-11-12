import { nextTick } from 'vue';
import { GlTableLite, GlSkeletonLoader, GlFormCheckbox } from '@gitlab/ui';
import { shallowMountExtended, mountExtended } from 'helpers/vue_test_utils_helper';
import { stubComponent } from 'helpers/stub_component';
import SecurityInventoryTable from 'ee/security_inventory/components/security_inventory_table.vue';
import NameCell from 'ee/security_inventory/components/name_cell.vue';
import VulnerabilityCell from 'ee/security_inventory/components/vulnerability_cell.vue';
import ToolCoverageCell from 'ee/security_inventory/components/tool_coverage_cell.vue';
import CapabilitiesCell from 'ee/security_inventory/components/capabilities_cell.vue';
import ActionCell from 'ee/security_inventory/components/action_cell.vue';
import AttributesCell from 'ee/security_inventory/components/attributes_cell.vue';
import CheckboxCell from 'ee/security_inventory/components/checkbox_cell.vue';
import TriageProfileDrawer from 'ee/security_configuration/components/scan_profiles/triage_profile_drawer.vue';
import BulkTurnOffTriage from 'ee/security_inventory/components/bulk_turn_off_triage.vue';
import {
  ACTION_TYPE_BULK_EDIT_SCANNERS,
  ACTION_TYPE_BULK_EDIT_ATTRIBUTES,
  ACTION_TYPE_BULK_EDIT_TRIAGE,
  ACTION_TYPE_BULK_TURN_OFF_TRIAGE,
} from 'ee/security_inventory/constants';
import { subgroupsSecurityDetails, mockProjects } from '../mock_data';

const mockProject = mockProjects[0];
const anotherProject = mockProjects[1];
const mockGroup = subgroupsSecurityDetails.data.group.descendantGroups.nodes[0];
const items = [mockGroup, mockProject];
const allColumnKeys = ['name', 'vulnerabilities', 'toolCoverage', 'securityAttributes', 'actions'];

describe('SecurityInventoryTable', () => {
  let wrapper;
  let openDrawerSpy;

  const createComponentFactory = ({ mountFn = shallowMountExtended } = {}) => {
    return ({
      props = {},
      stubs = {},
      provide = {
        groupFullPath: 'path/to/group',
        canManageAttributes: false,
        canReadAttributes: true,
        canApplyProfiles: false,
      },
    } = {}) => {
      wrapper = mountFn(SecurityInventoryTable, {
        propsData: {
          items,
          currentPath: 'path/to/group',
          ...props,
        },
        stubs: {
          GlTableLite: { ...stubComponent(GlTableLite), props: ['items', 'fields'] },
          ...stubs,
        },
        provide,
      });

      return wrapper;
    };
  };

  const createComponent = createComponentFactory();
  const createFullComponent = createComponentFactory({ mountFn: mountExtended });

  const findTable = () => wrapper.findComponent(GlTableLite);
  const findColumnKeys = () =>
    findTable()
      .props('fields')
      .map((field) => field.key);
  const findColumnWidths = () =>
    findTable()
      .props('fields')
      .map((field) => field.thStyle.width);
  const findTableRows = () => findTable().findAll('tbody tr');
  const findNthTableRow = (n) => findTableRows().at(n);
  const findSelectAllCheckbox = () => wrapper.findComponent(GlFormCheckbox);
  const findItemCheckbox = () => wrapper.findComponent(CheckboxCell);
  const findTooltipButton = () =>
    wrapper.find('[data-testid="security-attributes-tooltip-button"]');

  beforeEach(() => {
    createComponent();
  });

  describe('component rendering', () => {
    it('renders the table component', () => {
      expect(findTable().exists()).toBe(true);
    });

    it('passes fields to GlTableLite component', () => {
      const width = { width: expect.any(String) };

      expect(findTable().props('fields')).toEqual([
        { key: 'name', label: 'Name', thStyle: width },
        { key: 'vulnerabilities', label: 'Vulnerabilities', thStyle: width },
        { key: 'toolCoverage', label: 'Tool coverage', thStyle: width },
        { key: 'securityAttributes', label: 'Security attributes', thStyle: width },
        { key: 'actions', label: '', tdClass: 'gl-text-right', thStyle: width },
      ]);
    });

    it('passes items to GlTableLite component', () => {
      expect(findTable().props('items')).toEqual(items);
    });

    it('sizes each visible column in proportion to its width weight', () => {
      expect(findColumnKeys()).toEqual(allColumnKeys);
      expect(findColumnWidths()).toEqual([
        'calc((100% - 4rem) * 18 / 72)',
        'calc((100% - 4rem) * 14 / 72)',
        'calc((100% - 4rem) * 26 / 72)',
        'calc((100% - 4rem) * 14 / 72)',
        '4rem',
      ]);
    });

    it('gives the checkbox column a static width when it is shown', () => {
      createComponent({
        provide: {
          groupFullPath: 'path/to/group',
          canManageAttributes: true,
          canReadAttributes: true,
          canApplyProfiles: false,
        },
      });

      expect(findColumnKeys()).toEqual(['checkbox', ...allColumnKeys]);
      expect(findColumnWidths()).toEqual([
        '3rem',
        'calc((100% - 3rem - 4rem) * 18 / 72)',
        'calc((100% - 3rem - 4rem) * 14 / 72)',
        'calc((100% - 3rem - 4rem) * 26 / 72)',
        'calc((100% - 3rem - 4rem) * 14 / 72)',
        '4rem',
      ]);
    });
  });

  describe('loading state', () => {
    beforeEach(() => {
      createFullComponent({ props: { items: [], isLoading: true }, stubs: { GlTableLite: false } });
    });

    it('shows the correct number of skeleton rows when loading', () => {
      expect(findTableRows()).toHaveLength(3);
    });

    it('shows skeleton loaders for each column in a row', () => {
      const firstRow = findNthTableRow(0);
      const firstRowLoaders = firstRow.findAllComponents(GlSkeletonLoader);
      expect(firstRowLoaders).toHaveLength(5);
    });
  });

  describe('cell rendering', () => {
    beforeEach(() => {
      createFullComponent({ stubs: { GlTableLite: false } });
    });

    it('renders all required cell components', () => {
      expect(findTableRows()).toHaveLength(items.length);

      const firstRow = findNthTableRow(0);
      expect(firstRow.findComponent(NameCell).exists()).toBe(true);
      expect(firstRow.findComponent(VulnerabilityCell).exists()).toBe(true);
      expect(firstRow.findComponent(ToolCoverageCell).exists()).toBe(true);
      expect(firstRow.findComponent(AttributesCell).exists()).toBe(true);
      expect(firstRow.findComponent(ActionCell).exists()).toBe(true);
      expect(firstRow.findComponent(CheckboxCell).exists()).toBe(false);
    });
  });

  describe('security attributes header tooltip', () => {
    const TOOLTIP_TEXT =
      'You must have at least the Maintainer role in this group to manage security attributes.';

    beforeEach(() => {
      createFullComponent({ stubs: { GlTableLite: false } });
    });

    it('renders a focusable tooltip button with the expected title and aria-label', () => {
      const button = findTooltipButton();

      expect(button.exists()).toBe(true);
      expect(button.attributes('type')).toBe('button');
      expect(button.attributes('title')).toBe(TOOLTIP_TEXT);
      expect(button.attributes('aria-label')).toBe(TOOLTIP_TEXT);
    });
  });

  describe('subgroup navigation', () => {
    // mockProject.fullPath is 'flightjs/security-reports-example', so its parent is 'flightjs'
    const findProjectNameCell = () => findNthTableRow(1).findComponent(NameCell);

    it('passes a hash link to the parent path when not already viewing it', () => {
      createFullComponent({
        props: { currentPath: 'other/path' },
        stubs: { GlTableLite: false },
      });

      expect(findProjectNameCell().props('subgroupHref')).toBe('#flightjs');
    });

    it('passes no link when already viewing the parent path', () => {
      createFullComponent({
        props: { currentPath: 'flightjs' },
        stubs: { GlTableLite: false },
      });

      expect(findProjectNameCell().props('subgroupHref')).toBe('');
    });
  });

  describe('bulk selection', () => {
    describe('with permission', () => {
      beforeEach(() => {
        createFullComponent({
          props: { items },
          stubs: { GlTableLite: false },
          provide: {
            canReadAttributes: true,
            canManageAttributes: true,
            canApplyProfiles: false,
            groupFullPath: 'path/to/group',
          },
        });
      });

      it('select all checkbox selects and deselects all visible items', () => {
        findSelectAllCheckbox().vm.$emit('change', true);

        expect(wrapper.emitted('selected-count')[0]).toStrictEqual([2]);

        findSelectAllCheckbox().vm.$emit('change', false);

        expect(wrapper.emitted('selected-count')[1]).toStrictEqual([0]);
      });

      it('checkbox cell selects and deselects a single item', () => {
        findItemCheckbox().vm.$emit('select-item', items[0], true);

        expect(wrapper.emitted('selected-count')[0]).toStrictEqual([1]);

        findItemCheckbox().vm.$emit('select-item', items[0], false);

        expect(wrapper.emitted('selected-count')[1]).toStrictEqual([0]);
      });
    });
  });

  describe('when user does not have permission', () => {
    beforeEach(() => {
      createComponent({
        provide: {
          canManageAttributes: false,
          canReadAttributes: false,
          canApplyProfiles: false,
        },
      });
    });

    it('does not show the security attributes column', () => {
      expect(findTable().props('fields')).not.toContain(
        expect.objectContaining({ key: 'securityAttributes' }),
      );
    });
  });

  describe('capabilities column', () => {
    it('shows the column after tool coverage', () => {
      createComponent({ props: { showCapabilities: true } });

      expect(findColumnKeys()).toEqual([
        'name',
        'vulnerabilities',
        'toolCoverage',
        'capabilities',
        'securityAttributes',
        'actions',
      ]);
    });

    it('hides the column by default', () => {
      createComponent();

      expect(findColumnKeys()).not.toContain('capabilities');
    });

    it('is dropped when the user hides it', () => {
      createComponent({ props: { showCapabilities: true, hiddenColumns: ['capabilities'] } });

      expect(findColumnKeys()).not.toContain('capabilities');
    });

    it('renders the capabilities cell for each row', () => {
      createFullComponent({
        props: { showCapabilities: true },
        stubs: { GlTableLite: false, TriageProfileDrawer: true },
      });

      expect(wrapper.findAllComponents(CapabilitiesCell)).toHaveLength(items.length);
    });
  });

  describe('triage profile drawer', () => {
    const findTriageDrawer = () => wrapper.findComponent(TriageProfileDrawer);
    const openFromCell = async () => {
      wrapper.findAllComponents(CapabilitiesCell).at(1).vm.$emit('open-triage-drawer', {
        project: mockProject,
        presetId: 'gid://gitlab/Security::ScanProfile/1',
      });
      await nextTick();
    };

    it('hides the drawer without the capabilities column', () => {
      createComponent();

      expect(findTriageDrawer().exists()).toBe(false);
    });

    describe('with the capabilities column', () => {
      beforeEach(() => {
        createFullComponent({
          props: { showCapabilities: true },
          stubs: { GlTableLite: false, TriageProfileDrawer: true },
        });
      });

      it('renders a closed drawer', () => {
        expect(findTriageDrawer().props()).toMatchObject({
          open: false,
          project: null,
          presetId: '',
        });
      });

      it('shows the drawer for the project of the cell', async () => {
        await openFromCell();

        expect(findTriageDrawer().props()).toMatchObject({
          open: true,
          project: mockProject,
          presetId: 'gid://gitlab/Security::ScanProfile/1',
        });
      });

      it('hides the drawer on close', async () => {
        await openFromCell();
        findTriageDrawer().vm.$emit('close');
        await nextTick();

        expect(findTriageDrawer().props('open')).toBe(false);
      });

      it('refetches on applied', () => {
        findTriageDrawer().vm.$emit('applied');

        expect(wrapper.emitted('refetch')).toHaveLength(1);
      });
    });
  });

  describe('when columns are hidden', () => {
    it('drops them from the table and resizes the rest', () => {
      createComponent({ props: { hiddenColumns: ['vulnerabilities'] } });

      expect(findColumnKeys()).toEqual(['name', 'toolCoverage', 'securityAttributes', 'actions']);
      expect(findColumnWidths()).toEqual([
        'calc((100% - 4rem) * 18 / 58)',
        'calc((100% - 4rem) * 26 / 58)',
        'calc((100% - 4rem) * 14 / 58)',
        '4rem',
      ]);
    });

    it('keeps the actions column the same width when a column is hidden', () => {
      createComponent();
      const [actionsWidth] = findColumnWidths().slice(-1);

      createComponent({ props: { hiddenColumns: ['vulnerabilities'] } });

      expect(findColumnWidths().slice(-1)).toEqual([actionsWidth]);
    });

    it('does not hide columns that are not toggleable', () => {
      createComponent({ props: { hiddenColumns: ['name'] } });

      expect(findColumnKeys()).toEqual(allColumnKeys);
    });
  });

  describe('bulkEdit method with action types', () => {
    beforeEach(() => {
      createFullComponent({
        stubs: {
          GlTableLite: false,
          BulkAttributesUpdateDrawer: stubComponent({
            methods: { openDrawer: jest.fn() },
          }),
          BulkScannersUpdateDrawer: stubComponent({
            methods: { openDrawer: jest.fn() },
          }),
        },
        provide: {
          canApplyProfiles: true,
          canManageAttributes: true,
          canReadAttributes: true,
          groupFullPath: 'path/to/group',
        },
      });

      findSelectAllCheckbox().vm.$emit('change', true);
    });

    it('opens attributes drawer when called with attributes action type', async () => {
      await nextTick(); // Wait for drawer to be rendered after selection

      openDrawerSpy = jest.spyOn(wrapper.vm.$refs.bulkAttributesDrawer, 'openDrawer');

      wrapper.vm.bulkEdit(ACTION_TYPE_BULK_EDIT_ATTRIBUTES);
      await nextTick();

      expect(openDrawerSpy).toHaveBeenCalled();
    });

    it('opens scanners drawer when called with scanners action type', async () => {
      openDrawerSpy = jest.spyOn(wrapper.vm.$refs.bulkScannersDrawer, 'openDrawer');

      wrapper.vm.bulkEdit(ACTION_TYPE_BULK_EDIT_SCANNERS);
      await nextTick();

      expect(openDrawerSpy).toHaveBeenCalled();
    });
  });

  describe('triage profile drawer with selected items', () => {
    const findTriageDrawer = () => wrapper.findComponent(TriageProfileDrawer);
    const openFromCell = async () => {
      wrapper.findAllComponents(CapabilitiesCell).at(1).vm.$emit('open-triage-drawer', {
        project: mockProject,
        presetId: 'gid://gitlab/Security::ScanProfile/1',
      });
      await nextTick();
    };

    beforeEach(() => {
      createFullComponent({
        props: { showCapabilities: true },
        stubs: {
          GlTableLite: false,
          BulkAttributesUpdateDrawer: true,
          BulkScannersUpdateDrawer: true,
          TriageProfileDrawer: true,
        },
        provide: {
          groupFullPath: 'path/to/group',
          canManageAttributes: false,
          canReadAttributes: true,
          canApplyProfiles: true,
        },
      });
      findSelectAllCheckbox().vm.$emit('change', true);
    });

    it('shows the drawer for the selected items', async () => {
      wrapper.vm.bulkEdit(ACTION_TYPE_BULK_EDIT_TRIAGE);
      await nextTick();

      expect(findTriageDrawer().props()).toMatchObject({
        open: true,
        project: null,
        presetId: '',
        bulkItemIds: [mockGroup.id, mockProject.id],
      });
    });

    it('passes no item ids from a capabilities cell', async () => {
      await openFromCell();

      expect(findTriageDrawer().props()).toMatchObject({
        open: true,
        project: mockProject,
        bulkItemIds: [],
      });
    });

    it('hides the drawer on close', async () => {
      wrapper.vm.bulkEdit(ACTION_TYPE_BULK_EDIT_TRIAGE);
      await nextTick();
      findTriageDrawer().vm.$emit('close');
      await nextTick();

      expect(findTriageDrawer().props('open')).toBe(false);
    });

    it('clears the selection and refetches on applied', async () => {
      wrapper.vm.bulkEdit(ACTION_TYPE_BULK_EDIT_TRIAGE);
      await nextTick();
      findTriageDrawer().vm.$emit('applied');

      expect(wrapper.emitted('selected-count').at(-1)).toStrictEqual([0]);
      expect(wrapper.emitted('refetch')).toHaveLength(1);
    });

    it('keeps the selection on applied from a cell', async () => {
      await openFromCell();
      findTriageDrawer().vm.$emit('applied');

      expect(wrapper.emitted('selected-count')).toStrictEqual([[2]]);
      expect(wrapper.emitted('refetch')).toHaveLength(1);
    });
  });

  describe('bulk turn off of triage and remediation', () => {
    const findTurnOff = () => wrapper.findComponent(BulkTurnOffTriage);
    const turnOffSpy = jest.fn();

    beforeEach(() => {
      createFullComponent({
        stubs: {
          GlTableLite: false,
          BulkAttributesUpdateDrawer: true,
          BulkScannersUpdateDrawer: true,
          BulkTurnOffTriage: stubComponent(BulkTurnOffTriage, { methods: { turnOff: turnOffSpy } }),
        },
        provide: {
          groupFullPath: 'path/to/group',
          canManageAttributes: false,
          canReadAttributes: true,
          canApplyProfiles: true,
        },
      });
      findSelectAllCheckbox().vm.$emit('change', true);
    });

    it('passes the selected items', () => {
      expect(findTurnOff().props('itemIds')).toEqual([mockGroup.id, mockProject.id]);
    });

    it('turns off for the turn off action', () => {
      wrapper.vm.bulkEdit(ACTION_TYPE_BULK_TURN_OFF_TRIAGE);

      expect(turnOffSpy).toHaveBeenCalledTimes(1);
    });

    it('clears the selection and refetches when turned off', async () => {
      findTurnOff().vm.$emit('turned-off');
      await nextTick();

      expect(findTurnOff().props('itemIds')).toEqual([]);
      expect(wrapper.emitted('refetch')).toHaveLength(1);
    });

    it('keeps the selection and refetches on a failed turn off', async () => {
      findTurnOff().vm.$emit('refetch');
      await nextTick();

      expect(findTurnOff().props('itemIds')).toEqual([mockGroup.id, mockProject.id]);
      expect(wrapper.emitted('refetch')).toHaveLength(1);
    });
  });

  describe('openAttributesDrawer method', () => {
    beforeEach(() => {
      createFullComponent({
        stubs: {
          GlTableLite: false,
          ProjectAttributesUpdateDrawer: stubComponent({
            methods: { openDrawer: jest.fn() },
          }),
        },
      });
    });

    it('recreates drawer component when switching between different projects', async () => {
      wrapper.vm.openAttributesDrawer(mockProject);
      await nextTick();

      const firstDrawerInstance = wrapper.vm.$refs.attributesDrawer;

      wrapper.vm.openAttributesDrawer(anotherProject);
      await nextTick();

      const secondDrawerInstance = wrapper.vm.$refs.attributesDrawer;

      expect(firstDrawerInstance).not.toBe(secondDrawerInstance);
    });
  });
});
