# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Pipelines::SavePipelineService, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public, :repository) }

  let(:service) { described_class.new(name: 'save_pipeline') }
  let(:request) { Grape::Request.new(Rack::MockRequest.env_for('/api/v4/mcp')) }

  before_all do
    project.add_developer(user)
  end

  before do
    service.set_cred(current_user: user)
  end

  describe 'class configuration' do
    it 'registers version 0.1.0' do
      expect(described_class.available_versions).to include('0.1.0')
    end

    it 'is a write, destructive tool', :aggregate_failures do
      expect(service.annotations[:readOnlyHint]).to be(false)
      expect(service.annotations[:destructiveHint]).to be(true)
    end
  end

  describe '#input_schema' do
    it 'matches the expected contract' do
      expect(service.input_schema).to eq(
        {
          type: 'object',
          required: [],
          additionalProperties: false,
          properties: {
            url: {
              type: 'string',
              description: 'GitLab URL of the project. Used only when creating a pipeline.'
            },
            project_id: {
              type: 'string',
              description: 'ID or full path of the project. Used only when creating a pipeline.'
            },
            merge_request_iid: {
              type: 'integer',
              description: 'Internal ID of a merge request in the project to create a pipeline for. ' \
                'When set, creates a pipeline linked to the merge request.'
            },
            pipeline_id: {
              type: 'integer',
              description: 'ID of an existing pipeline to target. When set, requires action. ' \
                'Omit to create a new pipeline.'
            },
            action: {
              type: 'string',
              enum: %w[retry cancel update],
              description: 'Lifecycle action to perform on pipeline_id. Required when pipeline_id is set.'
            },
            ref: {
              type: 'string',
              description: 'Branch or tag name. Required to create a pipeline on a branch or tag ' \
                '(when pipeline_id and merge_request_iid are absent).'
            },
            name: {
              type: 'string',
              description: 'New pipeline name. Required for action: "update".'
            },
            variables: {
              type: 'array',
              description: 'Pipeline variables to create the pipeline with.',
              items: {
                type: 'object',
                properties: {
                  key: { type: 'string', description: 'Name of the variable.' },
                  value: { type: 'string', description: 'Value of the variable.' },
                  variable_type: {
                    type: 'string',
                    enum: %w[env_var file],
                    description: 'Type of the variable.'
                  }
                },
                required: %w[key value]
              }
            },
            inputs: {
              type: 'object',
              description: 'Pipeline input parameters as key-value pairs.'
            }
          }
        }
      )
    end
  end

  describe '#execute' do
    context 'when creating a pipeline' do
      let(:params) { { arguments: { project_id: project.full_path, ref: project.default_branch } } }

      before do
        stub_ci_pipeline_yaml_file(YAML.dump(test: { script: 'echo test' }))
      end

      it 'creates a pipeline and returns its reference', :aggregate_failures do
        expect { service.execute(request: request, params: params) }
          .to change { project.ci_pipelines.count }.by(1)

        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent]).to include(action: 'create', ref: project.default_branch)
      end

      context 'with variables and inputs' do
        let(:params) do
          {
            arguments: {
              project_id: project.full_path,
              ref: project.default_branch,
              variables: [{ key: 'DEPLOY_ENV', value: 'staging', variable_type: 'env_var' }],
              inputs: { job_name: 'my-input-job' }
            }
          }
        end

        before do
          stub_ci_pipeline_yaml_file(<<~YAML)
            spec:
              inputs:
                job_name:
            ---
            "$[[ inputs.job_name ]]":
              script: echo test
          YAML
        end

        it 'creates the pipeline with the variables and inputs applied', :aggregate_failures do
          expect { service.execute(request: request, params: params) }
            .to change { project.ci_pipelines.count }.by(1)

          created_pipeline = project.ci_pipelines.last

          expect(created_pipeline.variables.map(&:key)).to include('DEPLOY_ENV')
          expect(created_pipeline.builds.map(&:name)).to contain_exactly('my-input-job')
        end
      end
    end

    context 'when creating a pipeline for a merge request' do
      let_it_be(:merge_request) do
        create(:merge_request, :with_head_pipeline, source_project: project, target_project: project)
      end

      let(:token) { create(:personal_access_token, user: user, scopes: [:mcp]) }
      let(:params) do
        {
          arguments: {
            project_id: project.full_path,
            merge_request_iid: merge_request.iid
          }
        }
      end

      before do
        stub_ci_pipeline_yaml_file(YAML.dump(test: { script: 'echo test', only: ['merge_requests'] }))
        service.set_cred(current_user: user, access_token: token)
      end

      it 'creates a pipeline for the merge request and returns its reference', :aggregate_failures do
        result = nil
        expect { result = service.execute(request: request, params: params) }
          .to change { merge_request.pipelines_for_merge_request.count }.by(1)

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent]).to include(
          action: 'create',
          ref: merge_request.ref_path
        )
      end

      context 'when identified by url' do
        let(:params) do
          {
            arguments: {
              url: project.web_url,
              merge_request_iid: merge_request.iid
            }
          }
        end

        it 'creates the pipeline', :aggregate_failures do
          result = service.execute(request: request, params: params)

          expect(result[:isError]).to be(false)
          expect(result[:structuredContent]).to include(action: 'create')
        end
      end

      context 'with a granular token' do
        let(:token) do
          create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(project), permissions: token_permissions)
        end

        context 'without the required permission' do
          let(:token_permissions) { :read_merge_request }

          it 'does not create the pipeline', :aggregate_failures do
            result = service.execute(request: request, params: params)

            expect(result[:reason]).to eq(:unauthorized)
            expect(result[:content].first[:text]).to include('Access denied')
          end
        end

        context 'with the required permission' do
          let(:token_permissions) { :update_merge_request }

          it 'creates the pipeline', :aggregate_failures do
            result = service.execute(request: request, params: params)

            expect(result[:isError]).to be(false)
            expect(result[:structuredContent]).to include(action: 'create')
          end
        end
      end

      context 'without a token' do
        let(:token) { nil }

        it 'returns unauthorized', :aggregate_failures do
          result = service.execute(request: request, params: params)

          expect(result[:reason]).to eq(:unauthorized)
        end
      end

      context 'when the merge request does not exist' do
        let(:params) do
          {
            arguments: {
              project_id: project.full_path,
              merge_request_iid: non_existing_record_iid
            }
          }
        end

        it 'returns a not found error', :aggregate_failures do
          result = service.execute(request: request, params: params)

          expect(result[:isError]).to be(true)
          expect(result[:content].first[:text]).to include('Merge request not found or inaccessible.')
          expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:not_found)
        end
      end

      context 'when the project does not exist' do
        let(:params) do
          {
            arguments: {
              project_id: 'non-existing/project',
              merge_request_iid: merge_request.iid
            }
          }
        end

        it 'returns a not found error', :aggregate_failures do
          result = service.execute(request: request, params: params)

          expect(result[:isError]).to be(true)
          expect(result[:content].first[:text]).to include('not found or inaccessible')
          expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:not_found)
        end
      end

      context 'when neither url nor project_id is provided' do
        let(:params) do
          {
            arguments: {
              merge_request_iid: merge_request.iid
            }
          }
        end

        it 'returns a validation error', :aggregate_failures do
          result = service.execute(request: request, params: params)

          expect(result[:isError]).to be(true)
          expect(result[:reason]).to eq(:bad_request)
          expect(result[:content].first[:text]).to include('Provide exactly one of: url or project_id')
        end
      end

      context 'when the user does not have permission to create a pipeline' do
        let_it_be(:reporter) { create(:user) }
        let(:token) { create(:personal_access_token, user: reporter, scopes: [:mcp]) }

        before_all do
          project.add_reporter(reporter)
        end

        before do
          service.set_cred(current_user: reporter, access_token: token)
        end

        it 'returns an unauthorized error', :aggregate_failures do
          result = service.execute(request: request, params: params)

          expect(result[:isError]).to be(true)
          expect(result[:reason]).to eq(:unauthorized)
          expect(result[:content].first[:text]).to match(/permission/i)
        end
      end

      context 'when the merge request has no commits' do
        before do
          allow_next_found_instance_of(MergeRequest) do |mr|
            allow(mr).to receive(:has_no_commits?).and_return(true)
          end
        end

        it 'returns a bad request error', :aggregate_failures do
          result = service.execute(request: request, params: params)

          expect(result[:isError]).to be(true)
          expect(result[:reason]).to eq(:bad_request)
          expect(result[:content].first[:text]).to include(
            'Cannot create a pipeline for this merge request: no commits to build.'
          )
        end
      end

      context 'when pipeline creation fails with validation errors' do
        let(:unpersisted_pipeline) do
          build(:ci_pipeline, project: project).tap do |pipeline|
            pipeline.errors.add(:base, 'Pipeline configuration is invalid')
          end
        end

        before do
          allow_next_instance_of(::MergeRequests::CreatePipelineService) do |create_service|
            allow(create_service).to receive(:execute).and_return(
              ServiceResponse.success(payload: unpersisted_pipeline)
            )
          end
        end

        it 'returns a bad request error with the failure reason', :aggregate_failures do
          result = service.execute(request: request, params: params)

          expect(result[:isError]).to be(true)
          expect(result[:reason]).to eq(:bad_request)
          expect(result[:content].first[:text]).to include('Pipeline configuration is invalid')
        end
      end

      context 'when pipeline creation returns an error without a pipeline' do
        before do
          allow_next_instance_of(::MergeRequests::CreatePipelineService) do |create_service|
            allow(create_service).to receive(:execute).and_return(
              ServiceResponse.error(message: 'Pipeline creation failed', payload: nil)
            )
          end
        end

        it 'returns a bad request error with the failure reason', :aggregate_failures do
          result = service.execute(request: request, params: params)

          expect(result[:isError]).to be(true)
          expect(result[:reason]).to eq(:bad_request)
          expect(result[:content].first[:text]).to include('Pipeline creation failed')
        end
      end

      context 'when arguments are combined invalidly' do
        it 'rejects combining merge_request_iid with pipeline_id' do
          result = service.execute(
            request: request,
            params: { arguments: { project_id: project.full_path, merge_request_iid: 1, pipeline_id: 2 } }
          )

          expect(result[:isError]).to be(true)
          expect(result[:content].first[:text]).to include('Cannot combine merge_request_iid with pipeline_id')
        end

        it 'rejects combining merge_request_iid with ref' do
          result = service.execute(
            request: request,
            params: { arguments: { project_id: project.full_path, merge_request_iid: 1, ref: 'master' } }
          )

          expect(result[:isError]).to be(true)
          expect(result[:content].first[:text]).to include('Cannot combine merge_request_iid with ref')
        end

        it 'rejects combining merge_request_iid with action' do
          result = service.execute(
            request: request,
            params: { arguments: { project_id: project.full_path, merge_request_iid: 1, action: 'update' } }
          )

          expect(result[:isError]).to be(true)
          expect(result[:content].first[:text]).to include('Cannot combine merge_request_iid with action')
        end

        it 'rejects combining merge_request_iid with name' do
          result = service.execute(
            request: request,
            params: { arguments: { project_id: project.full_path, merge_request_iid: 1, name: 'custom' } }
          )

          expect(result[:isError]).to be(true)
          expect(result[:content].first[:text]).to include('Cannot combine merge_request_iid with name')
        end

        it 'rejects combining merge_request_iid with variables' do
          result = service.execute(
            request: request,
            params: {
              arguments: {
                project_id: project.full_path,
                merge_request_iid: 1,
                variables: [{ key: 'K', value: 'V' }]
              }
            }
          )

          expect(result[:isError]).to be(true)
          expect(result[:content].first[:text]).to include('Cannot combine merge_request_iid with variables')
        end

        it 'rejects combining merge_request_iid with inputs' do
          result = service.execute(
            request: request,
            params: {
              arguments: {
                project_id: project.full_path,
                merge_request_iid: 1,
                inputs: { key: 'value' }
              }
            }
          )

          expect(result[:isError]).to be(true)
          expect(result[:content].first[:text]).to include('Cannot combine merge_request_iid with inputs')
        end
      end
    end

    context 'when retrying a pipeline' do
      let_it_be(:failed_pipeline) { create(:ci_pipeline, project: project, ref: 'master', status: :failed) }
      let_it_be(:failed_build) { create(:ci_build, :failed, :retryable, pipeline: failed_pipeline) }

      let(:params) { { arguments: { pipeline_id: failed_pipeline.id, action: 'retry' } } }

      it 'retries the pipeline', :aggregate_failures do
        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent]).to include(action: 'retry', id: failed_pipeline.id)
      end
    end

    context 'when renaming a pipeline' do
      let_it_be_with_reload(:named_pipeline) { create(:ci_pipeline, project: project, ref: 'master') }

      let(:params) { { arguments: { pipeline_id: named_pipeline.id, action: 'update', name: 'Nightly build' } } }
      let(:token) { create(:personal_access_token, user: user, scopes: [:mcp]) }

      before do
        service.set_cred(current_user: user, access_token: token)
      end

      context 'without a token' do
        let(:token) { nil }

        it 'does not rename the pipeline', :aggregate_failures do
          result = service.execute(request: request, params: params)

          expect(result[:reason]).to eq(:unauthorized)
          expect(named_pipeline.reload.name).to be_nil
        end
      end

      context 'with a granular token' do
        let(:token) do
          create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(project), permissions: token_permissions)
        end

        context 'without the required permission' do
          let(:token_permissions) { :read_pipeline }

          it 'does not rename the pipeline', :aggregate_failures do
            result = service.execute(request: request, params: params)

            expect(result[:reason]).to eq(:unauthorized)
            expect(result[:content].first[:text]).to include('Access denied')
            expect(named_pipeline.reload.name).not_to eq('Nightly build')
          end
        end

        context 'with the required permission' do
          let(:token_permissions) { :update_pipeline }

          it 'renames the pipeline', :aggregate_failures do
            result = service.execute(request: request, params: params)

            expect(result[:isError]).to be(false)
            expect(named_pipeline.reload.name).to eq('Nightly build')
          end
        end
      end

      it 'renames the pipeline', :aggregate_failures do
        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(false)
        expect(result[:structuredContent]).to include(action: 'update', id: named_pipeline.id, name: 'Nightly build')
        expect(named_pipeline.reload.name).to eq('Nightly build')
      end

      it 'requires name' do
        result = service.execute(
          request: request, params: { arguments: { pipeline_id: named_pipeline.id, action: 'update' } }
        )

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('Provide name to rename the pipeline')
      end

      it 'surfaces the metadata validation errors when the service rejects the name', :aggregate_failures do
        result = service.execute(
          request: request,
          params: { arguments: { pipeline_id: named_pipeline.id, action: 'update', name: 'a' * 256 } }
        )

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('too long')
        expect(named_pipeline.reload.name).to be_nil
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:bad_request)
      end

      it 'requires pipeline_id' do
        result = service.execute(request: request, params: { arguments: { action: 'update', name: 'x' } })

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('Provide pipeline_id to rename a pipeline')
      end

      it 'returns the uniform not-found error for an unknown pipeline' do
        result = service.execute(
          request: request,
          params: { arguments: { pipeline_id: non_existing_record_id, action: 'update', name: 'x' } }
        )

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('Pipeline not found or inaccessible.')
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:not_found)
      end

      it 'returns the uniform not-found error for a pipeline the user cannot read', :aggregate_failures do
        private_pipeline = create(:ci_pipeline, project: create(:project, :private))

        result = service.execute(
          request: request,
          params: { arguments: { pipeline_id: private_pipeline.id, action: 'update', name: 'x' } }
        )

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('Pipeline not found or inaccessible.')
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:unauthorized)
      end

      it 'returns the uniform not-found error for a user who cannot rename', :aggregate_failures do
        non_member_token = create(:personal_access_token, scopes: [:mcp])
        service.set_cred(current_user: non_member_token.user, access_token: non_member_token)

        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('Pipeline not found or inaccessible.')
        expect(named_pipeline.reload.name).to be_nil
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:unauthorized)
      end
    end

    context 'when a retry or cancel cannot reach the pipeline' do
      let_it_be(:private_pipeline) { create(:ci_pipeline, project: create(:project, :private), status: :failed) }
      let_it_be(:public_pipeline) { create(:ci_pipeline, project: project, status: :failed) }
      let_it_be(:reporter) { create(:user, reporter_of: project) }

      let(:access_error) { ::Gitlab::Graphql::Authorize::AuthorizeResource::RESOURCE_ACCESS_ERROR }

      where(action: %w[retry cancel])

      with_them do
        it 'answers a missing pipeline with the access error as not_found', :aggregate_failures do
          expect(::Gitlab::ErrorTracking).not_to receive(:track_exception)

          result = service.execute(request: request,
            params: { arguments: { pipeline_id: non_existing_record_id, action: action } })

          expect(result[:content].first[:text]).to eq(access_error)
          expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:not_found)
        end

        it 'reports a pipeline in a project the user cannot see as unauthorized', :aggregate_failures do
          result = service.execute(request: request,
            params: { arguments: { pipeline_id: private_pipeline.id, action: action } })

          expect(result[:content].first[:text]).to eq(access_error)
          expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:unauthorized)
        end

        it 'reports a readable pipeline the user cannot act on as unauthorized', :aggregate_failures do
          service.set_cred(current_user: reporter)

          result = service.execute(request: request,
            params: { arguments: { pipeline_id: public_pipeline.id, action: action } })

          expect(result[:content].first[:text]).to eq(access_error)
          expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:unauthorized)
        end
      end
    end

    context 'when a reporter creates a pipeline' do
      let_it_be(:reporter) { create(:user, reporter_of: project) }

      it 'reports unauthorized with the access error', :aggregate_failures do
        service.set_cred(current_user: reporter)

        result = service.execute(request: request,
          params: { arguments: { project_id: project.full_path, ref: project.default_branch } })

        access_error = ::Gitlab::Graphql::Authorize::AuthorizeResource::RESOURCE_ACCESS_ERROR
        expect(result[:content].first[:text]).to eq(access_error)
        expect(Mcp::Tools::Base::Response.error_reason(result)).to eq(:unauthorized)
      end
    end

    context 'with an invalid action' do
      let(:params) { { arguments: { pipeline_id: 1, action: 'delete' } } }

      it 'returns a validation error', :aggregate_failures do
        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include("Invalid action: 'delete'")
      end
    end

    context 'when current_user is not set' do
      let(:params) { { arguments: { project_id: project.full_path, ref: 'master' } } }

      before do
        service.set_cred(current_user: nil)
      end

      it 'returns an error response' do
        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('current_user is not set')
      end
    end
  end

  describe '#governed_containers' do
    let_it_be(:pipeline) { create(:ci_pipeline, project: project) }

    it 'governs a pipeline_id by the project that pipeline belongs to' do
      arguments = { pipeline_id: pipeline.id, action: 'retry' }.with_indifferent_access

      expect(service.governed_containers(arguments).containers).to eq([project])
    end

    it 'names the pipeline even when it resolves to nothing', :aggregate_failures do
      arguments = { pipeline_id: non_existing_record_id, action: 'retry' }.with_indifferent_access
      resolved = service.governed_containers(arguments)

      expect(resolved.named).to eq(1)
      expect(resolved.containers).to be_empty
    end

    it 'still governs the create form by its project' do
      arguments = { project_id: project.full_path, ref: 'master' }.with_indifferent_access

      expect(service.governed_containers(arguments).containers).to eq([project])
    end
  end
end
