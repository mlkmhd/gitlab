import { GlTableLite, GlIcon } from '@gitlab/ui';
import { mountExtended } from 'helpers/vue_test_utils_helper';
import LfkBacklogResults from '~/admin/database_diagnostics/components/lfk_backlog_results.vue';
import { lfkBacklogResults } from '../mock_data';

describe('LfkBacklogResults component', () => {
  let wrapper;

  const findTable = () => wrapper.findComponent(GlTableLite);
  const findIcon = () => wrapper.findComponent(GlIcon);
  const findNoBacklog = () => wrapper.findByTestId('lfk-no-backlog');

  const createComponent = (props) => {
    wrapper = mountExtended(LfkBacklogResults, {
      propsData: {
        connectionName: 'main',
        ...props,
      },
    });
  };

  describe('with a backlog', () => {
    beforeEach(() => {
      createComponent({ backlog: lfkBacklogResults.connections.main });
    });

    it('renders the connection name and a warning icon', () => {
      expect(wrapper.text()).toContain('main');
      expect(findIcon().props('name')).toBe('warning');
    });

    it('renders a table row per parent table with a humanized age', () => {
      const rows = findTable().findAll('tbody tr');
      expect(rows).toHaveLength(2);

      const firstRow = rows.at(0).text();
      expect(firstRow).toContain('public.projects');
      expect(firstRow).toContain('100000');
      // 50,000,000 seconds humanizes to a count of days
      expect(firstRow).toContain('days');
    });

    it('appends "+" to the pending count of a capped table only', () => {
      // public.projects is capped -> "100000+"; public.users is exact (no marker)
      expect(wrapper.text()).toContain('100000+');
      expect(wrapper.findAllByTestId('pending-capped')).toHaveLength(1);
    });
  });

  describe('with a capped deferred count', () => {
    beforeEach(() => {
      createComponent({
        backlog: [
          {
            parent_table: 'public.projects',
            pending_records: 10000,
            capped: true,
            oldest_pending_age_seconds: 3888000,
            deferred_records: 10000,
          },
          {
            parent_table: 'public.namespaces',
            pending_records: 10000,
            capped: true,
            oldest_pending_age_seconds: 86400,
            deferred_records: 0,
          },
          {
            parent_table: 'public.users',
            pending_records: 30,
            capped: false,
            oldest_pending_age_seconds: 600,
            deferred_records: 30,
          },
        ],
      });
    });

    it('appends "+" to the deferred count of every capped table, including 0', () => {
      const deferredCells = findTable()
        .findAll('tbody tr')
        .wrappers.map((row) => row.findAll('td').at(3).text());

      expect(deferredCells).toEqual(['10000+', '0+', '30']);
      expect(wrapper.findAllByTestId('deferred-capped')).toHaveLength(2);
    });
  });

  describe('with no backlog', () => {
    beforeEach(() => {
      createComponent({ backlog: [] });
    });

    it('renders a success icon and an empty-state message', () => {
      expect(findIcon().props('name')).toBe('check-circle-filled');
      expect(findNoBacklog().exists()).toBe(true);
      expect(findTable().exists()).toBe(false);
    });
  });
});
