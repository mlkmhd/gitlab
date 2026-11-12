# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authz::ProjectAuthorizations::ExpandService, feature_category: :permissions do
  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:invited_group_parent) { create(:group) }
  let_it_be(:invited_group) { create(:group, parent: invited_group_parent) }
  let_it_be(:invited_subgroup) { create(:group, parent: invited_group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:sub_project) { create(:project, group: subgroup) }
  let_it_be(:linked_project) { create(:project, group: group) }
  let_it_be(:shared_with_subgroup) { create(:project) }
  let_it_be(:member) { create(:user, developer_of: invited_group) }

  before_all do
    create(:project_group_link, project: linked_project, group: invited_group)
    create(:project_group_link, project: shared_with_subgroup, group: subgroup)
    create(:project_group_link, project: sub_project, group: invited_group)
    # A share only grants access to the invited group's own members.
    create(:user, developer_of: invited_group_parent)
    create(:user, developer_of: invited_subgroup)
    create(:group_member, :access_request, group: invited_group)
    create(:group_member, :invited, group: invited_group)
  end

  # Fixtures queue events through the refresh triggers, so examples start from an empty queue.
  def clear_refresh_queue
    Authz::ProjectAuthorizations::RefreshEvent.delete_all
  end

  before do
    clear_refresh_queue
  end

  def lease(target_type, target_id, scope_id = nil, first_queued_at: 1.hour.ago, cursor: nil)
    create(:authz_refresh_event, target_type: target_type, target_id: target_id, scope_id: scope_id,
      first_queued_at: first_queued_at, cursor: cursor)
    Authz::ProjectAuthorizations::RefreshEvent.lease(duration: 1.minute)
  end

  def expand(...)
    described_class.new(lease(...)).execute
  end

  def pending_events
    Authz::ProjectAuthorizations::RefreshEvent.status_pending
      .map { |event| [event.target_type.to_sym, event.target_id, event.scope_id] }
  end

  it 'expands a group move into an all-user event per project under it or shared with it' do
    expect(expand(:namespace_subtree, subgroup.id).payload).to eq(events: 2)
    expect(pending_events).to contain_exactly([:project, sub_project.id, nil], [:project, shared_with_subgroup.id, nil])
  end

  it "expands a personal namespace's owner change into its projects" do
    personal_project = create(:project, namespace: create(:user, :with_namespace).namespace)
    clear_refresh_queue

    expand(:namespace_subtree, personal_project.namespace_id)

    expect(pending_events).to contain_exactly([:project, personal_project.id, nil])
  end

  it "expands a share lock change into the namespace's own shared projects" do
    expand(:namespace_project_group_links, group.id)

    expect(pending_events).to contain_exactly([:project, linked_project.id, nil])
  end

  it "expands a new or changed share into a membership event per invited group's authorizable direct member" do
    expand(:group_group_link, invited_group.id, group.id)

    expect(pending_events).to contain_exactly([:user_in_group, member.id, group.id])
  end

  it "finishes the lease and keeps its age on the expanded events, so queue age alerts still see it" do
    first_queued_at = 1.hour.ago.round

    expand(:namespace_subtree, subgroup.id, first_queued_at: first_queued_at)

    events = Authz::ProjectAuthorizations::RefreshEvent.all
    expect(events.select(&:status_processed?).map(&:target_type)).to eq(['namespace_subtree'])
    expect(events.select(&:status_pending?).map(&:first_queued_at)).to all(eq(first_queued_at))
  end

  it 'reads from the primary' do
    expect(Gitlab::Database::LoadBalancing::SessionMap.current(ApplicationRecord.load_balancer))
      .to receive(:use_primary).and_call_original

    expand(:namespace_project_group_links, group.id)
  end

  it 'keeps the lease pending when queueing fails' do
    allow(Authz::ProjectAuthorizations::RefreshEvent).to receive(:enqueue).and_raise(ActiveRecord::QueryCanceled)

    expect { expand(:namespace_subtree, subgroup.id) }.to raise_error(ActiveRecord::QueryCanceled)
    expect(pending_events).to contain_exactly([:namespace_subtree, subgroup.id, nil])
  end

  it 'queues nothing when another worker took the expired lease over and expanded it first' do
    stale_lease = lease(:namespace_subtree, subgroup.id)
    described_class.new(stale_lease).execute

    expect { described_class.new(stale_lease).execute }
      .to raise_error(Authz::ProjectAuthorizations::RefreshEvent::LeaseLostError)
    expect(pending_events).to contain_exactly([:project, sub_project.id, nil], [:project, shared_with_subgroup.id, nil])
  end

  describe 'batches' do
    let(:first_id) { [sub_project.id, shared_with_subgroup.id].min }
    let(:second_id) { [sub_project.id, shared_with_subgroup.id].max }

    before do
      stub_const("#{described_class}::BATCH_SIZE", 1)
    end

    it 'commits each batch with the cursor after it, so a failure keeps what was queued' do
      calls = 0
      allow(Authz::ProjectAuthorizations::RefreshEvent).to receive(:enqueue)
        .and_wrap_original do |original, *args, **opts|
        calls += 1
        raise ActiveRecord::QueryCanceled if calls == 2

        original.call(*args, **opts)
      end

      expect { expand(:namespace_subtree, subgroup.id) }.to raise_error(ActiveRecord::QueryCanceled)
      expect(pending_events).to contain_exactly([:namespace_subtree, subgroup.id, nil], [:project, first_id, nil])
      expect(Authz::ProjectAuthorizations::RefreshEvent.namespace_subtree.pick(:cursor)).to eq(first_id)
    end

    it 'resumes after the cursor' do
      expect(expand(:namespace_subtree, subgroup.id, cursor: first_id).payload).to eq(events: 1)
      expect(pending_events).to contain_exactly([:project, second_id, nil])
    end

    it 'finishes a lease resumed after its last batch without queueing anything' do
      expect(expand(:namespace_subtree, subgroup.id, cursor: second_id).payload).to eq(events: 0)
      expect(Authz::ProjectAuthorizations::RefreshEvent.all).to all(be_status_processed)
    end

    it "batches a share's members by user, keeping the shared group on each" do
      other_member = create(:user, developer_of: invited_group)
      clear_refresh_queue

      expand(:group_group_link, invited_group.id, group.id, cursor: [member.id, other_member.id].min)

      expect(pending_events).to contain_exactly([:user_in_group, [member.id, other_member.id].max, group.id])
    end

    it 'queues nothing when another worker holding the same expired lease advanced it first' do
      stale_lease = lease(:namespace_subtree, subgroup.id)
      Authz::ProjectAuthorizations::RefreshEvent.advance(stale_lease, cursor: first_id)

      expect { described_class.new(stale_lease).execute }
        .to raise_error(Authz::ProjectAuthorizations::RefreshEvent::LeaseLostError)
      expect(pending_events).to contain_exactly([:namespace_subtree, subgroup.id, nil])
    end
  end

  it 'expands targets that no longer exist into nothing' do
    expect(expand(:namespace_subtree, non_existing_record_id).payload).to eq(events: 0)
    expect(pending_events).to be_empty
  end

  it 'refuses types that are recalculated directly' do
    expect { expand(:project, project.id) }.to raise_error(ArgumentError)
  end
end
