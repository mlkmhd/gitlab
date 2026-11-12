# frozen_string_literal: true

require 'spec_helper'

# Part of the test security suite for the Import/Export feature
# Checks whether there are new attributes in models that are currently being exported as part of the
# project Import/Export feature.
# If there are new attributes, these will have to either be added to this spec in case we want them
# to be included as part of the export, or add them to excluded_attributes in the import_export.yml configuration file.
# Likewise, new models added to import_export.yml, will need to be added with their correspondent attributes
# to this spec.
RSpec.describe 'Import/Export attribute configuration', feature_category: :importers do
  include ConfigurationHelper

  let(:safe_attributes_file) { 'spec/lib/gitlab/import_export/safe_model_attributes.yml' }
  let(:safe_model_attributes) { YAML.load_file(safe_attributes_file) }
  let(:ignored_attributes_file) { 'lib/gitlab/import_export/project/ignored_exported_attributes.yml' }
  let(:ignored_attributes) { YAML.load_file(ignored_attributes_file) }

  it 'has no new columns' do
    relation_names_for(:project).each do |relation_name|
      relation_class = relation_class_for_name(relation_name)
      relation_attributes = relation_class.new.attributes.keys - relation_class.attr_encrypted_encrypted_attributes.keys.map(&:to_s)

      current_attributes = parsed_attributes(relation_name, relation_attributes)
      safe_attributes = safe_model_attributes[relation_class.to_s].dup || []

      expect(safe_attributes).not_to be_nil, "Expected exported class #{relation_class} to exist in safe_model_attributes"

      new_attributes = current_attributes - safe_attributes

      expect(new_attributes).to be_empty, failure_message(relation_class.to_s, new_attributes)
    end
  end

  # Only models listed in the ignored attributes file are checked, so the check can be rolled out model by model.
  it 'accounts for every column of models in the ignored attributes file', :aggregate_failures do
    relations = relation_names_for(:project).group_by { |name| relation_class_for_name(name).name }

    ignored_attributes.each do |class_name, ignored|
      ignored ||= {}
      relation_class = class_name.safe_constantize
      next if relation_class.nil? && !Gitlab.ee? # EE-only model in FOSS

      relation_names = relations[class_name]
      expect(relation_names).to be_present,
        "#{class_name} in #{ignored_attributes_file} is not a model exported by project Import/Export"
      next unless relation_names

      # A column exported by any relation of the class is accounted for. Some relations export only a few
      # columns on purpose, like Ci::Pipeline for vulnerability findings.
      accounted = relation_names.flat_map do |name|
        parsed_attributes(name, relation_class.column_names) + excluded_attributes_for(name)
      end
      unaccounted = relation_class.column_names - accounted - Array(relation_class.primary_key) - ignored.keys

      expect(unaccounted).to be_empty, unaccounted_message(class_name, unaccounted)
      expect(ignored.keys - relation_class.column_names).to be_empty,
        "Remove #{class_name} entries for columns that no longer exist from #{ignored_attributes_file}"
      expect(ignored.keys & accounted).to be_empty,
        "Remove #{class_name} entries for columns that are now exported or excluded from #{ignored_attributes_file}"
      has_reason = satisfy { |entry| entry.is_a?(Hash) && entry.values_at('note', 'migrate_issue_url').any?(&:present?) }
      expect(ignored.values).to all(has_reason),
        "Give every #{class_name} entry in #{ignored_attributes_file} a `note` or a `migrate_issue_url`"
    end
  end

  def excluded_attributes_for(relation_name)
    Array(config_hash.dig(:excluded_attributes, relation_name.to_sym)).map(&:to_s)
  end

  def unaccounted_message(class_name, attributes)
    <<~MSG
      #{class_name} has columns that project Import/Export neither exports nor ignores: #{attributes.join(', ')}

      Add each column to +included_attributes+ in #{Gitlab::ImportExport.config_file} to export it, after
      checking https://docs.gitlab.com/development/import_export/#security-in-the-code. Otherwise, add it to
      +excluded_attributes+, or to #{ignored_attributes_file} with a `note` or a `migrate_issue_url`.
      See https://docs.gitlab.com/development/import_export/#ignored-exported-attributes
    MSG
  end

  def failure_message(relation_class, new_attributes)
    <<-MSG
      It looks like #{relation_class}, which is exported using the project Import/Export, has new attributes: #{new_attributes.join(',')}

      Please add the attribute(s) to SAFE_MODEL_ATTRIBUTES if they can be exported.

      Please denylist the attribute(s) in IMPORT_EXPORT_CONFIG by adding it to its corresponding
      model in the +excluded_attributes+ section.

      SAFE_MODEL_ATTRIBUTES: #{File.expand_path(safe_attributes_file)}
      IMPORT_EXPORT_CONFIG: #{Gitlab::ImportExport.config_file}
    MSG
  end
end
