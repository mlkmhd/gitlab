# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authz::ProjectAuthorizations::RecalculateProjectService, feature_category: :permissions do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:developer) { create(:user) }
  let_it_be(:maintainer) { create(:user) }
  let_it_be(:outsider) { create(:user) }

  before_all do
    group.add_developer(developer)
    project.add_maintainer(maintainer)
  end

  before do
    ProjectAuthorization.where(project: project).delete_all
    ProjectAuthorization.insert_all([
      { user_id: developer.id, project_id: project.id, access_level: Gitlab::Access::DEVELOPER, is_unique: true },
      { user_id: outsider.id, project_id: project.id, access_level: Gitlab::Access::DEVELOPER, is_unique: true }
    ])
  end

  def levels
    ProjectAuthorization.where(project: project).pluck(:user_id, :access_level)
  end

  it 'adds missing users, removes users without access, and keeps the rest' do
    result = Authz::ProjectAuthorizations::WriteBatchService::Result.new(1, 1)

    expect(described_class.new(project.id).execute.payload).to eq(complete: true, requested: result, written: result)

    expect(levels).to contain_exactly(
      [developer.id, Gitlab::Access::DEVELOPER], [maintainer.id, Gitlab::Access::MAINTAINER]
    )
  end

  it 'writes only the users whose rows are wrong' do
    written = []
    allow_next_instances_of(Authz::ProjectAuthorizations::WriteBatchService, 1) do |service|
      allow(service).to receive(:execute).and_wrap_original do |original, ids, &block|
        written.concat(ids)
        original.call(ids, &block)
      end
    end

    described_class.new(project.id).execute

    expect(written).to contain_exactly(maintainer.id, outsider.id)
  end

  it 'reads the stored rows from the primary, before and after waiting for writers' do
    # The spec's session already sticks to the primary, so this records whether each read asked for it.
    session = ::Gitlab::Database::LoadBalancing::SessionMap.current(ProjectAuthorization.load_balancer)
    in_use_primary = false
    allow(session).to receive(:use_primary).and_wrap_original do |original, *args, &block|
      original.call(*args) do
        in_use_primary = true
        block.call
      ensure
        in_use_primary = false
      end
    end
    on_primary = []
    allow(ProjectAuthorization).to receive(:stored_levels_for_project).and_wrap_original do |original, *args|
      on_primary << in_use_primary
      original.call(*args)
    end

    described_class.new(project.id).execute

    # Later reads are WriteBatchService's, inside its write transaction.
    expect(on_primary.first(2)).to eq([true, true])
  end

  it 'waits for writers of every calculated and stored user before comparing' do
    expect(Authz::ProjectAuthorizations::WriteBatchService).to receive(:wait_for_writers)
      .with(match_array([developer.id, maintainer.id, outsider.id])).and_call_original

    described_class.new(project.id).execute
  end

  it 'calculates each chunk with a newly loaded project, so a move after the comparison is seen' do
    stub_const("#{described_class}::CHUNK_SIZE", 1)
    calculated_with = []
    allow(Projects::Members::EffectiveAccessLevelPerUserFinder).to receive(:new).and_wrap_original do |original, *args|
      calculated_with << args.first
      original.call(*args)
    end

    described_class.new(project.id).execute

    expect(calculated_with.size).to eq(2)
    expect(calculated_with.map(&:object_id).uniq.size).to eq(2)
  end

  it 'writes the first chunk, then stops once over time' do
    stub_const("#{described_class}::CHUNK_SIZE", 1)
    expect(Authz::ProjectAuthorizations::WriteBatchService).to receive(:new).once.and_call_original

    result = described_class.new(project.id, runtime_limiter: Gitlab::Metrics::RuntimeLimiter.new(0)).execute

    expect(result.payload).to include(complete: false)
    # Asked for both users' rows, but wrote only the first chunk's.
    expect(result.payload[:requested]).to eq(Authz::ProjectAuthorizations::WriteBatchService::Result.new(1, 1))
    expect(result.payload[:written].to_h.values.sum).to eq(1)
  end

  it 'is complete when it finishes, even if the limiter went over time before it started' do
    limiter = Gitlab::Metrics::RuntimeLimiter.new(0)
    limiter.over_time?

    expect(described_class.new(project.id, runtime_limiter: limiter).execute.payload).to include(complete: true)
  end

  it 'writes nothing when every row is already right' do
    described_class.new(project.id).execute

    expect(Authz::ProjectAuthorizations::WriteBatchService).not_to receive(:new)

    expect(described_class.new(project.id).execute.payload).to include(complete: true)
  end

  it 'writes nothing when the project is deleted before a chunk is written' do
    allow(Project).to receive(:find_by_id).and_call_original
    allow(Project).to receive(:find_by_id).with(project.id).and_return(project, nil)

    expect { described_class.new(project.id).execute }.not_to change { levels }
  end

  it "grants no access in a chunk when the project is gone by the time it's calculated" do
    # The comparison and WriteBatchService still find the project; the chunk's own reload doesn't.
    allow(Project).to receive(:find_by_id).and_call_original
    allow(Project).to receive(:find_by_id).with(project.id).and_return(project, project, nil)
    expect(Projects::Members::EffectiveAccessLevelPerUserFinder).not_to receive(:new)

    described_class.new(project.id).execute

    expect(levels).to contain_exactly([developer.id, Gitlab::Access::DEVELOPER])
  end

  context 'when users whose rows would change are blocked' do
    let_it_be(:blocked_member) { create(:user, :blocked) }
    let_it_be(:blocked_outsider) { create(:user, :blocked) }

    before_all do
      project.add_developer(blocked_member)
    end

    before do
      ProjectAuthorization.insert_all([{ user_id: blocked_outsider.id, project_id: project.id,
                                         access_level: Gitlab::Access::DEVELOPER, is_unique: true }])
    end

    it 'leaves their rows as they are and still writes the active users' do
      described_class.new(project.id).execute

      expect(levels).to contain_exactly(
        [developer.id, Gitlab::Access::DEVELOPER], [maintainer.id, Gitlab::Access::MAINTAINER],
        [blocked_outsider.id, Gitlab::Access::DEVELOPER]
      )
    end

    it 'looks up only the users whose rows would change' do
      expect(Authz::ProjectAuthorizations::BlockedUserRefreshSkip).to receive(:skipped_user_ids).with(
        contain_exactly(maintainer.id, outsider.id, blocked_member.id, blocked_outsider.id),
        skipped_in: :project_recalculate
      ).and_call_original

      described_class.new(project.id).execute
    end

    context 'when skip_authorization_refresh_for_blocked_users is disabled' do
      before do
        stub_feature_flags(skip_authorization_refresh_for_blocked_users: false)
      end

      it 'writes the blocked users too' do
        described_class.new(project.id).execute

        expect(levels).to contain_exactly(
          [developer.id, Gitlab::Access::DEVELOPER], [maintainer.id, Gitlab::Access::MAINTAINER],
          [blocked_member.id, Gitlab::Access::DEVELOPER]
        )
      end
    end
  end

  it 'does nothing for a project that no longer exists' do
    expect(Authz::ProjectAuthorizations::WriteBatchService).not_to receive(:new)

    expect(described_class.new(non_existing_record_id).execute.payload).to include(complete: true)
  end
end
