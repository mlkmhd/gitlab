# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ProtectedBranches::CreateService, feature_category: :compliance_management do
  include ProjectForksHelper

  let(:source_project) { create(:project) }
  let(:target_project) { fork_project(source_project, user, repository: true) }
  let(:security_orchestration_policy_configuration) do
    create(:security_orchestration_policy_configuration, project: target_project)
  end

  let(:user) { source_project.first_owner }

  let(:params) do
    {
      name: "feature",
      merge_access_levels_attributes: [{ access_level: Gitlab::Access::MAINTAINER }],
      push_access_levels_attributes: [{ access_level: Gitlab::Access::MAINTAINER }]
    }
  end

  describe "#execute" do
    subject(:service) { described_class.new(target_project, user, params) }

    before do
      target_project.add_member(user, :developer)
    end

    context "code_owner_approval_required" do
      context "when unavailable" do
        before do
          stub_licensed_features(code_owner_approval_required: false)

          params[:code_owner_approval_required] = true
        end

        it "ignores incoming params and sets code_owner_approval_required to false", :aggregate_failures do
          expect { service.execute }.to change { ProtectedBranch.count }.by(1)
          expect(ProtectedBranch.last.code_owner_approval_required).to be_falsy
        end
      end

      context "when available" do
        before do
          stub_licensed_features(code_owner_approval_required: true)
          params[:code_owner_approval_required] = code_owner_approval_required
        end

        context "when code_owner_approval_required param is true" do
          let(:code_owner_approval_required) { true }

          it "sets code_owner_approval_required to true", :aggregate_failures do
            expect { service.execute }.to change { ProtectedBranch.count }.by(1)
            expect(ProtectedBranch.last.code_owner_approval_required).to be_truthy
          end
        end

        context "when code_owner_approval_required param is false" do
          let(:code_owner_approval_required) { false }

          it "sets code_owner_approval_required to false", :aggregate_failures do
            expect { service.execute }.to change { ProtectedBranch.count }.by(1)
            expect(ProtectedBranch.last.code_owner_approval_required).to be_falsy
          end
        end
      end
    end

    context "when there are open merge requests" do
      let!(:merge_request) do
        create(:merge_request,
          source_project: source_project,
          target_project: target_project,
          discussion_locked: false
        )
      end

      it "calls MergeRequest::SyncCodeOwnerApprovalRules to update open MRs", :aggregate_failures do
        expect(::MergeRequests::SyncCodeOwnerApprovalRules).to receive(:new).with(merge_request).and_call_original
        expect { service.execute }.to change { ProtectedBranch.count }.by(1)
      end

      context "when the branch is a wildcard" do
        %w[*ture *eatur* feat*].each do |wildcard|
          context "with wildcard: #{wildcard}" do
            before do
              params[:name] = wildcard
            end

            it "calls MergeRequest::SyncCodeOwnerApprovalRules to update open MRs", :aggregate_failures do
              expect(::MergeRequests::SyncCodeOwnerApprovalRules).to receive(:new).with(merge_request).and_call_original
              expect { service.execute }.to change { ProtectedBranch.count }.by(1)
            end
          end
        end
      end
    end

    context "when there are closed merge requests targeting the branch" do
      let!(:closed_merge_request) do
        create(:merge_request, :closed,
          source_project: source_project,
          target_project: target_project,
          source_branch: 'closed-merge-request-source'
        )
      end

      it "does not sync their code owner approval rules" do
        expect(::MergeRequests::SyncCodeOwnerApprovalRules).not_to receive(:new)

        expect { service.execute }.to change { ProtectedBranch.count }.by(1)
      end

      context "when the feature flag is disabled" do
        before do
          stub_feature_flags(protected_branch_code_owner_sync_open_only: false)
        end

        it "syncs their code owner approval rules" do
          expect(::MergeRequests::SyncCodeOwnerApprovalRules).to receive(:new)
            .with(closed_merge_request).and_call_original

          expect { service.execute }.to change { ProtectedBranch.count }.by(1)
        end
      end
    end

    it 'adds a security audit event entry' do
      expect { service.execute }.to change { AuditEventReader.count }.by(1)
    end

    context 'when the protected branch write rate limit is exceeded' do
      before do
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
          .with(:protected_branch_write, scope: { user: user, namespace: target_project.root_ancestor })
          .and_return(true)
      end

      it 'raises through the EE override' do
        expect { service.execute }.to raise_error(RateLimitedService::RateLimitedError)
      end

      it 'forwards skip_rate_limit through the EE override', :aggregate_failures do
        expect { service.execute(skip_rate_limit: true) }
          .to change { ProtectedBranch.count }.by(1)
          .and change { AuditEventReader.count }.by(1)
      end
    end

    context 'with invalid params' do
      let(:params) { nil }

      it "doesn't add a security audit event entry" do
        expect { service.execute }.not_to change { AuditEventReader.count }
      end
    end
  end

  context 'when entity group' do
    let_it_be_with_reload(:user) { create(:user) }
    let_it_be_with_reload(:entity) { create(:group, owners: user) }

    let(:service) { described_class.new(entity, user, params) }

    it 'return early in `sync_code_owner_approval_rules`' do
      expect(service).to receive(:sync_code_owner_approval_rules)
      expect(entity).not_to receive(:merge_requests)

      service.execute
    end
  end
end
