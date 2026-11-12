# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Ci::Pipelines, feature_category: :continuous_integration do
  let(:user)    { create(:user) }
  let(:project) { create(:project, :repository, creator: user) }

  let!(:pipeline) do
    create(:ci_pipeline, project: project, sha: project.commit.id, ref: project.default_branch, user: user)
  end

  before do
    project.add_maintainer(user)
  end

  describe 'GET /projects/:id/pipelines' do
    context 'when authenticated as a security policy bot with a CI job token' do
      let(:bot) { create(:user, user_type: :security_policy_bot) }
      let(:job) { create(:ci_build, :running, project: project, user: bot) }

      before do
        project.add_guest(bot)
      end

      it 'returns the project pipelines', :aggregate_failures do
        get api("/projects/#{project.id}/pipelines"), params: { job_token: job.token, sha: pipeline.sha }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response.pluck('id')).to include(pipeline.id)
      end
    end
  end

  describe 'DELETE /projects/:id/pipelines/:pipeline_id' do
    context 'authorized user' do
      let(:owner) { project.first_owner }

      context 'when audit events is enabled' do
        before do
          stub_licensed_features(extended_audit_events: true, admin_audit_log: true)
        end

        it 'logs an audit event' do
          expect { delete api("/projects/#{project.id}/pipelines/#{pipeline.id}", owner) }.to change { AuditEventReader.count }.by(1)
        end
      end
    end
  end
end
