# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Entities::Ci::RunnerWithUuid, feature_category: :runner_core do
  let_it_be(:runner) { create(:ci_runner) }

  let(:entity) { described_class.new(runner) }

  subject(:runner_entity) { entity.presented.as_json }

  it 'exposes the runner uuid' do
    expect(runner_entity[:uuid]).to eq(runner.uuid)
  end

  it 'exposes the base runner fields' do
    expect(runner_entity).to include(:id, :description, :runner_type, :status)
  end
end
