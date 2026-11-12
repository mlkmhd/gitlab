# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe DeleteStaleAiFlowSchedules,
  migration: :gitlab_main_org,
  feature_category: :dap_triggers do
  let(:flow_schedules) { table(:ai_flow_schedules) }
  let(:flow_triggers) { table(:ai_flow_triggers) }

  let(:scheduled) { 9 }
  let(:mention) { 0 }

  let!(:project) { create_project }

  describe '#up' do
    it 'deletes only the schedules whose trigger no longer fires on a cron tick' do
      create_schedule(create_trigger(event_types: [mention]))
      create_schedule(create_trigger(event_types: []))
      live = create_schedule(create_trigger(event_types: [scheduled]))
      mixed = create_schedule(create_trigger(event_types: [mention, scheduled]))

      migrate!

      expect(flow_schedules.pluck(:id)).to contain_exactly(live.id, mixed.id)
    end

    context 'when schedules span multiple batches' do
      before do
        stub_const("#{described_class}::BATCH_SIZE", 2)
      end

      it 'keeps the live schedules in batches that also hold stale ones' do
        create_schedule(create_trigger(event_types: [mention]))
        live = create_schedule(create_trigger(event_types: [scheduled]))
        create_schedule(create_trigger(event_types: [mention]))
        mixed = create_schedule(create_trigger(event_types: [mention, scheduled]))

        migrate!

        expect(flow_schedules.pluck(:id)).to contain_exactly(live.id, mixed.id)
      end
    end
  end

  describe '#down' do
    it 'is a no-op' do
      expect { described_class.new.down }.not_to raise_error
    end
  end

  def create_trigger(event_types:)
    flow_triggers.create!(
      project_id: project.id,
      description: 'trigger',
      event_types: event_types,
      created_at: Time.current,
      updated_at: Time.current
    )
  end

  def create_schedule(trigger)
    flow_schedules.create!(
      project_id: project.id,
      ai_flow_trigger_id: trigger.id,
      cron: '0 9 * * 1',
      cron_timezone: 'UTC',
      description: 'Nightly run',
      created_at: Time.current,
      updated_at: Time.current
    )
  end

  def create_project
    organization = table(:organizations).create!(name: 'Organization', path: 'organization')
    group = table(:namespaces).create!(
      name: 'Group', path: 'group', type: 'Group', organization_id: organization.id
    )
    project_namespace = table(:namespaces).create!(
      name: 'Project', path: 'project', type: 'Project', organization_id: organization.id
    )

    table(:projects).create!(
      name: 'Project', path: 'project', namespace_id: group.id,
      project_namespace_id: project_namespace.id, organization_id: organization.id
    )
  end
end
