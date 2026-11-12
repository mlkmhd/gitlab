# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe AddIndexMlExperimentsOnProjectIdAndId, feature_category: :mlops do
  let(:connection) { described_class.new.connection }

  def index_exists?
    connection.index_exists?(:ml_experiments, nil, name: described_class::INDEX_NAME)
  end

  it 'adds and removes the index' do
    reversible_migration do |migration|
      migration.before -> { expect(index_exists?).to be(false) }
      migration.after -> { expect(index_exists?).to be(true) }
    end
  end
end
