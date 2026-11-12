# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Orbit::MemberNotifications::TodoWorker, feature_category: :knowledge_graph do
  let_it_be_with_reload(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:reporter) { create(:user, reporter_of: group) }
  let_it_be(:subgroup_developer) { create(:user, developer_of: subgroup) }
  let_it_be(:guest) { create(:user, guest_of: group) }
  let_it_be(:owner) { create(:user, owner_of: group) }

  let(:group_id) { group.id }

  subject(:perform) { described_class.new.perform(group_id) }

  before do
    stub_saas_features(gitlab_com_subscriptions: true)
    create(:knowledge_graph_enabled_namespace, namespace: group)
  end

  it_behaves_like 'worker with data consistency', described_class, data_consistency: :delayed

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [group_id] }
  end

  it 'creates one orbit todo for each Reporter or higher member of the group or a subgroup' do
    perform

    expect(Todo.where(action: Todo::ORBIT_ACCESS_GRANTED).pluck(:user_id))
      .to match_array([reporter.id, subgroup_developer.id, owner.id])
  end

  it 'targets each member, so members of only a subgroup can read it' do
    perform

    expect(subgroup_developer.todos.last).to have_attributes(target: subgroup_developer)
  end

  context 'when a member belongs to groups in different batches' do
    before_all do
      subgroup.add_developer(reporter)
    end

    before do
      stub_const("#{described_class}::NAMESPACE_BATCH_SIZE", 1)
    end

    it 'creates one todo for that member' do
      perform

      expect(Todo.where(action: Todo::ORBIT_ACCESS_GRANTED, user: reporter).count).to eq(1)
    end
  end

  it 'does not notify members below the Reporter role' do
    perform

    expect(guest.todos.where(action: Todo::ORBIT_ACCESS_GRANTED)).to be_empty
  end

  context 'when a subgroup has only a bot member' do
    before_all do
      create(:group, parent: group).add_developer(create(:user, :project_bot))
    end

    before do
      stub_const("#{described_class}::NAMESPACE_BATCH_SIZE", 1)
    end

    it 'does not notify the bot' do
      perform

      expect(Todo.where(action: Todo::ORBIT_ACCESS_GRANTED).pluck(:user_id))
        .to match_array([reporter.id, subgroup_developer.id, owner.id])
    end
  end

  context 'when Orbit is no longer on for the group' do
    before do
      group.knowledge_graph_enabled_namespace.destroy!
    end

    it 'creates no todos' do
      expect { perform }.not_to change { Todo.count }
    end
  end

  context 'when not on GitLab.com' do
    before do
      stub_saas_features(gitlab_com_subscriptions: false)
    end

    it 'creates no todos' do
      expect { perform }.not_to change { Todo.count }
    end
  end

  context 'when the group does not exist' do
    let(:group_id) { non_existing_record_id }

    it 'creates no todos and does not raise' do
      expect { perform }.not_to change { Todo.count }
    end
  end
end
