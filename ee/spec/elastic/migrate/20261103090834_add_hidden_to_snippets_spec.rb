# frozen_string_literal: true

require 'spec_helper'
require File.expand_path('ee/elastic/migrate/20261103090834_add_hidden_to_snippets.rb')

RSpec.describe AddHiddenToSnippets, :elastic, feature_category: :global_search do
  let(:version) { 20261103090834 }

  include_examples 'migration adds mapping'
end
