# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanProfiles::Configuration::ScanProfileVariables, feature_category: :security_testing_configuration do
  describe 'MAPPINGS' do
    it 'gives every variable a serializer type, a label and a description', :aggregate_failures do
      described_class::MAPPINGS.each_value do |scan_type_mappings|
        scan_type_mappings.each_value do |mapping|
          expect(Security::ScanProfiles::Configuration::CiVariables::SERIALIZERS).to have_key(mapping[:type])
          expect(mapping[:label]).to be_present
          expect(mapping[:description]).to be_present
        end
      end
    end

    describe 'dependency scanning integer ranges' do
      let(:input_type) { Types::Security::ScanProfiles::DependencyScanningConfigurationInputType }
      let(:integer_mappings) do
        described_class::MAPPINGS[:dependency_scanning].select { |_key, mapping| mapping[:type] == :integer }
      end

      def numericality_validator(key)
        input_type.arguments.fetch(key.to_s.camelize(:lower)).validators
          .find { |validator| validator.is_a?(GraphQL::Schema::Validator::NumericalityValidator) }
      end

      it 'has integer variables to check' do
        expect(integer_mappings).not_to be_empty
      end

      it 'accepts its min and its max', :aggregate_failures do
        integer_mappings.each do |key, mapping|
          validator = numericality_validator(key)
          min = mapping[:min]
          max = mapping[:max]

          expect(validator.validate(nil, nil, min)).to be_nil, "expected #{key} to accept its min" if min
          expect(validator.validate(nil, nil, max)).to be_nil, "expected #{key} to accept its max" if max
        end
      end

      it 'rejects values outside its min and max', :aggregate_failures do
        integer_mappings.each do |key, mapping|
          validator = numericality_validator(key)
          min = mapping[:min]
          max = mapping[:max]

          expect(validator.validate(nil, nil, min - 1)).to be_present, "expected #{key} to reject below its min" if min
          expect(validator.validate(nil, nil, max + 1)).to be_present, "expected #{key} to reject above its max" if max
        end
      end
    end
  end
end
