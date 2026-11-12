# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Compliance::Anthropic::Session, feature_category: :compliance_management do
  subject(:session) { build(:ai_compliance_anthropic_session) }

  describe 'associations' do
    it { is_expected.to belong_to(:namespace).class_name('::Group').required }
    it { is_expected.to belong_to(:anthropic_integration).class_name('::Ai::Compliance::Anthropic::Integration').required }
    it { is_expected.to belong_to(:ai_governance_session).class_name('::Ai::Governance::Session').required }
  end

  describe 'validations' do
    subject(:session) { create(:ai_compliance_anthropic_session) }

    it { is_expected.to be_valid }
    it { is_expected.to validate_presence_of(:session_xid) }
    it { is_expected.to validate_length_of(:session_xid).is_at_most(255) }
    it { is_expected.to validate_length_of(:message_watermark).is_at_most(255) }
    it { is_expected.to validate_uniqueness_of(:ai_governance_session_id) }

    it 'allows the same session id twice in one namespace' do
      duplicate = build(:ai_compliance_anthropic_session,
        namespace: session.namespace,
        anthropic_integration: session.anthropic_integration,
        session_xid: session.session_xid,
        ai_governance_session: create(:ai_governance_session, :external, namespace: session.namespace))

      expect(duplicate).to be_valid
    end

    it 'is invalid when the namespace differs from the integration namespace' do
      session.namespace = create(:group)

      expect(session).not_to be_valid
      expect(session.errors[:namespace]).to include(_('must match the Anthropic Compliance integration namespace'))
    end

    it 'is valid when the governance session is in the same namespace' do
      expect(session.ai_governance_session.namespace_id).to eq(session.namespace_id)
      expect(session).to be_valid
    end

    it 'is invalid when the governance session belongs to another namespace' do
      session.ai_governance_session = create(:ai_governance_session, :external)

      expect(session).not_to be_valid
      expect(session.errors[:namespace]).to include(_('must match the AI governance session namespace'))
    end
  end

  describe 'sharding key' do
    let(:integration) { build_stubbed(:ai_compliance_anthropic_integration) }

    subject(:session) { described_class.new(anthropic_integration: integration) }

    it { is_expected.to populate_sharding_key(:namespace_id).with(integration.namespace_id) }
  end

  describe '.find_for' do
    let_it_be(:session) { create(:ai_compliance_anthropic_session) }
    let_it_be(:other_governance_session) { create(:ai_governance_session, :external) }

    it 'returns the row for the governance session, or nil without creating one', :aggregate_failures do
      expect(described_class.find_for(session.ai_governance_session)).to eq(session)
      expect { expect(described_class.find_for(other_governance_session)).to be_nil }
        .not_to change { described_class.count }
    end
  end

  describe '.find_or_create_for!' do
    let_it_be(:integration) { create(:ai_compliance_anthropic_integration) }
    let_it_be(:governance_session) do
      create(:ai_governance_session, :external, namespace: integration.namespace, external_xid: 'clls_1')
    end

    subject(:find_or_create) do
      described_class.find_or_create_for!(
        anthropic_integration: integration, ai_governance_session: governance_session, session_xid: 'clls_1'
      )
    end

    it 'creates the row when none exists' do
      expect { find_or_create }.to change { described_class.count }.by(1)

      expect(find_or_create).to have_attributes(
        namespace_id: integration.namespace_id,
        anthropic_integration_id: integration.id,
        ai_governance_session_id: governance_session.id,
        session_xid: 'clls_1'
      )
    end

    it 'returns the existing row' do
      existing = create(:ai_compliance_anthropic_session, namespace: integration.namespace,
        anthropic_integration: integration, ai_governance_session: governance_session, session_xid: 'clls_1')

      expect(find_or_create).to eq(existing)
    end

    context 'when a concurrent walk inserts the row first' do
      let!(:existing) do
        create(:ai_compliance_anthropic_session, namespace: integration.namespace,
          anthropic_integration: integration, ai_governance_session: governance_session, session_xid: 'clls_1')
      end

      before do
        allow(described_class).to receive(:find_by).and_return(nil, existing)
      end

      it 'reads the winning row back after a validation conflict' do
        expect(find_or_create).to eq(existing)
      end

      it 'reads the winning row back after a unique violation' do
        allow(described_class).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

        expect(find_or_create).to eq(existing)
      end
    end

    it 'raises other validation errors' do
      expect do
        described_class.find_or_create_for!(
          anthropic_integration: integration, ai_governance_session: governance_session, session_xid: nil
        )
      end.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe '#start_walk!', :freeze_time do
    it 'records when the walk started' do
      session = create(:ai_compliance_anthropic_session)

      expect { session.start_walk! }.to change { session.reload.walk_started_at }.from(nil).to(Time.current)
    end
  end

  describe '#commit_walk!' do
    let(:session) { create(:ai_compliance_anthropic_session, message_watermark: 'clsm_1', walk_started_at: 1.hour.ago) }

    it 'stores the watermark and clears walk_started_at' do
      session.commit_walk!('clsm_2')

      expect(session.reload).to have_attributes(message_watermark: 'clsm_2', walk_started_at: nil)
    end

    it 'keeps the stored watermark when given none' do
      session.commit_walk!(nil)

      expect(session.reload).to have_attributes(message_watermark: 'clsm_1', walk_started_at: nil)
    end

    it 'moves updated_at even when nothing else changes' do
      fresh = create(:ai_compliance_anthropic_session)

      travel_to(1.minute.from_now) do
        expect { fresh.commit_walk!(nil) }
          .to change { fresh.reload.updated_at }.to(be_within(1.second).of(Time.current))
      end
    end

    context 'with the start of the walk that commits' do
      it 'commits when that walk is still the latest', :aggregate_failures do
        expect(session.commit_walk!('clsm_2', walk_started_at: session.reload.walk_started_at)).to be(true)
        expect(session.reload).to have_attributes(message_watermark: 'clsm_2', walk_started_at: nil)
      end

      it 'moves updated_at even without a watermark' do
        walk_started_at = session.reload.walk_started_at

        travel_to(1.minute.from_now) do
          expect { session.commit_walk!(nil, walk_started_at: walk_started_at) }
            .to change { session.reload.updated_at }.to(be_within(1.second).of(Time.current))
        end
      end

      it 'accepts the start as an ISO 8601 string' do
        expect(session.commit_walk!('clsm_2', walk_started_at: session.reload.walk_started_at.iso8601(6))).to be(true)
      end

      it 'does not commit an older walk while a newer one is running', :aggregate_failures do
        older_walk_started_at = session.reload.walk_started_at
        session.start_walk!

        expect(session.commit_walk!('clsm_2', walk_started_at: older_walk_started_at)).to be(false)
        expect(session.reload).to have_attributes(message_watermark: 'clsm_1', walk_started_at: be_present)
      end

      it 'does not move the watermark backwards when the older walk commits last', :aggregate_failures do
        older_walk_started_at = session.reload.walk_started_at
        session.start_walk!
        session.commit_walk!('clsm_3', walk_started_at: session.reload.walk_started_at)

        expect(session.commit_walk!('clsm_2', walk_started_at: older_walk_started_at)).to be(false)
        expect(session.reload).to have_attributes(message_watermark: 'clsm_3', walk_started_at: nil)
      end
    end
  end

  describe 'database constraints' do
    it 'rejects a second row for the same governance session' do
      existing = create(:ai_compliance_anthropic_session)
      duplicate = build(:ai_compliance_anthropic_session,
        namespace: existing.namespace,
        anthropic_integration: existing.anthropic_integration,
        ai_governance_session: existing.ai_governance_session)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'is deleted with its governance session' do
      session = create(:ai_compliance_anthropic_session)

      expect { session.ai_governance_session.delete }.to change { described_class.count }.by(-1)
    end

    it 'is deleted with its integration' do
      session = create(:ai_compliance_anthropic_session)

      expect { session.anthropic_integration.delete }.to change { described_class.count }.by(-1)
    end
  end
end
