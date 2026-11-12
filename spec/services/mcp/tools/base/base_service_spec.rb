# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Base::BaseService, feature_category: :mcp_server do
  let(:service_name) { 'test_tool' }
  let(:service) { described_class.new(name: service_name) }

  let(:test_service_class) do
    Class.new(described_class) do
      def description
        'Test tool for specs'
      end

      def input_schema
        {
          type: 'object',
          properties: {
            required_field: { type: 'string' },
            optional_field: { type: 'integer' },
            items_field: { type: 'array', items: { type: 'string' }, maxItems: 3 },
            enum_field: { type: 'string', enum: %w[option_a option_b option_c] }
          },
          required: ['required_field']
        }
      end

      def version
        '1.0.0'
      end

      protected

      def perform(arguments, _query = {})
        raise StandardError, 'Something went wrong' if arguments[:required_field] == 'error'

        formatted_content = [{ type: 'text', text: 'Success' }]
        Mcp::Tools::Base::Response.success(formatted_content, { processed: true })
      end
    end
  end

  let(:test_service) { test_service_class.new(name: service_name) }

  describe '#unlisted?' do
    it 'returns false by default' do
      expect(service.unlisted?).to be(false)
    end

    context 'when a subclass marks itself unlisted' do
      let(:unlisted_service_class) do
        Class.new(described_class) do
          def unlisted?
            true
          end
        end
      end

      it 'returns true' do
        expect(unlisted_service_class.new(name: service_name).unlisted?).to be(true)
      end
    end
  end

  describe '#description' do
    it 'raises NoMethodError' do
      expect { service.description }.to raise_error(NoMethodError)
    end
  end

  describe '#input_schema' do
    it 'raises NoMethodError' do
      expect { service.input_schema }.to raise_error(NoMethodError)
    end
  end

  describe '#version' do
    it 'raises NoMethodError' do
      expect { service.version }.to raise_error(NoMethodError)
    end
  end

  describe '#perform' do
    it 'raises NoMethodError' do
      expect { service.send(:perform, {}, {}) }.to raise_error(NoMethodError)
    end
  end

  describe '#set_cred' do
    it 'raises NoMethodError' do
      expect { service.set_cred(current_user: nil, access_token: nil) }.to raise_error(NoMethodError)
    end
  end

  describe '#available?' do
    it 'returns true' do
      expect(service.available?(build(:user))).to be true
    end
  end

  describe '.tool_aliases' do
    it 'returns empty array by default' do
      expect(described_class.tool_aliases).to eq([])
    end
  end

  describe '#tool_aliases' do
    it 'delegates to the class method' do
      allow(test_service_class).to receive(:tool_aliases).and_return(['old_name'])

      expect(test_service.tool_aliases).to eq(['old_name'])
    end
  end

  describe '#to_h' do
    it 'returns tool metadata without annotations when empty' do
      result = test_service.to_h

      expect(result).to eq({
        name: service_name,
        description: 'Test tool for specs',
        inputSchema: {
          type: 'object',
          properties: {
            required_field: { type: 'string' },
            optional_field: { type: 'integer' },
            items_field: { type: 'array', items: { type: 'string' }, maxItems: 3 },
            enum_field: { type: 'string', enum: %w[option_a option_b option_c] }
          },
          required: ['required_field']
        },
        icons: [Mcp::Tools::Base::IconConfig.gitlab_icons.first]
      })

      expect(result).not_to have_key(:annotations)
    end

    context 'when tool has annotations' do
      let(:test_service_with_annotations_class) do
        Class.new(described_class) do
          def description
            'Test tool with annotations'
          end

          def input_schema
            { type: 'object', properties: {} }
          end

          def version
            '1.0.0'
          end

          def annotations
            { readOnlyHint: true }
          end

          protected

          def perform(_arguments, _query = {})
            Mcp::Tools::Base::Response.success([], {})
          end
        end
      end

      let(:test_service_with_annotations) do
        test_service_with_annotations_class.new(name: service_name)
      end

      it 'includes annotations in tool metadata while preserving icons' do
        result = test_service_with_annotations.to_h

        expect(result).to eq({
          name: service_name,
          description: 'Test tool with annotations',
          inputSchema: { type: 'object', properties: {} },
          icons: [Mcp::Tools::Base::IconConfig.gitlab_icons.first],
          annotations: { readOnlyHint: true }
        })
      end
    end

    context 'when icons returns empty array' do
      before do
        allow(test_service).to receive(:icons).and_return([])
      end

      it 'does not include icons key' do
        result = test_service.to_h

        expect(result).not_to have_key(:icons)
      end
    end
  end

  describe '#icons' do
    it 'returns icons array' do
      icons = test_service.icons

      expect(icons).to be_an(Array)
      expect(icons.first).to include(:mimeType, :src, :theme)
    end
  end

  describe '#execute' do
    let(:access_token) { 'test_token' }

    context 'with valid arguments' do
      let(:arguments) { { arguments: { required_field: 'test' } } }

      it 'returns success response' do
        result = test_service.execute(request: nil, params: arguments)

        expect(result).to eq({
          content: [{ type: 'text', text: 'Success' }],
          structuredContent: { processed: true },
          isError: false
        })
      end
    end

    context 'with a request' do
      let(:request) { instance_double(ActionDispatch::Request) }
      let(:arguments) { { arguments: { required_field: 'test' } } }

      let(:request_aware_service_class) do
        Class.new(test_service_class) do
          protected

          def perform(_arguments, _query = {})
            Mcp::Tools::Base::Response.success(
              [{ type: 'text', text: 'ok' }],
              { request: request }
            )
          end
        end
      end

      let(:request_aware_service) { request_aware_service_class.new(name: service_name) }

      it 'makes the request available to subclasses through the inherited reader' do
        result = request_aware_service.execute(request: request, params: arguments)

        expect(result.dig(:structuredContent, :request)).to eq(request)
      end

      it 'does not keep the request after a later call without one' do
        request_aware_service.execute(request: request, params: arguments)
        result = request_aware_service.execute(request: nil, params: arguments)

        expect(result.dig(:structuredContent, :request)).to be_nil
      end
    end

    context 'with missing required field' do
      let(:arguments) { { arguments: { optional_field: 123 } } }

      it 'returns validation error', :aggregate_failures do
        result = test_service.execute(request: nil, params: arguments)

        expect(result[:isError]).to be true
        expect(result[:reason]).to eq(:bad_request)
        expect(result[:content].first[:text]).to eq('Validation error: required_field is missing')
      end
    end

    context 'with array exceeding maxItems' do
      let(:arguments) { { arguments: { required_field: 'valid', items_field: %w[a b c d] } } }

      it 'returns validation error with maxItems message' do
        result = test_service.execute(request: nil, params: arguments)

        expect(result[:isError]).to be true
        expect(result[:content].first[:text]).to include('items_field cannot contain more than 3 items')
      end
    end

    context 'with invalid enum value' do
      let(:arguments) { { arguments: { required_field: 'valid', enum_field: 'invalid_option' } } }

      it 'returns validation error with enum message' do
        result = test_service.execute(request: nil, params: arguments)

        expect(result[:isError]).to be true
        expect(result[:content].first[:text])
          .to include("Invalid enum_field: 'invalid_option'. Must be one of: option_a, option_b, option_c")
      end
    end

    context 'with invalid field type' do
      let(:arguments) { { arguments: { required_field: 123 } } }

      it 'returns validation error' do
        result = test_service.execute(request: nil, params: arguments)

        expect(result[:isError]).to be true
        expect(result[:content].first[:text]).to eq('Validation error: required_field is invalid')
      end
    end

    context 'with unknown parameter when additionalProperties is false' do
      let(:strict_service_class) do
        Class.new(test_service_class) do
          def input_schema
            Mcp::Tools::Base::SchemaDefaults.with_additional_properties(super)
          end
        end
      end

      let(:strict_service) { strict_service_class.new(name: service_name) }
      let(:arguments) { { arguments: { unknown_param: 'value' } } }

      it 'names the unknown parameter, lists accepted parameters, and reports missing required fields' do
        result = strict_service.execute(request: nil, params: arguments)

        expect(result[:isError]).to be true
        expect(result[:content].first[:text]).to eq(
          'Validation error: unknown_param is invalid: unknown parameter; ' \
            'required_field is missing; ' \
            'Accepted parameters: required_field, optional_field, items_field, enum_field'
        )
      end
    end

    context 'with multiple unknown parameters' do
      let(:strict_service_class) do
        Class.new(test_service_class) do
          def input_schema
            Mcp::Tools::Base::SchemaDefaults.with_additional_properties(super)
          end
        end
      end

      let(:strict_service) { strict_service_class.new(name: service_name) }
      let(:arguments) { { arguments: { unknown_one: '1', unknown_two: '2' } } }

      it 'lists each unknown parameter and prints the accepted parameter list once' do
        result = strict_service.execute(request: nil, params: arguments)

        expect(result[:isError]).to be true
        expect(result[:content].first[:text]).to eq(
          'Validation error: unknown_one is invalid: unknown parameter; ' \
            'unknown_two is invalid: unknown parameter; ' \
            'required_field is missing; ' \
            'Accepted parameters: required_field, optional_field, items_field, enum_field'
        )
      end
    end

    context 'with unknown parameter when tool takes no parameters' do
      let(:no_params_service_class) do
        Class.new(test_service_class) do
          def input_schema
            Mcp::Tools::Base::SchemaDefaults.with_additional_properties(
              type: 'object',
              properties: {}
            )
          end
        end
      end

      let(:no_params_service) { no_params_service_class.new(name: service_name) }
      let(:arguments) { { arguments: { verbose: true } } }

      it 'reports that the tool takes no parameters' do
        result = no_params_service.execute(request: nil, params: arguments)

        expect(result[:isError]).to be true
        expect(result[:content].first[:text]).to eq(
          'Validation error: verbose is invalid: unknown parameter; This tool takes no parameters'
        )
      end
    end

    context 'with string-keyed schema properties' do
      let(:string_keyed_service_class) do
        Class.new(test_service_class) do
          def input_schema
            Mcp::Tools::Base::SchemaDefaults.with_additional_properties(
              'type' => 'object',
              'properties' => {
                'target' => { 'type' => 'string' }
              }
            )
          end
        end
      end

      let(:string_keyed_service) { string_keyed_service_class.new(name: service_name) }
      let(:arguments) { { arguments: { unexpected: 'val' } } }

      it 'lists accepted parameters from string-keyed properties' do
        result = string_keyed_service.execute(request: nil, params: arguments)

        expect(result[:isError]).to be true
        expect(result[:content].first[:text]).to eq(
          'Validation error: unexpected is invalid: unknown parameter; Accepted parameters: target'
        )
      end
    end

    context 'with typed additionalProperties and invalid property type' do
      let(:typed_additional_service_class) do
        Class.new(test_service_class) do
          def input_schema
            super.merge(additionalProperties: { type: 'string' })
          end
        end
      end

      let(:typed_additional_service) { typed_additional_service_class.new(name: service_name) }
      let(:arguments) { { arguments: { required_field: 'valid', extra_num: 123 } } }

      it 'reports field is invalid rather than unknown parameter' do
        result = typed_additional_service.execute(request: nil, params: arguments)

        expect(result[:isError]).to be true
        expect(result[:content].first[:text]).to eq('Validation error: extra_num is invalid')
      end
    end

    context 'with multiple missing required fields' do
      let(:multi_required_service_class) do
        Class.new(test_service_class) do
          def input_schema
            super.merge(required: %w[required_field optional_field])
          end
        end
      end

      let(:multi_required_service) { multi_required_service_class.new(name: service_name) }

      it 'reports all missing required fields' do
        result = multi_required_service.execute(request: nil, params: { arguments: {} })

        expect(result[:isError]).to be true
        expect(result[:content].first[:text])
          .to eq('Validation error: required_field is missing; optional_field is missing')
      end
    end

    context 'when perform raises an error' do
      let(:arguments) { { arguments: { required_field: 'error' } } }

      it 'returns execution error' do
        result = test_service.execute(request: nil, params: arguments)

        expect(result[:isError]).to be true
        expect(result[:content].first[:text]).to eq('Tool execution failed: Something went wrong')
      end

      it 'reports the exception, which the response no longer carries into the log' do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception)
          .with(an_instance_of(StandardError), mcp_tool: service_name)

        test_service.execute(request: nil, params: arguments)
      end
    end

    context 'with nil arguments' do
      let(:arguments) { { arguments: nil } }

      it 'returns validation error' do
        result = test_service.execute(request: nil, params: arguments)

        expect(result[:isError]).to be true
        expect(result[:content].first[:text]).to include('required_field is missing')
      end
    end

    context 'when an optional argument is sent as nil or an empty string' do
      let(:echo_service_class) do
        Class.new(described_class) do
          def description
            'Echoes the arguments it received'
          end

          def input_schema
            {
              type: 'object',
              properties: {
                required_field: { type: 'string' },
                optional_field: { type: 'integer' },
                enum_field: { type: 'string', enum: %w[option_a option_b option_c] },
                flag_field: { type: 'boolean' },
                list_field: { type: 'array', items: { type: 'string' } }
              },
              required: ['required_field']
            }
          end

          def version
            '1.0.0'
          end

          protected

          def perform(arguments, _query = {})
            Mcp::Tools::Base::Response.success([{ type: 'text', text: 'ok' }], arguments)
          end
        end
      end

      let(:echo_service) { echo_service_class.new(name: service_name) }

      def execute_with(args)
        echo_service.execute(request: nil, params: { arguments: args })
      end

      it 'treats them as omitted instead of rejecting them', :aggregate_failures do
        result = execute_with({ required_field: 'test', optional_field: nil, enum_field: '' })

        expect(result[:isError]).to be false
        expect(result[:structuredContent]).to eq({ required_field: 'test' })
      end

      it 'preserves false and empty collections', :aggregate_failures do
        result = execute_with({ required_field: 'test', flag_field: false, list_field: [] })

        expect(result[:isError]).to be false
        expect(result[:structuredContent]).to eq({ required_field: 'test', flag_field: false, list_field: [] })
      end

      it 'still rejects a value that is present but not allowed', :aggregate_failures do
        result = execute_with({ required_field: 'test', enum_field: 'nope' })

        expect(result[:isError]).to be true
        expect(result[:content].first[:text])
          .to include("Invalid enum_field: 'nope'. Must be one of: option_a, option_b, option_c")
      end

      it 'reports a required field sent as nil as missing', :aggregate_failures do
        result = execute_with({ required_field: nil })

        expect(result[:isError]).to be true
        expect(result[:content].first[:text]).to include('required_field is missing')
      end
    end

    context 'when an integer argument is a zero-filled ID or a bounded field' do
      let(:minimum_service_class) do
        Class.new(described_class) do
          def description
            'Echoes the arguments it received'
          end

          def input_schema
            {
              type: 'object',
              properties: {
                id: { type: 'integer' },
                item_iid: { type: 'integer' },
                project_id: { type: 'integer' },
                name: { type: 'string' },
                weight: { type: 'integer' },
                line: { type: 'integer', minimum: 1 }
              }
            }
          end

          def version
            '1.0.0'
          end

          protected

          def perform(arguments, _query = {})
            Mcp::Tools::Base::Response.success([{ type: 'text', text: 'ok' }], arguments)
          end
        end
      end

      let(:minimum_service) { minimum_service_class.new(name: service_name) }

      def execute_with(args)
        minimum_service.execute(request: nil, params: { arguments: args })
      end

      it 'strips zero for *_iid fields by name pattern', :aggregate_failures do
        result = execute_with({ item_iid: 0, name: 'test' })

        expect(result[:isError]).to be false
        expect(result[:structuredContent]).to eq({ name: 'test' })
      end

      it 'strips zero for *_id fields by name pattern', :aggregate_failures do
        result = execute_with({ project_id: 0, name: 'test' })

        expect(result[:isError]).to be false
        expect(result[:structuredContent]).to eq({ name: 'test' })
      end

      it 'strips zero for a bare id field' do
        result = execute_with({ id: 0, name: 'test' })

        expect(result[:structuredContent]).to eq({ name: 'test' })
      end

      it 'strips zero for non-ID fields with minimum: 1' do
        result = execute_with({ line: 0, name: 'test' })

        expect(result[:structuredContent]).to eq({ name: 'test' })
      end

      it 'preserves non-zero values for ID fields' do
        result = execute_with({ item_iid: 42, project_id: 5, name: 'test' })

        expect(result[:structuredContent]).to eq({ item_iid: 42, project_id: 5, name: 'test' })
      end

      it 'preserves zero for integer fields that are neither ID nor minimum: 1' do
        result = execute_with({ weight: 0, name: 'test' })

        expect(result[:structuredContent]).to eq({ weight: 0, name: 'test' })
      end

      it 'strips multiple zero-valued fields across both patterns', :aggregate_failures do
        result = execute_with({ item_iid: 0, project_id: 0, line: 0, name: 'test' })

        expect(result[:isError]).to be false
        expect(result[:structuredContent]).to eq({ name: 'test' })
      end

      it 'strips negative values for ID fields' do
        result = execute_with({ item_iid: -1, project_id: -5, name: 'test' })

        expect(result[:structuredContent]).to eq({ name: 'test' })
      end

      it 'still strips nil and empty string values', :aggregate_failures do
        result = execute_with({ item_iid: nil, name: '', weight: 0 })

        expect(result[:isError]).to be false
        expect(result[:structuredContent]).to eq({ weight: 0 })
      end
    end
  end
end
