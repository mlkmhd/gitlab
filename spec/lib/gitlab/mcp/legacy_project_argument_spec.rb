# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Mcp::LegacyProjectArgument, feature_category: :mcp_server do
  describe '.normalize!' do
    let(:declared) { { project: :project_id } }
    let(:properties) { { project_id: { type: 'string' } } }
    let(:tool) do
      instance_double(Mcp::Tools::Base::BaseService,
        container_arguments: declared, input_schema: { type: 'object', properties: properties })
    end

    def normalize(arguments)
      described_class.normalize!(tool, arguments)
    end

    context 'when the tool declares project_id' do
      it 'renames id to project_id' do
        arguments = { 'id' => 'flightjs/Flight' }

        expect(normalize(arguments)).to eq(['id->project_id'])
        expect(arguments).to eq('project_id' => 'flightjs/Flight')
      end

      it 'renames and coerces an integer id' do
        arguments = { 'id' => 42 }

        expect(normalize(arguments)).to match_array(['id->project_id', 'project_id:integer->string'])
        expect(arguments).to eq('project_id' => '42')
      end

      it 'coerces an integer project_id' do
        arguments = { 'project_id' => 42 }

        expect(normalize(arguments)).to eq(['project_id:integer->string'])
        expect(arguments).to eq('project_id' => '42')
      end

      it 'leaves a zero project_id unchanged' do
        arguments = { 'project_id' => 0 }

        expect(normalize(arguments)).to eq([])
        expect(arguments).to eq('project_id' => 0)
      end

      it 'does not rewrite when the caller sent both keys' do
        arguments = { 'id' => 'foo/bar', 'project_id' => 'baz/qux' }

        expect(normalize(arguments)).to eq([])
        expect(arguments).to eq('id' => 'foo/bar', 'project_id' => 'baz/qux')
      end

      it 'does not coerce when the caller sent both keys' do
        arguments = { 'id' => 'foo/bar', 'project_id' => 42 }

        expect(normalize(arguments)).to eq([])
        expect(arguments).to eq('id' => 'foo/bar', 'project_id' => 42)
      end

      context 'when the schema does not declare project_id' do
        let(:properties) { { group_id: { type: 'string' } } }

        it 'does not rewrite' do
          arguments = { 'id' => 'flightjs/Flight' }

          expect(normalize(arguments)).to eq([])
          expect(arguments).to eq('id' => 'flightjs/Flight')
        end

        it 'does not coerce an integer project_id' do
          arguments = { 'project_id' => 42 }

          expect(normalize(arguments)).to eq([])
          expect(arguments).to eq('project_id' => 42)
        end
      end

      context 'when the schema types project_id as an integer' do
        let(:properties) { { project_id: { type: 'integer' } } }

        it 'does not coerce' do
          arguments = { 'project_id' => 42 }

          expect(normalize(arguments)).to eq([])
          expect(arguments).to eq('project_id' => 42)
        end
      end

      context 'when the schema also declares id' do
        let(:properties) { { project_id: { type: 'string' }, id: { type: 'integer' } } }

        it 'does not rewrite' do
          arguments = { 'id' => 42 }

          expect(normalize(arguments)).to eq([])
          expect(arguments).to eq('id' => 42)
        end
      end
    end

    context 'when the schema declares iid arguments' do
      let(:properties) do
        { project_id: { type: 'string' }, work_item_iid: { type: 'integer' }, merge_request_iid: { type: 'integer' } }
      end

      it 'renames id when the caller sent an iid' do
        arguments = { 'id' => 'flightjs/Flight', 'merge_request_iid' => 3 }

        expect(normalize(arguments)).to eq(['id->project_id'])
        expect(arguments).to eq('project_id' => 'flightjs/Flight', 'merge_request_iid' => 3)
      end

      it 'does not rename id without an iid' do
        arguments = { 'id' => 'gid://gitlab/WorkItem/1' }

        expect(normalize(arguments)).to eq([])
        expect(arguments).to eq('id' => 'gid://gitlab/WorkItem/1')
      end

      it 'coerces an integer project_id without an iid' do
        arguments = { 'project_id' => 42 }

        expect(normalize(arguments)).to eq(['project_id:integer->string'])
        expect(arguments).to eq('project_id' => '42')
      end
    end

    context 'when the tool declares id as its project argument' do
      let(:declared) { { project: :id } }
      let(:properties) { { id: { type: 'string' } } }

      it 'renames project_id to id' do
        arguments = { 'project_id' => 'flightjs/Flight' }

        expect(normalize(arguments)).to eq(['project_id->id'])
        expect(arguments).to eq('id' => 'flightjs/Flight')
      end

      it 'renames and coerces an integer project_id' do
        arguments = { 'project_id' => 42 }

        expect(normalize(arguments)).to match_array(['project_id->id', 'id:integer->string'])
        expect(arguments).to eq('id' => '42')
      end

      it 'coerces an integer id' do
        arguments = { 'id' => 42 }

        expect(normalize(arguments)).to eq(['id:integer->string'])
        expect(arguments).to eq('id' => '42')
      end
    end

    context 'when project_id is not the first declared project key' do
      let(:declared) { { project: %i[start_project project_id] } }

      it 'renames id to project_id' do
        arguments = { 'id' => 'flightjs/Flight' }

        expect(normalize(arguments)).to eq(['id->project_id'])
        expect(arguments).to eq('project_id' => 'flightjs/Flight')
      end
    end

    context 'when the project declaration lists both id and project_id' do
      let(:declared) { { project: %i[id project_id] } }

      it 'does not rewrite' do
        arguments = { 'id' => 'flightjs/Flight' }

        expect(normalize(arguments)).to eq([])
        expect(arguments).to eq('id' => 'flightjs/Flight')
      end
    end

    context 'when the project argument is neither id nor project_id' do
      let(:declared) { { project: :project_full_path } }

      it 'does not rewrite' do
        arguments = { 'project_id' => 'flightjs/Flight' }

        expect(normalize(arguments)).to eq([])
        expect(arguments).to eq('project_id' => 'flightjs/Flight')
      end
    end

    context 'when the tool declares no project argument' do
      let(:declared) { {} }

      it 'does not rewrite' do
        arguments = { 'id' => 'flightjs/Flight' }

        expect(normalize(arguments)).to eq([])
        expect(arguments).to eq('id' => 'flightjs/Flight')
      end
    end
  end

  describe 'registered tools' do
    it 'renames a lone id or project_id on every tool except these' do
      skipped = Mcp::Tools::Manager.new.tools.select do |_name, tool|
        properties = tool.input_schema.to_h.with_indifferent_access[:properties] || {}
        declared = Array(tool.container_arguments[:project]).map(&:to_s) & %w[id project_id]
        legacy = declared.first == 'id' ? 'project_id' : 'id'

        declared.one? && properties.key?(declared.first) &&
          described_class.normalize!(tool, { legacy => 'group/project' }).empty?
      end

      expect(skipped.keys).to match_array(%w[
        accept_merge_request get_issue get_merge_request get_merge_request_commits get_merge_request_conflicts
        get_merge_request_diffs get_merge_request_notes get_merge_request_pipelines get_work_item get_workitem_notes
        link_work_items list_work_items save_merge_request save_merge_request_review save_note save_pipeline
        save_work_item
      ])
    end
  end
end
