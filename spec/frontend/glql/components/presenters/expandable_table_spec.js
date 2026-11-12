import { nextTick } from 'vue';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import ThResizable from '~/glql/components/common/th_resizable.vue';
import ExpandableTablePresenter from '~/glql/components/presenters/expandable_table.vue';
import { withBreakdown } from '~/glql/components/presenters/utils/expandable_table';
import RowDisclosureToggle from '~/vue_shared/components/expandable_rows/row_disclosure_toggle.vue';
import { MOCK_GROUP, MOCK_PROJECT } from '../../mock_data';

describe('ExpandableTablePresenter', () => {
  let wrapper;

  const groupField = {
    key: 'Group',
    field: 'group',
    label: 'Group',
    name: 'group_depth_2',
    type: 'dimension',
    parameters: { depth: '2' },
  };
  const projectField = { key: 'project', label: 'Project', name: 'project', type: 'dimension' };
  const metricFields = [
    { key: 'creditsUsedSum', label: 'Credits', name: 'creditsUsedSum', type: 'metric' },
    { key: 'usersCount', label: 'Users', name: 'usersCount', type: 'metric' },
  ];
  const fields = [groupField, ...metricFields];

  const platform = { ...MOCK_GROUP, id: 'gid://gitlab/Group/2', fullName: 'Org / Platform' };
  const data = { ...MOCK_GROUP, id: 'gid://gitlab/Group/3', fullName: 'Org / Data' };
  const tools = { ...MOCK_GROUP, id: 'gid://gitlab/Group/4', fullName: 'Org / Tools' };
  const projectOf = (id, name) => ({
    ...MOCK_PROJECT,
    id: `gid://gitlab/Project/${id}`,
    nameWithNamespace: name,
  });

  const parents = {
    nodes: [
      { Group: platform, creditsUsedSum: 10, usersCount: 3 },
      { Group: null, creditsUsedSum: 4, usersCount: 2 },
      { Group: data, creditsUsedSum: 1, usersCount: 1 },
    ],
  };
  const breakdownData = {
    count: 3,
    fields: [groupField, projectField, ...metricFields],
    nodes: [
      {
        Group: platform,
        project: projectOf(1, 'Org / Platform / api'),
        creditsUsedSum: 4,
        usersCount: 2,
      },
      {
        Group: platform,
        project: projectOf(2, 'Org / Platform / web'),
        creditsUsedSum: 6,
        usersCount: 1,
      },
      { Group: null, project: projectOf(3, 'Org / tools'), creditsUsedSum: 4, usersCount: 2 },
    ],
  };

  // Props as DataPresenter derives them from the resolver's breakdown.
  const propsFor = ({
    breakdown = null,
    parentData = parents,
    tableFields = fields,
    ...props
  } = {}) => {
    const joined = withBreakdown({
      fields: tableFields,
      data: parentData,
      breakdownData: breakdown,
    });

    return {
      data: joined.data,
      fields: tableFields,
      source: 'DuoWorkflows',
      childDimension: joined.dimension,
      truncatedChildCount: joined.truncatedCount,
      ...props,
    };
  };

  const createWrapper = async (props) => {
    wrapper = mountExtended(ExpandableTablePresenter, { propsData: propsFor(props) });

    await nextTick();
  };

  const findToggles = () => wrapper.findAllComponents(RowDisclosureToggle);
  const findToggle = (index) => findToggles().at(index);
  // Collapses the line breaks between a cell's label and its hint.
  const findRowTexts = () =>
    wrapper
      .findAll('tbody tr')
      .wrappers.map((row) =>
        row.findAll('td').wrappers.map((td) => td.text().replace(/\s+/g, ' ').trim()),
      );

  const toggle = async (index) => {
    findToggle(index).vm.$emit('toggle');
    await nextTick();
  };

  describe('before the children load', () => {
    beforeEach(() => createWrapper());

    it('renders a collapsed toggle on every parent row', () => {
      expect(findToggles()).toHaveLength(3);
      expect(findToggles().wrappers.map((t) => t.props())).toEqual(
        ['Org / Platform', 'Not in a subgroup', 'Org / Data'].map((label) =>
          expect.objectContaining({ label, expandable: true, expanded: false, depth: 0 }),
        ),
      );
    });

    it('asks for the children on the first expand', async () => {
      await toggle(0);

      expect(wrapper.emitted('load-children')).toHaveLength(1);
      expect(findToggle(0).props('expanded')).toBe(true);
    });
  });

  describe('while the children load', () => {
    beforeEach(async () => {
      await createWrapper({ childrenLoading: true });
      await toggle(0);
    });

    it('shows a loading toggle and a skeleton row under the expanded parent', () => {
      expect(findToggle(0).props('loading')).toBe(true);
      expect(wrapper.findAll('tbody tr').at(1).attributes('data-testid')).toBe(
        'child-rows-loading',
      );
    });
  });

  describe('once the children load', () => {
    beforeEach(async () => {
      await createWrapper({ breakdown: breakdownData });
      await toggle(0);
    });

    it('does not ask for the children again', () => {
      expect(wrapper.emitted('load-children')).toBeUndefined();
    });

    it('renders the children under their parent, aligned with its columns', () => {
      expect(findRowTexts()).toEqual([
        ['Org / Platform', '10', '3'],
        // The project presenter leads with its avatar's initial, and the toggle ends with the
        // parent for screen readers.
        ['O Org / Platform / api Under Org / Platform', '4', '2'],
        ['O Org / Platform / web Under Org / Platform', '6', '1'],
        ['Not in a subgroup May include subgroups you cannot see', '4', '2'],
        ['Org / Data', '1', '1'],
      ]);
    });

    it('indents the children and gives them no toggle', () => {
      expect(findToggle(1).props()).toMatchObject({ depth: 1, expandable: false });
    });

    it('names the parent of each child row for screen readers', () => {
      expect(findToggles().wrappers.map((t) => t.props('parentLabel'))).toEqual([
        '',
        'Org / Platform',
        'Org / Platform',
        '',
        '',
      ]);
    });

    it('points the expanded toggle at the rows it shows', () => {
      const ids = wrapper
        .findAll('tbody tr')
        .wrappers.slice(1, 3)
        .map((row) => row.attributes('id'));

      expect(ids.every(Boolean)).toBe(true);
      expect(findToggle(0).props('childRowIds')).toEqual(ids);
    });

    it('keeps the toggle of a parent with no children, so it keeps focus', () => {
      expect(findToggle(4).props('expandable')).toBe(true);
    });

    it('says when an expanded parent has no children', async () => {
      await toggle(4);

      expect(wrapper.findByTestId('child-rows-empty').text()).toBe('No rows under this one.');
    });

    it('nests the projects of the "Not in a subgroup" row under it', async () => {
      await toggle(3);

      expect(findRowTexts()[4]).toEqual(['O Org / tools Under Not in a subgroup', '4', '2']);
    });

    it('hides the children again on collapse', async () => {
      await toggle(0);

      expect(findRowTexts()).toHaveLength(3);
    });

    it('sorts the children within their parent', async () => {
      await wrapper.findByTestId('column-1').trigger('click');

      expect(findRowTexts().map(([label]) => label)).toEqual([
        'Org / Data',
        'Not in a subgroup May include subgroups you cannot see',
        'Org / Platform',
        'O Org / Platform / api Under Org / Platform',
        'O Org / Platform / web Under Org / Platform',
      ]);
    });

    it('sorts the children by their own dimension when sorting by the first column', async () => {
      await wrapper.findByTestId('column-0').trigger('click');
      await wrapper.findByTestId('column-0').trigger('click');

      expect(findRowTexts().map(([label]) => label)).toEqual([
        'Org / Platform',
        'O Org / Platform / web Under Org / Platform',
        'O Org / Platform / api Under Org / Platform',
        'Org / Data',
        'Not in a subgroup May include subgroups you cannot see',
      ]);
    });

    it('marks the status rows so that copying the table leaves them out', async () => {
      await toggle(4);

      expect(wrapper.findByTestId('child-rows-empty').attributes()).toHaveProperty(
        'data-gfm-ignore',
      );
    });

    it('keeps the row expanded when more rows load', async () => {
      const { data: moreRows } = propsFor({
        breakdown: breakdownData,
        parentData: {
          nodes: [...parents.nodes, { Group: tools, creditsUsedSum: 1, usersCount: 1 }],
        },
      });
      await wrapper.setProps({ data: moreRows });

      expect(findToggle(0).props('expanded')).toBe(true);
    });
  });

  it('does not expand parents that share a key', async () => {
    await createWrapper({
      breakdown: breakdownData,
      parentData: { nodes: [...parents.nodes, { Group: null, creditsUsedSum: 1, usersCount: 1 }] },
    });

    expect(findToggle(1).props('expandable')).toBe(false);
    expect(findToggle(3).props('expandable')).toBe(false);
    expect(findToggle(0).props('expandable')).toBe(true);
  });

  it('leaves the trend cell of a child row blank', async () => {
    const trendField = { key: '__trend', label: 'Trend', name: '__trend', type: 'metric' };
    await createWrapper({
      breakdown: breakdownData,
      parentData: { nodes: parents.nodes.map((node) => ({ ...node, __trend: null })) },
      tableFields: [...fields, trendField],
    });
    await toggle(0);

    expect(findRowTexts()[1]).toEqual([
      'O Org / Platform / api Under Org / Platform',
      '4',
      '2',
      '',
    ]);
  });

  describe('when some children could not be loaded', () => {
    beforeEach(() => createWrapper({ breakdown: { ...breakdownData, count: 5 } }));

    it('says how many did', () => {
      expect(wrapper.findByTestId('child-rows-truncated').text()).toBe(
        'Some nested rows are missing: only the first 3 rows could be loaded.',
      );
    });

    it('uses the singular for one row', async () => {
      await createWrapper({
        breakdown: { ...breakdownData, count: 5, nodes: breakdownData.nodes.slice(0, 1) },
      });

      expect(wrapper.findByTestId('child-rows-truncated').text()).toBe(
        'Some nested rows are missing: only the first 1 row could be loaded.',
      );
    });

    it('says an expanded parent with no loaded children may be missing some', async () => {
      await toggle(2);

      expect(wrapper.findByTestId('child-rows-empty').text()).toBe(
        'Rows under this one may be missing.',
      );
    });
  });

  describe('when the children fail to load', () => {
    beforeEach(async () => {
      await createWrapper({ childrenError: true });
      await toggle(0);
    });

    it('says so under the expanded row', () => {
      expect(wrapper.findByTestId('child-rows-error').text()).toBe(
        'Could not load the rows under this one. Expand it again to retry.',
      );
    });

    it('asks for the children again on the next expand', async () => {
      await toggle(0);
      await toggle(0);

      expect(wrapper.emitted('load-children')).toHaveLength(2);
    });
  });

  describe('columnWidths', () => {
    const FIXED_LAYOUT_CLASS = '[&>table]:gl-table-fixed';
    const findTableWrapper = () => wrapper.find('.gl-table-shadow');
    const headerWidths = () =>
      wrapper.findAllComponents(ThResizable).wrappers.map((th) => th.element.style.width);
    const truncatedCellTexts = () =>
      wrapper
        .findAllByTestId('truncated-cell')
        .wrappers.map((cell) => cell.text().replace(/\s+/g, ' '));

    it('keeps the automatic layout when no widths are set', async () => {
      await createWrapper({ breakdown: breakdownData });

      expect(findTableWrapper().classes()).not.toContain(FIXED_LAYOUT_CLASS);
      expect(headerWidths()).toEqual(['', '', '']);
      expect(truncatedCellTexts()).toHaveLength(0);
    });

    it('fixes the layout and truncates a sized column, child rows included', async () => {
      await createWrapper({
        breakdown: breakdownData,
        displayConfig: { columnWidths: { Group: 40 } },
      });
      await toggle(0);

      expect(findTableWrapper().classes()).toContain(FIXED_LAYOUT_CLASS);
      expect(headerWidths()).toEqual(['40%', '', '']);
      // The NULL bucket renders its label instead of a value, so it has nothing to truncate.
      expect(truncatedCellTexts()).toEqual([
        'Org / Platform',
        'O Org / Platform / api',
        'O Org / Platform / web',
        'Org / Data',
      ]);
    });

    it.each`
      columnWidths        | message
      ${{ Group: '40%' }} | ${'`columnWidths` must map column names to percentages between 1 and 100.'}
      ${{ project: 30 }}  | ${'Unknown column for `columnWidths`: `project`.'}
    `('emits an error for $columnWidths', async ({ columnWidths, message }) => {
      await createWrapper({ breakdown: breakdownData, displayConfig: { columnWidths } });

      expect(wrapper.emitted('error')[0][0].message).toBe(message);
      expect(findTableWrapper().classes()).not.toContain(FIXED_LAYOUT_CLASS);
    });
  });
});
