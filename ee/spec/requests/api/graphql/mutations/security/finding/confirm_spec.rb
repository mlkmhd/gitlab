# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Confirming a security finding', feature_category: :vulnerability_management do
  include GraphqlHelpers

  let_it_be_with_reload(:project) { create(:project) }
  let_it_be_with_reload(:pipeline) { create(:ci_pipeline, project: project) }
  let_it_be_with_reload(:build) { create(:ci_build, :success, name: 'dast', pipeline: pipeline) }
  let_it_be_with_reload(:artifact) { create(:ee_ci_job_artifact, :dast, job: build) }
  let_it_be_with_reload(:report) { create(:ci_reports_security_report, pipeline: pipeline, type: :dast) }
  let_it_be_with_reload(:scan) { create(:security_scan, :latest_successful, scan_type: :dast, build: artifact.job) }
  let_it_be(:security_findings) { insert_security_findings }
  let_it_be(:security_finding) { security_findings.first }
  let_it_be(:finding_uuid) { security_finding.uuid }
  let_it_be(:current_user) { create(:user) }

  let(:comment) { 'Confirmed via the pipeline security tab' }
  let(:mutation_input) { { project_path: project.full_path, uuid: finding_uuid.to_s, comment: comment } }

  let(:mutation) do
    graphql_mutation(:security_finding_confirm, mutation_input) do
      <<~QL
        clientMutationId
        errors
        securityFinding {
          uuid
        }
      QL
    end
  end

  let(:mutation_response) { graphql_mutation_response(:security_finding_confirm) }

  subject(:run_mutation) { post_graphql_mutation(mutation, current_user: current_user) }

  def confirmed_vulnerability
    Vulnerabilities::Finding.by_uuid(finding_uuid).first&.vulnerability
  end

  context 'when the user has access to vulnerability management' do
    before do
      stub_licensed_features(security_dashboard: true)
    end

    context 'when the user does not have access to the project' do
      it_behaves_like 'a mutation that returns a top-level access error'
    end

    context 'when no uuid is provided' do
      let(:mutation_input) { { project_path: project.full_path } }

      it 'returns an error' do
        run_mutation

        expect(graphql_errors.first['message']).to include('Expected value to not be null')
      end
    end

    context 'when the user has access to the project' do
      before_all do
        project.add_maintainer(current_user)
      end

      context 'when the finding does not belong to the given project' do
        let_it_be(:other_project) { create(:project) }
        let(:mutation_input) { { project_path: other_project.full_path, uuid: finding_uuid.to_s } }

        before_all do
          other_project.add_maintainer(current_user)
        end

        it_behaves_like 'a mutation that returns a top-level access error'

        it 'does not confirm the finding' do
          run_mutation

          expect(confirmed_vulnerability).to be_nil
        end
      end

      context 'when there is no existing vulnerability' do
        it 'creates a confirmed vulnerability for the finding' do
          run_mutation

          expect(mutation_response['errors']).to be_empty
          expect(mutation_response['securityFinding']['uuid']).to eq(finding_uuid)
          expect(confirmed_vulnerability).to have_attributes(state: 'confirmed')
        end

        it 'records the comment on the state transition' do
          run_mutation

          expect(confirmed_vulnerability.state_transitions.last)
            .to have_attributes(comment: comment, to_state: 'confirmed')
        end
      end

      context 'when there is an existing vulnerability in the detected state' do
        let_it_be_with_reload(:vulnerability) { create(:vulnerability, :detected, project: project) }
        let_it_be(:vulnerability_finding) do
          create(:vulnerabilities_finding, vulnerability: vulnerability, uuid: finding_uuid)
        end

        it 'transitions the existing vulnerability to confirmed' do
          expect { run_mutation }.to change { vulnerability.reload.state }.from('detected').to('confirmed')
          expect(mutation_response['errors']).to be_empty
        end
      end

      context 'when the confirmation fails' do
        before do
          allow_next_instance_of(::Vulnerabilities::FindOrCreateFromSecurityFindingService) do |service|
            allow(service).to receive(:execute)
              .and_return(ServiceResponse.error(message: 'something went wrong'))
          end
        end

        it 'returns the error' do
          run_mutation

          expect(mutation_response['errors'])
            .to match_array(['failed to confirm security finding: something went wrong'])
        end
      end
    end
  end

  describe 'granular PAT authorization' do
    before_all do
      project.add_maintainer(current_user)
    end

    before do
      stub_licensed_features(security_dashboard: true)
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :confirm_vulnerability do
      let(:user) { current_user }
      let(:boundary_object) { project }
      let(:authz_mutation) { graphql_mutation(:security_finding_confirm, mutation_input, 'errors') }
      let(:request) { post_graphql_mutation(authz_mutation, token: { personal_access_token: pat }) }
    end
  end

  def insert_security_findings
    dast_content = File.read(artifact.file.path)
    Gitlab::Ci::Parsers::Security::Dast.parse!(dast_content, report)
    report.merge!(report)

    report.findings.map do |finding|
      create(
        :security_finding,
        :with_finding_data,
        solution: finding.solution,
        severity: finding.severity,
        uuid: finding.uuid,
        context_unaware_uuid: finding.context_unaware_uuid,
        scan: scan
      )
    end
  end
end
