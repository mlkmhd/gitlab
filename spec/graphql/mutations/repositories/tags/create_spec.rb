# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Repositories::Tags::Create, feature_category: :source_code_management do
  specify { expect(described_class).to require_graphql_authorizations(:create_repository_tag) }
end
