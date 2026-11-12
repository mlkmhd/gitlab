# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::GroupActivityCalculator, :use_clean_rails_memory_store_caching,
  feature_category: :value_stream_management do
  subject { described_class.new(group, current_user) }

  let_it_be(:group) { create(:group) }
  let_it_be(:current_user) { create(:user) }
  let_it_be(:another_user) { create(:user) }
  let_it_be(:subgroup) { create(:group, parent: group, developers: [current_user, another_user]) }
  let_it_be(:project) { create(:project, group: subgroup, developers: current_user) }
  let_it_be(:secret_project) { create(:project, group: create(:group, parent: group)) }

  context 'with issues' do
    before_all do
      create(:issue, project: project)
      create(:issue, project: project, created_at: 40.days.ago)
    end

    it 'only returns the count of recent issues' do
      expect(subject.issues_count).to eq 1
    end

    context 'when user does not have access to some issues' do
      it 'does not include those issues' do
        create(:issue, project: secret_project)

        expect(subject.issues_count).to eq 1
      end
    end

    it 'caches value per user' do
      expect(subject.issues_count).to eq 1

      create(:issue, project: project)

      expect(subject.issues_count).to eq 1
      expect(described_class.new(group, another_user).issues_count).to eq 2
    end

    it 'limits count to RECENT_COUNT_LIMIT' do
      stub_const('Analytics::GroupActivityCalculator::RECENT_COUNT_LIMIT', 2)

      create(:issue, project: project)
      create(:issue, project: project)

      expect(subject.issues_count).to eq 2
    end
  end

  context 'with merge requests' do
    before_all do
      create(:merge_request,
        source_project: project,
        source_branch: "my-personal-branch-1")

      create(:merge_request,
        source_project: project,
        source_branch: "my-personal-branch-2",
        created_at: 40.days.ago)
    end

    it 'only returns the count of recent MRs' do
      expect(subject.merge_requests_count).to eq 1
    end

    context 'when user does not have access to some MRs' do
      it 'does not include those MRs' do
        create(:merge_request, source_project: secret_project)

        expect(subject.merge_requests_count).to eq 1
      end
    end

    it 'caches value per user' do
      expect(subject.merge_requests_count).to eq 1

      create(:merge_request,
        source_project: project,
        source_branch: "my-personal-branch-3")

      expect(subject.merge_requests_count).to eq 1
      expect(described_class.new(group, another_user).merge_requests_count).to eq 2
    end

    it 'limits count to RECENT_COUNT_LIMIT' do
      stub_const('Analytics::GroupActivityCalculator::RECENT_COUNT_LIMIT', 2)

      create(:merge_request,
        source_project: project,
        source_branch: "my-personal-branch-3")
      create(:merge_request,
        source_project: project,
        source_branch: "my-personal-branch-4")

      expect(subject.merge_requests_count).to eq 2
    end
  end

  context 'with members' do
    it 'returns the count of recently added members' do
      expect(subject.new_members_count).to eq 2 # current_user + another_user
    end

    context 'when there is a member who was not added recently' do
      before do
        travel_to(40.days.ago) do
          subgroup.add_developer create(:user, created_at: 2.days.ago)
        end
      end

      it 'returns the count of recently added members' do
        expect(subject.new_members_count).to eq 2 # current_user + another_user
      end
    end

    context 'when user does not have access to some members' do
      it 'does not include those members' do
        secret_project.add_developer create(:user)

        expect(subject.new_members_count).to eq 2
      end
    end

    it 'caches value per user' do
      expect(subject.new_members_count).to eq 2

      subgroup.add_developer create(:user)

      expect(subject.new_members_count).to eq 2
      expect(described_class.new(group, another_user).new_members_count).to eq 3
    end

    it 'limits count to RECENT_COUNT_LIMIT' do
      stub_const('Analytics::GroupActivityCalculator::RECENT_COUNT_LIMIT', 2)

      subgroup.add_developer create(:user)
      subgroup.add_developer create(:user)

      expect(subject.new_members_count).to eq 2
    end
  end

  describe 'when a count times out' do
    let(:cache_key) { ['groups', 'recent_30d_merge_requests_count', group.id, current_user.id] }

    before do
      allow_next_instance_of(MergeRequestsFinder) do |finder|
        allow(finder).to receive(:execute).and_raise(ActiveRecord::QueryCanceled)
      end
    end

    it 'returns the limit and marks the count as too large' do
      expect(subject.merge_requests_count).to eq(described_class::RECENT_COUNT_LIMIT)
      expect(subject.too_large?(:merge_requests)).to be(true)
      expect(subject.too_large?(:issues)).to be(false)
    end

    it 'logs the timeout with the group id and count type' do
      expect(Gitlab::ErrorTracking).to receive(:log_exception).with(
        instance_of(ActiveRecord::QueryCanceled),
        { Labkit::Fields::GL_NAMESPACE_ID => group.id, count_type: :merge_requests }
      )

      subject.merge_requests_count
    end

    it 'caches the result for an hour without running the query again' do
      subject.merge_requests_count

      expect(Rails.cache.read(cache_key)).to eq(described_class::TOO_LARGE)
      expect(MergeRequestsFinder).not_to receive(:new)

      calculator = described_class.new(group, current_user)

      expect(calculator.merge_requests_count).to eq(described_class::RECENT_COUNT_LIMIT)
      expect(calculator.too_large?(:merge_requests)).to be(true)

      travel_to(61.minutes.from_now) do
        expect(Rails.cache.read(cache_key)).to be_nil
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(group_activity_fast_count_timeout: false)
      end

      it 'raises and caches nothing' do
        expect { subject.merge_requests_count }.to raise_error(ActiveRecord::QueryCanceled)
        expect(Rails.cache.read(cache_key)).to be_nil
      end

      it 'still returns a too large result cached while the flag was enabled' do
        Rails.cache.write(cache_key, described_class::TOO_LARGE)

        expect(subject.merge_requests_count).to eq(described_class::RECENT_COUNT_LIMIT)
        expect(subject.too_large?(:merge_requests)).to be(true)
      end
    end
  end

  describe '#too_large?' do
    it 'raises for an unknown type' do
      expect { subject.too_large?(:unknown) }
        .to raise_error(ArgumentError, 'unknown group activity type: unknown')
    end
  end

  describe 'statement timeout' do
    before_all do
      create(:issue, project: project)
    end

    it 'cancels a count that runs longer than the timeout' do
      stub_const("#{described_class}::STATEMENT_TIMEOUT_MS", 1)
      allow_next_instance_of(IssuesFinder) do |finder|
        allow(finder).to receive(:execute).and_wrap_original do |method, *args|
          method.call(*args).where('(SELECT pg_sleep(0.1)::text) IS NOT NULL')
        end
      end

      expect(subject.issues_count).to eq(described_class::RECENT_COUNT_LIMIT)
      expect(subject.too_large?(:issues)).to be(true)
    end

    it 'does not change a count that finishes in time' do
      expect(subject.issues_count).to eq(1)
      expect(subject.too_large?(:issues)).to be(false)
    end

    context 'when the feature flag is enabled for the root group only' do
      before do
        stub_feature_flags(group_activity_fast_count_timeout: group)
      end

      it 'sets a statement timeout for a subgroup' do
        recorder = ActiveRecord::QueryRecorder.new { described_class.new(subgroup, current_user).issues_count }

        expect(recorder.log).to include(a_string_including('statement_timeout'))
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(group_activity_fast_count_timeout: false)
      end

      it 'does not set a statement timeout' do
        recorder = ActiveRecord::QueryRecorder.new { expect(subject.issues_count).to eq(1) }

        expect(recorder.log).not_to include(a_string_including('statement_timeout'))
      end
    end
  end
end
