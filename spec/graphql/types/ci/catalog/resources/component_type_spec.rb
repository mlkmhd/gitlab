# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ci::Catalog::Resources::ComponentType, feature_category: :pipeline_composition do
  let(:component_type) { described_class.authorized_new(component, context) }
  let(:context) { GraphQL::Query::Context.new(query: query, values: {}) }
  let(:query) { GraphQL::Query.new(GitlabSchema) }
  let(:component) { create(:ci_catalog_resource_component, version: version, spec: spec) }
  let_it_be(:version, freeze: false) { create(:ci_catalog_resource_version) }

  specify { expect(described_class.graphql_name).to eq('CiCatalogResourceComponent') }

  it 'exposes the expected fields' do
    expected_fields = %i[
      id
      inputs
      name
      include_path
      description
      last_30_day_usage_count
    ]

    expect(described_class).to have_graphql_fields(*expected_fields)
  end

  describe '#description' do
    context 'when spec contains a description' do
      let(:spec) do
        {
          'description' => 'A helpful component description',
          'inputs' => { 'foo' => { 'default' => 'bar' } }
        }
      end

      it 'returns the description' do
        expect(component_type.description).to eq('A helpful component description')
      end
    end

    context 'when spec does not contain a description' do
      let(:spec) do
        {
          'inputs' => { 'foo' => { 'default' => 'bar' } }
        }
      end

      it 'returns nil' do
        expect(component_type.description).to be_nil
      end
    end
  end

  describe '#inputs' do
    # The input names are deliberately neither in `inputs` order nor in length order, so that the
    # assertions fail if `inputs_order` is not applied.
    let(:inputs) do
      {
        'stage' => { 'default' => 'test' },
        'environment' => { 'description' => 'Deployment target' },
        'n' => { 'type' => 'number' }
      }
    end

    context 'when spec contains inputs_order' do
      let(:spec) { { 'inputs' => inputs, 'inputs_order' => %w[environment n stage] } }

      it 'returns the inputs in the recorded order' do
        expect(component_type.inputs.pluck(:name)).to eq(%w[environment n stage])
      end

      it 'returns the fields of each input' do
        expect(component_type.inputs).to include(
          {
            name: 'environment',
            required?: true,
            default: nil,
            options: nil,
            description: 'Deployment target',
            regex: nil,
            type: 'string',
            rules: nil
          },
          {
            name: 'n',
            required?: true,
            default: nil,
            options: nil,
            description: nil,
            regex: nil,
            type: 'number',
            rules: nil
          },
          {
            name: 'stage',
            required?: false,
            default: 'test',
            options: nil,
            description: nil,
            regex: nil,
            type: 'string',
            rules: nil
          }
        )
      end
    end

    context 'when an input declares options' do
      let(:spec) { { 'inputs' => { 'stage' => { 'default' => 'test', 'options' => %w[build test] } } } }

      it 'returns the options' do
        expect(component_type.inputs.first[:options]).to eq(%w[build test])
      end
    end

    context 'when an input declares options that are not an array' do
      let(:spec) { { 'inputs' => { 'stage' => { 'default' => 'test', 'options' => 'test' } } } }

      it 'returns no options' do
        expect(component_type.inputs.first[:options]).to be_nil
      end
    end

    context 'when an input takes its options from rules' do
      let(:rules) do
        [
          { 'if' => '$[[ inputs.env ]] == "prod"', 'options' => %w[us-east eu-west], 'default' => 'us-east' },
          { 'options' => %w[local], 'default' => 'local' }
        ]
      end

      let(:spec) { { 'inputs' => { 'region' => { 'rules' => rules } } } }

      it 'returns the rules' do
        expect(component_type.inputs.first[:rules]).to eq(rules)
      end

      it 'marks the input as optional' do
        expect(component_type.inputs.first[:required?]).to be(false)
      end
    end

    context 'when an input declares rules that are not an array' do
      let(:spec) { { 'inputs' => { 'region' => { 'rules' => 'prod' } } } }

      it 'returns no rules' do
        expect(component_type.inputs.first[:rules]).to be_nil
      end
    end

    context 'when an input declares rules that are not hashes' do
      let(:spec) { { 'inputs' => { 'region' => { 'rules' => ['prod', 1] } } } }

      it 'returns no rules' do
        expect(component_type.inputs.first[:rules]).to be_empty
      end
    end

    context 'when a rule declares options that are not an array' do
      let(:rules) do
        [
          { 'if' => '$[[ inputs.env ]] == "prod"', 'options' => 'us-east', 'default' => 'us-east' },
          { 'options' => %w[local], 'default' => 'local' }
        ]
      end

      let(:spec) { { 'inputs' => { 'region' => { 'rules' => rules } } } }

      it 'returns the rule without its options' do
        expect(component_type.inputs.first[:rules]).to eq(
          [
            { 'if' => '$[[ inputs.env ]] == "prod"', 'default' => 'us-east' },
            { 'options' => %w[local], 'default' => 'local' }
          ]
        )
      end
    end

    context 'when the rules of an input provide no default' do
      let(:spec) { { 'inputs' => { 'region' => { 'rules' => [{ 'options' => %w[local] }] } } } }

      it 'marks the input as required' do
        expect(component_type.inputs.first[:required?]).to be(true)
      end
    end

    context 'when an input declares an unsupported type' do
      let(:spec) { { 'inputs' => { 'website' => { 'type' => 'unicorn' }, 'stage' => { 'default' => 'test' } } } }

      it 'returns the other inputs' do
        expect(component_type.inputs.pluck(:name)).to contain_exactly('stage')
      end
    end

    context 'when an input has no configuration' do
      let(:spec) { { 'inputs' => { 'website' => nil } } }

      it 'returns the input with default values' do
        expect(component_type.inputs).to contain_exactly(
          {
            name: 'website',
            required?: true,
            default: nil,
            options: nil,
            description: nil,
            regex: nil,
            type: 'string',
            rules: nil
          }
        )
      end
    end

    context 'when spec does not contain inputs' do
      let(:spec) { { 'description' => 'A component without inputs' } }

      it 'returns no inputs' do
        expect(component_type.inputs).to be_empty
      end
    end
  end
end
