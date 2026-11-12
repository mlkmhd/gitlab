# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Security::Finding::Resolve, feature_category: :vulnerability_management do
  include GraphqlHelpers

  let(:mutation) { described_class.new(object: nil, context: query_context, field: nil) }

  specify { expect(described_class).to require_graphql_authorizations(:resolve_vulnerability) }

  describe '#resolve' do
    let_it_be(:security_finding) { create(:security_finding) }
    let_it_be(:current_user) { create(:user) }
    let_it_be(:finding_uuid) { security_finding.uuid }

    let(:project_path) { security_finding.project.full_path }

    let(:comment) { 'Resolution comment' }
    let(:mutated_finding) { resolve_result[:security_finding] }

    subject(:resolve_result) { mutation.resolve(project_path: project_path, uuid: finding_uuid, comment: comment) }

    context 'when the user has permission to resolve the security finding' do
      before do
        stub_licensed_features(security_dashboard: true)
      end

      context 'when user does not have access to the project' do
        it 'raises an error' do
          expect { resolve_result }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
        end
      end

      context 'when the project does not exist' do
        let(:project_path) { 'non-existent/project' }

        it 'raises an error' do
          expect { resolve_result }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
        end
      end

      context 'when no uuid is provided' do
        subject(:resolve_result) { mutation.resolve(project_path: project_path, comment: comment) }

        it 'raises an error' do
          expect { resolve_result }.to raise_error(ArgumentError)
        end
      end

      context 'when the user has access to the project' do
        before do
          security_finding.project.add_maintainer(current_user)
        end

        context 'when the finding does not belong to the given project' do
          let_it_be(:other_project) { create(:project, maintainers: current_user) }
          let(:project_path) { other_project.full_path }

          it 'raises an error' do
            expect { resolve_result }.to raise_error(Gitlab::Graphql::Errors::ResourceNotAvailable)
          end
        end

        context 'when the resolution is successful' do
          before do
            allow_next_instance_of(::Security::Findings::ResolveService) do |service|
              allow(service).to receive(:execute)
                .and_return(ServiceResponse.success(payload: { security_finding: security_finding }))
            end
          end

          it 'returns the resolved security finding' do
            expect(mutated_finding).to eq(security_finding)
            expect(resolve_result[:errors]).to be_empty
          end
        end

        context 'when the resolution fails' do
          let_it_be(:error_result) do
            ServiceResponse.error(message: 'error', reason: :unprocessable_entity)
          end

          before do
            allow_next_instance_of(::Security::Findings::ResolveService) do |service|
              allow(service).to receive(:execute).and_return(error_result)
            end
          end

          it 'returns the error and no security finding' do
            expect(mutated_finding).to be_nil
            expect(resolve_result[:errors]).to match_array(['error'])
          end
        end
      end
    end
  end
end
