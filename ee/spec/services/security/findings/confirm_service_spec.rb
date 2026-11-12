# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::Findings::ConfirmService, feature_category: :vulnerability_management do
  let_it_be(:user) { create(:user) }

  let!(:finding) { create(:security_finding) }
  let(:comment) { nil }
  let(:vulnerability) do
    create(:vulnerability, :detected,
      project: finding.project, findings: [create(:vulnerabilities_finding, uuid: finding.uuid)])
  end

  let(:created) { false }
  let(:find_or_create_response) do
    ServiceResponse.success(payload: { vulnerability: vulnerability, created: created })
  end

  let(:find_or_create_service) do
    instance_double(::Vulnerabilities::FindOrCreateFromSecurityFindingService, execute: find_or_create_response)
  end

  let(:service) { described_class.new(user: user, security_finding: finding, comment: comment) }

  subject(:confirm_finding) { service.execute }

  before do
    stub_licensed_features(security_dashboard: true)
    allow(::Vulnerabilities::FindOrCreateFromSecurityFindingService)
      .to receive(:new).and_return(find_or_create_service)
  end

  describe 'pre-existing state policy re-evaluation' do
    before do
      finding.project.add_maintainer(user)
    end

    it_behaves_like 'syncs pre-existing state approval policy rules on triage' do
      let(:triaged_project) { finding.project }
      let(:perform_triage) { confirm_finding }
    end
  end

  describe '#execute' do
    context 'when the user is authorized' do
      before do
        finding.project.add_maintainer(user)
      end

      it 'defers the transition of an existing vulnerability to the caller' do
        expect(::Vulnerabilities::FindOrCreateFromSecurityFindingService).to receive(:new).with(
          project: finding.project,
          current_user: user,
          params: { security_finding_uuid: finding.uuid, comment: comment },
          state: :confirmed,
          present_on_default_branch: false,
          defer_existing_state_update: true
        ).and_return(find_or_create_service)

        confirm_finding
      end

      it 'confirms an existing vulnerability through the dedicated service' do
        freeze_time do
          confirm_finding

          expect(vulnerability.reload).to be_confirmed
          expect(vulnerability.confirmed_by).to eq(user)
          expect(vulnerability.confirmed_at).to eq(Time.current)
        end
      end

      context 'when the vulnerability was newly created' do
        let(:created) { true }

        it 'does not run the dedicated service and triggers the webhook' do
          expect(::Vulnerabilities::ConfirmService).not_to receive(:new)
          expect(vulnerability).to receive(:trigger_webhook_event)

          confirm_finding
        end
      end

      it 'returns the security finding with a success response' do
        response = confirm_finding

        expect(response).to be_success
        expect(response.payload[:security_finding]).to eq(finding)
      end

      it 'schedules the sync findings to approval rules worker' do
        expect(Security::ScanResultPolicies::SyncFindingsToApprovalRulesWorker)
          .to receive(:perform_in).with(1.minute, finding.pipeline.id)

        confirm_finding
      end

      context 'when transitioning the existing vulnerability fails' do
        before do
          allow(vulnerability).to receive(:update) do
            vulnerability.errors.add(:base, 'update failed')
            false
          end
        end

        it 'returns an error and does not schedule the sync worker' do
          expect(Security::ScanResultPolicies::SyncFindingsToApprovalRulesWorker).not_to receive(:perform_in)

          result = confirm_finding

          expect(result).not_to be_success
          expect(result.reason).to be(:unprocessable_entity)
          expect(result.message).to eq('failed to confirm security finding: update failed')
        end
      end

      context 'when the newly created vulnerability was not saved' do
        let(:created) { false }
        let(:vulnerability) do
          build(:vulnerability, project: finding.project).tap do |vulnerability|
            vulnerability.errors.add(:base, 'finding is not found or is already attached to a vulnerability')
          end
        end

        it 'returns an error without triggering side effects' do
          expect(::Vulnerabilities::ConfirmService).not_to receive(:new)
          expect(vulnerability).not_to receive(:trigger_webhook_event)
          expect(Security::ScanResultPolicies::SyncFindingsToApprovalRulesWorker).not_to receive(:perform_in)

          result = confirm_finding

          expect(result).not_to be_success
          expect(result.reason).to be(:unprocessable_entity)
          expect(result.message).to eq(
            'failed to confirm security finding: finding is not found or is already attached to a vulnerability'
          )
        end
      end

      context 'when creating the vulnerability fails' do
        let(:find_or_create_response) { ServiceResponse.error(message: 'something went wrong') }

        it 'returns an error and does not schedule the sync worker' do
          expect(Security::ScanResultPolicies::SyncFindingsToApprovalRulesWorker).not_to receive(:perform_in)
          expect(::Vulnerabilities::ConfirmService).not_to receive(:new)

          result = confirm_finding

          expect(result).not_to be_success
          expect(result.reason).to be(:unprocessable_entity)
          expect(result.message).to eq('failed to confirm security finding: something went wrong')
        end
      end
    end

    context 'when the user cannot confirm_vulnerability' do
      before do
        finding.project.add_maintainer(user)

        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?).with(user, :confirm_vulnerability, finding.project).and_return(false)
      end

      it 'returns an access denied error' do
        result = confirm_finding

        expect(result).not_to be_success
        expect(result.reason).to be(:forbidden)
      end
    end

    context 'when the user is not authorized' do
      it 'raises an "access denied" error' do
        result = confirm_finding

        expect(result).not_to be_success
        expect(result.reason).to be(:forbidden)
        expect(result.message).to eq('Access denied')
      end
    end
  end
end
