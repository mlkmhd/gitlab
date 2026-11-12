# frozen_string_literal: true

module Gitlab
  module Database
    module Aggregation
      # Shared by the ActiveRecord and ClickHouse filter definitions. Each check is an ActiveModel
      # validator run against the plan part, so it reads the part like any other model attribute.
      # The validators are built once, from the `max_size:` and `in:` options given to the definition.
      module FilterValidators
        def initialize(*args, **kwargs)
          super
          @validators = build_validators(max_size: kwargs[:max_size], allowed_values: kwargs[:in])
        end

        def validate_part(part)
          validators.each { |validator| validator.validate(part) }
        end

        # Read back from the length validator, so the limit is stored in one place.
        def max_size
          length_validator = validators.find { |validator| validator.is_a?(ActiveModel::Validations::LengthValidator) }
          length_validator.options[:maximum] if length_validator
        end

        private

        attr_reader :validators

        # `max_size` checks the formatted values and `in:` the values as the request sent them,
        # because a formatter can drop values it does not recognize.
        def build_validators(max_size:, allowed_values:)
          validators = []

          if max_size
            validators << ActiveModel::Validations::LengthValidator.new(
              attributes: [:values],
              maximum: max_size,
              message: ->(part, data) {
                format(s_("AggregationEngine|maximum size of %{max_size} exceeded for filter `%{key}`"),
                  max_size: data[:count],
                  key: part.instance_key)
              }
            )
          end

          validators << AllowedValuesValidator.new(attributes: [:raw_values], in: allowed_values) if allowed_values

          validators
        end
      end
    end
  end
end
