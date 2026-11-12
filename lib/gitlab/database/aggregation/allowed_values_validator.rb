# frozen_string_literal: true

module Gitlab
  module Database
    module Aggregation
      # Rejects values outside the `in:` option. It follows the ActiveModel validator interface, so a
      # definition runs it with `validator.validate(part)` against the plan part attribute it names.
      class AllowedValuesValidator < ActiveModel::EachValidator
        # `allowed` (the `in:` option) is an Array mixing String, Regexp, and
        # Gitlab::UntrustedRegexp entries, or any other container responding to `include?`
        # (for example a Range). Patterns are developer-defined; anchor them with `\A`/`\z`.
        def self.allowed?(allowed, value)
          return value.in?(allowed) unless allowed.is_a?(Array)

          allowed.any? do |entry|
            case entry
            when Regexp, ::Gitlab::UntrustedRegexp then entry.match?(value.to_s)
            else entry == value
            end
          end
        end

        def check_validity!
          raise ArgumentError, ':in is required' if options[:in].nil?
        end

        def validate_each(part, _attribute, value)
          invalid = Array.wrap(value).reject { |v| self.class.allowed?(options[:in], v) }
          return if invalid.empty?

          part.errors.add(:base,
            format(s_("AggregationEngine|Invalid value(s) for filter `%{key}`: %{values}"),
              key: part.instance_key,
              values: invalid.uniq.join(', ')))
        end
      end
    end
  end
end
