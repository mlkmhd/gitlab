# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DeploymentMergeRequest, feature_category: :continuous_delivery do
  let(:mr) { create(:merge_request, :merged) }
  let(:deployment) { create(:deployment, :success, project: project) }
  let(:project) { mr.project }

  subject { described_class.new(deployment: deployment, merge_request: mr) }

  it { is_expected.to belong_to(:deployment).required }
  it { is_expected.to belong_to(:merge_request).required }
  it { is_expected.to belong_to(:project).optional }
  it { is_expected.to belong_to(:environment).optional }

  describe '.each_batch_for_environment' do
    let_it_be(:project) { create(:project, :repository) }
    let_it_be(:deployment) { create(:deployment, :success, project: project) }
    let_it_be(:other_deployment) { create(:deployment, :success, project: project) }
    let_it_be(:merge_requests) { create_list(:merge_request, 2, :merged, :unique_branches, source_project: project) }

    before_all do
      deployment.link_merge_requests(MergeRequest.id_in(merge_requests))
      other_deployment.link_merge_requests(MergeRequest.id_in(merge_requests))
    end

    it "yields the environment's links in batches" do
      batches = []

      described_class.each_batch_for_environment(deployment.environment, of: 1) do |links|
        batches << links.pluck(:deployment_id, :merge_request_id)
      end

      expect(batches).to eq(merge_requests.map { |merge_request| [[deployment.id, merge_request.id]] })
    end
  end
end
