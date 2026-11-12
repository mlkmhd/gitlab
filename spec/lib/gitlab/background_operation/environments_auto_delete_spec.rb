# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::BackgroundOperation::EnvironmentsAutoDelete, :background_operation, feature_category: :continuous_delivery do
  let(:environments) { table(:environments) }

  let!(:organization) { table(:organizations).create!(name: 'organization', path: 'organization') }
  let!(:namespace) do
    table(:namespaces).create!(name: 'test', path: 'test', type: 'Group', organization_id: organization.id)
  end

  let!(:project) do
    table(:projects).create!(
      namespace_id: namespace.id,
      project_namespace_id: namespace.id,
      organization_id: organization.id
    )
  end

  let!(:env_to_delete) { create_environment(state: 'stopped', auto_delete_at: 1.day.ago) }
  let!(:env_to_delete_2) { create_environment(state: 'stopped', auto_delete_at: 2.days.ago) }
  let!(:env_available) { create_environment(state: 'available', auto_delete_at: 1.day.ago) }
  let!(:env_no_auto_delete) { create_environment(state: 'stopped', auto_delete_at: nil) }
  let!(:env_future_auto_delete) { create_environment(state: 'stopped', auto_delete_at: 1.day.from_now) }

  let!(:min_cursor) { environments.minimum(:id) }
  let!(:max_cursor) { environments.maximum(:id) }

  let!(:operation) do
    described_class.new(
      min_cursor: [min_cursor],
      max_cursor: [max_cursor],
      batch_table: :environments,
      batch_column: :id,
      sub_batch_size: 2,
      pause_ms: 0,
      connection: ::ApplicationRecord.connection
    )
  end

  shared_examples 'deleting stopped environments past their auto_delete_at' do
    it 'deletes stopped environments past their auto_delete_at', :aggregate_failures do
      expect { operation.perform }
        .to change { environments.exists?(env_to_delete.id) }.from(true).to(false)
        .and change { environments.exists?(env_to_delete_2.id) }.from(true).to(false)
        .and not_change { environments.exists?(env_available.id) }
        .and not_change { environments.exists?(env_no_auto_delete.id) }
        .and not_change { environments.exists?(env_future_auto_delete.id) }
    end
  end

  it_behaves_like 'deleting stopped environments past their auto_delete_at'

  it 'deletes each environment in batches' do
    expect(Environments::Job).to receive(:delete_batch_for_environment).twice.and_call_original

    operation.perform
  end

  context 'when environment_delete_in_batches is disabled' do
    before do
      stub_feature_flags(environment_delete_in_batches: false)
    end

    it_behaves_like 'deleting stopped environments past their auto_delete_at'
  end

  it 'only deletes environments matching both conditions' do
    expect { operation.perform }.to change { environments.count }.by(-2)
  end

  context 'when the job runs out of time after the first environment' do
    before do
      allow(Gitlab::Metrics::RuntimeLimiter).to receive(:new).and_call_original
      allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter, described_class::MAX_RUNTIME) do |limiter|
        allow(limiter).to receive(:over_time?).and_return(false, true)
      end
    end

    it 'leaves the next environment for the next run and logs it', :aggregate_failures do
      allow(Gitlab::AppLogger).to receive(:info).and_call_original

      expect { operation.perform }
        .to change { environments.exists?(env_to_delete.id) }.from(true).to(false)
        .and not_change { environments.exists?(env_to_delete_2.id) }

      expect(Gitlab::AppLogger).to have_received(:info).with(
        hash_including(
          'message' => 'Environments left for the next auto-delete run',
          environment_count: 1,
          environment_ids: [env_to_delete_2.id]
        )
      )
    end
  end

  context 'when an environment is left partially deleted' do
    before do
      allow_next_instance_of(Environments::DestroyService) do |service|
        allow(service).to receive(:unsafe_execute!).and_call_original
        allow(service).to receive(:unsafe_execute!).with(have_attributes(id: env_to_delete.id))
          .and_return(ServiceResponse.error(message: 'incomplete', reason: :incomplete))
      end
    end

    it 'logs it for the next run' do
      allow(Gitlab::AppLogger).to receive(:info).and_call_original

      operation.perform

      expect(Gitlab::AppLogger).to have_received(:info)
        .with(hash_including(environment_ids: [env_to_delete.id]))
    end
  end

  context 'when an environment is not deleted' do
    before do
      allow_next_instance_of(Environments::DestroyService) do |service|
        allow(service).to receive(:unsafe_execute!).and_call_original
        allow(service).to receive(:unsafe_execute!).with(have_attributes(id: env_to_delete.id))
          .and_return(ServiceResponse.error(message: 'error'))
      end
    end

    it 'keeps the environment and does not count it', :aggregate_failures do
      expect { operation.perform }
        .to change { environments.exists?(env_to_delete_2.id) }.from(true).to(false)
        .and not_change { environments.exists?(env_to_delete.id) }

      expect(operation.batch_metrics.affected_rows[:delete_all].sum).to eq(1)
    end
  end

  private

  def create_environment(state:, auto_delete_at:)
    environments.create!(
      project_id: project.id,
      name: "env-#{SecureRandom.hex(4)}",
      slug: SecureRandom.hex(8),
      state: state,
      auto_delete_at: auto_delete_at
    )
  end
end
