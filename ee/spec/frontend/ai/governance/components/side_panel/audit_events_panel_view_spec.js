import { nextTick } from 'vue';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import AgentArtifactsFilteredSearch from 'ee/agent_artifacts/components/agent_artifacts_filtered_search.vue';
import AgentArtifactsTable from 'ee/agent_artifacts/components/agent_artifacts_table.vue';
import AuditEventsPanelView from 'ee/ai/governance/components/side_panel/audit_events_panel_view.vue';

const filters = { projectPath: 'gitlab-duo/web-app' };

describe('AuditEventsPanelView', () => {
  let wrapper;

  const createComponent = (props = {}) => {
    wrapper = shallowMountExtended(AuditEventsPanelView, {
      propsData: { filters, ...props },
    });
  };

  const findFilteredSearch = () => wrapper.findComponent(AgentArtifactsFilteredSearch);
  const findTable = () => wrapper.findComponent(AgentArtifactsTable);

  it('opens the filter bar with the filters it was given', () => {
    createComponent();

    expect(findFilteredSearch().props('initialFilters')).toEqual(filters);
  });

  it('lists the sessions for the filters the filter bar applies', async () => {
    createComponent();

    findFilteredSearch().vm.$emit('filter', { projectPath: 'gitlab-duo/api-service' });
    await nextTick();

    expect(findTable().props('filter')).toEqual({ projectPath: 'gitlab-duo/api-service' });
  });

  it('opens the session of a clicked row', () => {
    const row = { id: 'gid://gitlab/Ai::DuoWorkflows::Workflow/1' };
    createComponent();

    findTable().vm.$emit('row-click', row);

    expect(wrapper.emitted('open-session')).toEqual([[row]]);
  });
});
