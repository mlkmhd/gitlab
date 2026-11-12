# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('ee/elastic/migrate/20260803123322_backfill_sbom_occurrence_refs_index.rb')

RSpec.describe BackfillSbomOccurrenceRefsIndex, feature_category: :dependency_management do
  it_behaves_like 'a deprecated Advanced Search migration', 20260803123322
end
