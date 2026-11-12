# frozen_string_literal: true

# Helpers for the permission tables in spec/support/shared_contexts/policies/ and
# spec/support/shared_contexts/work_items/confidentiality_shared_context.rb
module PermissionTableHelpers
  # Groups permission table rows by everything but the last three columns (membership,
  # admin mode and expected count), so one example sets up each setting once and checks
  # every membership against it.
  def access_cases_by_setting(table)
    table.to_params.group_by { |row| row[0...-3] }.map { |setting, rows| [*setting, rows.map { |row| row.last(3) }] }
  end
end
