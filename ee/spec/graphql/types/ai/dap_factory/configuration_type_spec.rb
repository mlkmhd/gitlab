# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::DapFactory::ConfigurationType, feature_category: :dap_triggers do
  include GraphqlHelpers

  specify { expect(described_class.graphql_name).to eq('DapFactoryConfiguration') }

  it 'has the expected fields' do
    expect(described_class).to have_graphql_fields(
      :path, :default_branch, :last_commit_id, :exists, :content, :errors, :warnings, :auto_review, :last_sync
    )
  end

  describe '#auto_review' do
    let_it_be(:project) { create(:project) }

    it 'builds the Duo Code Review settings for the project' do
      configuration = ::Ai::DapFactory::ConfigurationFile.new(project)

      expect(resolve_field(:auto_review, configuration))
        .to be_a(::Ai::DapFactory::AutoReview).and(have_attributes(project: project))
    end
  end
end
