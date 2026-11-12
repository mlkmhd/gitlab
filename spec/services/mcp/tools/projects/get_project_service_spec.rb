# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Projects::GetProjectService, feature_category: :mcp_server do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public) }

  let(:service) { described_class.new(name: 'get_project') }

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

    it 'locks the description' do
      expect(described_class.version_metadata('0.1.0')[:description]).to eq(
        'Get metadata for a single GitLab project: numeric ID, full path, default ' \
          'branch, visibility, and web URL. Identify the project with exactly one of url or ' \
          'project_id. Use search with scope projects to find a project you cannot name yet. ' \
          'Pass include: ["work_item_types"] to also return the project work item types and ' \
          'their enabled widgets, for use before save_work_item.'
      )
    end
  end

  describe 'input schema' do
    it 'locks the full input schema for version 0.1.0' do
      expect(described_class.version_metadata('0.1.0')[:input_schema]).to eq({
        type: 'object',
        required: [],
        properties: {
          url: {
            type: 'string',
            description: 'GitLab URL of the project.'
          },
          project_id: {
            type: 'string',
            description: 'Project ID or full path. Provide exactly one of url or project_id.'
          },
          include: {
            type: 'array',
            description: 'Facet to include alongside the project, one per call: work_item_types.',
            items: {
              type: 'string',
              enum: ['work_item_types']
            },
            maxItems: 1
          }
        }
      })
    end

    it 'rejects unknown arguments' do
      expect(service.input_schema[:additionalProperties]).to be(false)
    end
  end

  describe '#execute' do
    let(:request) { Grape::Request.new(Rack::MockRequest.env_for('/api/v4/mcp')) }
    let(:params) { { arguments: { project_id: project.id.to_s } } }

    it 'returns the project metadata', :aggregate_failures do
      result = service.execute(request: request, params: params)

      expect(result[:isError]).to be(false)
      expect(result[:structuredContent][:path_with_namespace]).to eq(project.full_path)
      expect(result[:structuredContent][:default_branch]).to eq(project.default_branch)
    end

    context 'with the work_item_types facet' do
      let(:params) { { arguments: { project_id: project.id.to_s, include: ['work_item_types'] } } }

      it 'returns the work item types alongside the project' do
        result = service.execute(request: request, params: params)

        expect(result[:structuredContent][:work_item_types]).to be_present
      end
    end

    it 'instantiates the tool with the resolved version and arguments' do
      expect(Mcp::Tools::Projects::GetProjectTool).to receive(:new).with(
        current_user: user,
        params: params[:arguments],
        version: '0.1.0',
        access_token: nil,
        request: request
      ).and_call_original

      service.execute(request: request, params: params)
    end

    context 'when current_user is not set' do
      before do
        service.set_cred(current_user: nil)
      end

      it 'returns an error response', :aggregate_failures do
        result = service.execute(request: request, params: params)

        expect(result[:isError]).to be(true)
        expect(result[:content].first[:text]).to include('current_user is not set')
      end
    end
  end
end
