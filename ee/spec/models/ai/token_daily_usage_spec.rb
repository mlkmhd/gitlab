# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::TokenDailyUsage, feature_category: :ai_abstraction_layer do
  let_it_be(:user) { create(:user) }

  subject(:usage) { build(:ai_token_daily_usage, user: user) }

  it { is_expected.to include_module(PartitionedTable) }

  describe 'partitioning' do
    let(:strategy) { described_class.partitioning_strategy }

    it 'partitions monthly by usage date', :aggregate_failures do
      expect(strategy).to be_a(Gitlab::Database::Partitioning::Time::MonthlyStrategy)
      expect(strategy.partitioning_key).to eq(:usage_date)
    end

    it 'keeps 1,095 days by default' do
      create(:application_setting)
      ApplicationSetting.expire

      expect(strategy.retain_for).to eq(1095.days)
    end

    it 'keeps the retention period an administrator sets' do
      create(:application_setting, duo_token_usage_retention_days: 365)
      ApplicationSetting.expire

      expect(strategy.retain_for).to eq(365.days)
    end

    it 'keeps 1,095 days when the stored period is null' do
      setting = create(:application_setting)
      setting.update_column(:duo_settings, setting.duo_settings.merge('duo_token_usage_retention_days' => nil))
      ApplicationSetting.expire

      expect(strategy.retain_for).to eq(1095.days)
    end

    it 'keeps 1,095 days when there is no settings row' do
      allow(ApplicationSetting).to receive(:current).and_return(nil)

      expect(strategy.retain_for).to eq(1095.days)
    end

    it 'keeps the stored period while a rake task has pending migrations' do
      create(:application_setting, duo_token_usage_retention_days: 3650)
      ApplicationSetting.expire
      allow(Gitlab::Runtime).to receive(:rake?).and_return(true)
      allow(Gitlab::ApplicationSettingFetcher).to receive(:needs_migration?).and_return(true)
      stub_env('IN_MEMORY_APPLICATION_SETTINGS', 'false')

      expect(strategy.retain_for).to eq(3650.days)
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:organization).class_name('Organizations::Organization') }
  end

  describe '#organization_id' do
    let_it_be(:group) { create(:group, organization: create(:organization)) }

    it 'populates the organization of the user when the row has no namespace' do
      expect(described_class.new(user: user)).to populate_sharding_key(:organization_id).with(user.organization_id)
    end

    it 'populates the organization of the namespace when the row has one' do
      expect(described_class.new(user: user, traversal_ids: group.traversal_ids))
        .to populate_sharding_key(:organization_id).with(group.organization_id)
    end

    it 'leaves the organization empty when the namespace no longer exists' do
      usage = described_class.new(user: user, traversal_ids: [non_existing_record_id])

      usage.validate

      expect(usage.organization_id).to be_nil
    end
  end

  describe 'validations' do
    it { is_expected.to be_valid }
    it { is_expected.to validate_presence_of(:usage_date) }
    it { is_expected.to validate_presence_of(:user_id) }
    it { expect(described_class.new).to validate_presence_of(:organization_id) }
    it { is_expected.to validate_presence_of(:feature) }
    it { is_expected.to validate_presence_of(:model) }
    it { is_expected.to validate_length_of(:model).is_at_most(255) }

    it { is_expected.to validate_numericality_of(:input_tokens).only_integer.is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:output_tokens).only_integer.is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:events_count).only_integer.is_greater_than_or_equal_to(0) }

    it 'rejects a new row dated before the retention period' do
      usage.usage_date = (described_class::DEFAULT_RETENTION_DAYS + 1).days.ago.to_date

      expect(usage).not_to be_valid
      expect(usage.errors[:usage_date]).to be_present
    end

    it 'rejects a new row dated past the months that have a partition' do
      headroom = described_class.partitioning_strategy.class::HEADROOM
      usage.usage_date = (Date.current.end_of_month + headroom).end_of_month + 1.day

      expect(usage).not_to be_valid
      expect(usage.errors[:usage_date]).to be_present
    end

    it 'accepts a new row dated on the last day that has a partition' do
      headroom = described_class.partitioning_strategy.class::HEADROOM
      usage.usage_date = (Date.current.end_of_month + headroom).end_of_month

      expect(usage).to be_valid
    end
  end

  describe '.buffer_usage', :clean_gitlab_redis_shared_state do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:member) { create(:user, organizations: [organization]) }
    let_it_be(:group) { create(:group, organization: organization) }
    let_it_be(:project) { create(:project, namespace: group) }

    let(:event_name) { 'report_duo_chat_token_usage' }
    let(:namespace) { project.project_namespace }
    let(:timestamp) { Time.current.utc.beginning_of_day - 1.second }
    let(:usage) do
      {
        'claude-sonnet-4-5' => { 'input_tokens' => 8, 'output_tokens' => 12 },
        'claude-haiku-4-5' => { 'input_tokens' => 3, 'output_tokens' => 5 }
      }
    end

    let(:event) do
      Ai::UsageEvent.new(user: member, namespace: namespace, event: event_name, timestamp: timestamp,
        extras: { 'request_id' => 'request-1', 'usage' => usage }.with_indifferent_access).tap(&:validate!)
    end

    let(:buffered) { described_class.write_buffer.pop(10) }

    it 'buffers one row per model, dated by the UTC day of the event' do
      described_class.buffer_usage(event)

      expect(buffered).to contain_exactly(
        hash_including('model' => 'claude-sonnet-4-5', 'input_tokens' => 8, 'output_tokens' => 12),
        hash_including('model' => 'claude-haiku-4-5', 'input_tokens' => 3, 'output_tokens' => 5)
      )
      expect(buffered).to all(include(
        'organization_id' => event.organization_id, 'user_id' => member.id, 'feature' => 'chat',
        'traversal_ids' => namespace.traversal_ids, 'usage_date' => timestamp.to_date.iso8601, 'events_count' => 1,
        'namespace_id' => namespace.id, 'event' => event_name
      ))
    end

    it 'ends the chain of a project event at its project namespace' do
      described_class.buffer_usage(event)

      expect(buffered.first['traversal_ids']).to eq([group.id, namespace.id])
    end

    it 'dates by the UTC day when the application time zone is on another day' do
      Time.use_zone('Pacific/Auckland') { described_class.buffer_usage(event) }

      expect(buffered).to contain_exactly(
        hash_including('model' => 'claude-sonnet-4-5', 'usage_date' => timestamp.to_date.iso8601),
        hash_including('model' => 'claude-haiku-4-5', 'usage_date' => timestamp.to_date.iso8601)
      )
    end

    context 'when the event has no namespace' do
      let(:namespace) { nil }

      it 'buffers an empty chain' do
        described_class.buffer_usage(event)

        expect(buffered).to contain_exactly(
          hash_including('model' => 'claude-sonnet-4-5', 'traversal_ids' => []),
          hash_including('model' => 'claude-haiku-4-5', 'traversal_ids' => [])
        )
      end

      it 'buffers the organization of the user' do
        described_class.buffer_usage(event)

        expect(buffered).to contain_exactly(
          hash_including('model' => 'claude-sonnet-4-5', 'organization_id' => member.organization_id),
          hash_including('model' => 'claude-haiku-4-5', 'organization_id' => member.organization_id)
        )
      end
    end

    context 'when the namespace is in another organization than the user' do
      let_it_be(:other_organization) { create(:organization) }
      let_it_be(:other_group) { create(:group, organization: other_organization) }

      let(:namespace) { other_group }

      it 'buffers the organization of the namespace' do
        expect(member.organization_id).not_to eq(other_organization.id)

        described_class.buffer_usage(event)

        expect(buffered).to contain_exactly(
          hash_including('model' => 'claude-sonnet-4-5', 'organization_id' => other_organization.id),
          hash_including('model' => 'claude-haiku-4-5', 'organization_id' => other_organization.id)
        )
      end
    end

    context 'when the event is not a token usage event' do
      let(:event_name) { 'request_duo_chat_response' }

      it 'buffers nothing' do
        described_class.buffer_usage(event)

        expect(buffered).to be_empty
      end
    end

    context 'when the event carries no usage' do
      let(:usage) { nil }

      it 'buffers nothing' do
        described_class.buffer_usage(event)

        expect(buffered).to be_empty
      end
    end

    context 'when the usage is not keyed by model' do
      let(:usage) { [8, 12] }

      it 'buffers nothing' do
        described_class.buffer_usage(event)

        expect(buffered).to be_empty
      end
    end

    context 'when a model carries no token counts' do
      let(:usage) { { 'claude-sonnet-4-5' => { 'input_tokens' => 8, 'output_tokens' => 12 }, 'claude-haiku-4-5' => 5 } }

      it 'buffers only the models that do' do
        described_class.buffer_usage(event)

        expect(buffered.pluck('model')).to eq(['claude-sonnet-4-5'])
      end
    end

    context 'when no model carries token counts' do
      let(:usage) { { 'claude-haiku-4-5' => 5 } }

      it 'buffers nothing' do
        described_class.buffer_usage(event)

        expect(buffered).to be_empty
      end
    end

    context 'when the event has no extras' do
      let(:event) do
        Ai::UsageEvent.new(user: member, namespace: namespace, event: event_name, timestamp: timestamp, extras: nil)
      end

      it 'buffers nothing' do
        described_class.buffer_usage(event)

        expect(buffered).to be_empty
      end
    end
  end

  describe '.transfer_organization' do
    let_it_be(:from) { create(:organization) }
    let_it_be(:to) { create(:organization) }

    let(:relation) { described_class.where(user_id: user.id) }

    def create_usage(organization: from, **attributes)
      create(:ai_token_daily_usage, user: user, organization: organization, **attributes)
    end

    def transfer
      described_class.transfer_organization(relation, from: from.id, to: to.id)
    end

    it 'moves the rows of the relation from the source organization to the target' do
      usage = create_usage

      transfer

      expect(usage.reload.organization_id).to eq(to.id)
    end

    it 'does not move the rows of the relation in another organization' do
      usage = create_usage(organization: create(:organization))

      expect { transfer }.not_to change { usage.reload.organization_id }
    end

    it 'does not move the rows outside the relation' do
      usage = create(:ai_token_daily_usage, user: create(:user), organization: from)

      expect { transfer }.not_to change { usage.reload.organization_id }
    end

    it 'reads the rows once, without ordering by id, when none match' do
      create_usage(organization: to)

      recorder = ActiveRecord::QueryRecorder.new { transfer }

      expect(recorder.log).to contain_exactly(a_string_including('LIMIT 1000'))
      expect(recorder.log.first).not_to include('ORDER BY')
    end

    it 'bounds each update to the dates of the rows it moves' do
      today = Time.current.utc.to_date
      create_usage(usage_date: today)
      create_usage(usage_date: today - 2.months)

      recorder = ActiveRecord::QueryRecorder.new { transfer }
      update = recorder.log.find { |query| query.start_with?('UPDATE') }

      expect(update).to include('"ai_token_daily_usages"."usage_date" IN', today.to_s, (today - 2.months).to_s)
    end

    it 'sends no query when the source and target organizations are the same' do
      recorder = ActiveRecord::QueryRecorder.new do
        described_class.transfer_organization(relation, from: from.id, to: from.id)
      end

      expect(recorder.count).to eq(0)
    end

    context 'when the rows span several batches' do
      include_context 'with transfer batch size of 1'

      let(:execute_service) { transfer }
      let(:expected_batch_queries) { { 'ai_token_daily_usages' => 3 } }

      before do
        3.times { |i| create_usage(model: "model-#{i}") }
      end

      it_behaves_like 'generates batched transfer queries'

      it 'moves the rows of every batch' do
        transfer

        expect(described_class.where(organization_id: to.id).count).to eq(3)
      end
    end
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:feature).with_values(chat: 0) }
  end

  describe '.find' do
    it 'finds a row by its id alone, without the partition key' do
      usage = create(:ai_token_daily_usage, user: user)

      expect(described_class.find(usage[:id])).to eq(usage)
    end
  end

  describe 'database constraints' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:group) { create(:group, organization: organization) }

    let(:tuple) do
      { organization: organization, usage_date: Date.current.beginning_of_month, traversal_ids: group.traversal_ids,
        user: user, feature: :chat, model: 'claude-sonnet-4-6' }
    end

    it 'keeps one row per day, organization, namespace, user, feature and model' do
      create(:ai_token_daily_usage, tuple)

      expect { create(:ai_token_daily_usage, tuple) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'keeps a row per model, so usage is never summed across models' do
      create(:ai_token_daily_usage, tuple)

      expect { create(:ai_token_daily_usage, tuple.merge(model: 'claude-haiku-4-5')) }
        .to change { described_class.count }.by(1)
    end

    it 'keeps usage with no namespace under its organization' do
      create(:ai_token_daily_usage, tuple.merge(traversal_ids: []))

      expect { create(:ai_token_daily_usage, tuple.merge(traversal_ids: [])) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'keeps a row per day in the same month' do
      create(:ai_token_daily_usage, tuple)

      expect { create(:ai_token_daily_usage, tuple.merge(usage_date: tuple[:usage_date] + 1.day)) }
        .to change { described_class.count }.by(1)
    end

    it 'rejects negative token counts' do
      usage = create(:ai_token_daily_usage, tuple)

      expect { usage.update_column(:input_tokens, -1) }
        .to raise_error(ActiveRecord::StatementInvalid, /check_ai_token_daily_usages_input_tokens_non_negative/)
    end
  end
end
