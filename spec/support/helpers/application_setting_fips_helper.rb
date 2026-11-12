# frozen_string_literal: true

# Test-only helper. FactoryBot-built ApplicationSettings default to SSH
# key-size restrictions that are invalid under FIPS, so FIPS-mode specs would
# build invalid records. Bump them to the minimum compliant size. Production
# builds settings through its own defaults and never needs this.
#
module ApplicationSettingFipsHelper
  module_function

  def ensure_key_restrictions!(settings)
    return if Gitlab::Database.read_only?
    return unless Gitlab::FIPS.enabled?

    Gitlab::SSHPublicKey.supported_types.each do |key_type|
      set_max_key_restriction!(settings, key_type)
    end
  end

  def set_max_key_restriction!(settings, key_type)
    attr_name = "#{key_type}_key_restriction"
    current = settings.attributes[attr_name].to_i

    return if current == KeyRestrictionValidator::FORBIDDEN

    min_size = settings.class.default_min_key_size(key_type)

    new_value =
      if min_size == KeyRestrictionValidator::FORBIDDEN
        min_size
      else
        [min_size, current].max
      end

    settings.assign_attributes(attr_name => new_value)
  end
  private_class_method :set_max_key_restriction!
end
