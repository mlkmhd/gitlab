# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Llm::NamespaceAccessCacheResetWorker, :saas, feature_category: :ai_abstraction_layer do
  let_it_be_with_reload(:group) { create(:group_with_plan, plan: :ultimate_plan) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:sub_group) { create(:group, parent: group) }

  let_it_be(:group_member) { create(:group_member, group: group, user: create(:user)) }
  let_it_be(:sub_group_member) { create(:group_member, group: sub_group, user: create(:user)) }
  let_it_be(:project_member) { create(:project_member, project: project, user: create(:user)) }

  let(:source_id) { group.id }

  it_behaves_like 'worker with data consistency', described_class, data_consistency: :delayed

  it 'reschedules a deduplicated job once' do
    expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
    expect(described_class.get_deduplication_options).to include(if_deduplicated: :reschedule_once)
  end

  it 'has a concurrency limit' do
    expect(described_class.get_concurrency_limit).to eq(10)
  end

  it 'defers on the members table health signal' do
    expect(described_class.database_health_check_attrs).to include(
      gitlab_schema: :gitlab_main, tables: %i[members], delay_by: 10.minutes
    )
  end

  shared_examples 'success' do
    context 'when namespace has AI features' do
      before do
        stub_licensed_features(ai_features: true)
      end

      context 'when namespace can not be found' do
        let(:source_id) { non_existing_record_id }

        it 'does not clear cache' do
          expect(User).not_to receive(:clear_group_with_ai_available_cache)

          consume_event(subscriber: described_class, event: event)
        end
      end

      context 'when namespace can be found' do
        it 'clears cache for affected users' do
          expect(User).to receive(:clear_group_with_ai_available_cache).with(match_array(affected_user_ids))

          consume_event(subscriber: described_class, event: event)
        end
      end

      context 'when user is member multiple times', :use_clean_rails_redis_caching do
        let_it_be(:group_member2) { create(:group_member, group: sub_group, user: project_member.user) }

        it 'calls cache deletion only once for a user' do
          expect(User).to receive(:clear_group_with_ai_available_cache).with(match_array(affected_user_ids))

          consume_event(subscriber: described_class, event: event)
        end
      end
    end

    context 'when namespace has no AI features' do
      before do
        stub_licensed_features(ai_features: false)
      end

      it 'does not clear cache for any user' do
        expect(User).not_to receive(:clear_group_with_ai_available_cache)

        consume_event(subscriber: described_class, event: event)
      end
    end
  end

  context 'when AiRelatedSettingsChangedEvent' do
    let(:data) { { group_id: source_id } }
    let(:event) { NamespaceSettings::AiRelatedSettingsChangedEvent.new(data: data) }
    let(:affected_user_ids) { [group_member.user.id, sub_group_member.user.id, project_member.user.id] }

    it_behaves_like 'subscribes to event'
    it_behaves_like 'success'

    context 'when the hierarchy has more members than one batch' do
      before do
        stub_licensed_features(ai_features: true)
        stub_const('Ai::HierarchyMemberUserIds::MEMBER_BATCH_SIZE', 1)
      end

      it 'clears cache one batch at a time' do
        cleared_user_ids = []
        allow(User).to receive(:clear_group_with_ai_available_cache) { |user_ids| cleared_user_ids << user_ids }

        consume_event(subscriber: described_class, event: event)

        expect(cleared_user_ids).to all(have_attributes(size: 1))
        expect(cleared_user_ids.flatten).to match_array(affected_user_ids)
      end

      it 'logs the number of batches and user IDs cleared' do
        worker = described_class.new
        expect(worker).to receive(:log_hash_metadata_on_done).with(user_id_batches: 3, user_ids_cleared: 3)

        worker.handle_event(event)
      end
    end

    context 'when batch_ai_namespace_access_cache_reset is disabled' do
      before do
        stub_feature_flags(batch_ai_namespace_access_cache_reset: false)
      end

      it_behaves_like 'success'

      it 'does not read members in batches' do
        stub_licensed_features(ai_features: true)

        expect(Ai::HierarchyMemberUserIds).not_to receive(:new)

        consume_event(subscriber: described_class, event: event)
      end
    end
  end

  context 'when members are added to a group' do
    let_it_be(:current_user) { create(:user) }
    let_it_be(:existing_member) do
      create(:group_member, group: group, user: create(:user), created_at: (1.hour + 1.minute).ago)
    end

    let(:affected_user_ids) { [group_member.user.id] }

    context 'with AddedCloudEvent' do
      let(:event) do
        Members::AddedCloudEvent.build(
          source: Group.new(id: source_id, organization: group.organization),
          current_user: current_user,
          invited_user_ids: affected_user_ids
        )
      end

      it_behaves_like 'subscribes to event'
      it_behaves_like 'success'

      it 'does not read the hierarchy in batches' do
        stub_licensed_features(ai_features: true)

        expect(Ai::HierarchyMemberUserIds).not_to receive(:new)

        consume_event(subscriber: described_class, event: event)
      end
    end
  end

  context 'when members are added to a project' do
    let_it_be(:current_user) { create(:user) }
    let_it_be(:existing_member) do
      create(:project_member, project: project, user: create(:user), created_at: (1.hour + 1.minute).ago)
    end

    let(:source_id) { project.id }
    let(:affected_user_ids) { [project_member.user.id] }

    context 'with AddedCloudEvent' do
      let(:event) do
        Members::AddedCloudEvent.build(
          source: Project.new(id: source_id, organization: project.organization),
          current_user: current_user,
          invited_user_ids: affected_user_ids
        )
      end

      it_behaves_like 'subscribes to event'
      it_behaves_like 'success'
    end
  end
end
