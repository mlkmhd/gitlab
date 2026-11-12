# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onboarding::ProgressTrackingWorker, '#perform', feature_category: :onboarding do
  let_it_be(:namespace) { create(:namespace) }
  let(:action) { 'user_added' }

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [namespace.id, action] }
  end
end
