# frozen_string_literal: true

RSpec.describe QA::Tools::Ci::E2eTestSelector, feature_category: :tooling do
  include QA::Support::Helpers::StubEnv

  subject(:selector) { described_class.new(changed_files) }

  let(:backend_map) do
    {
      "./qa/specs/features/api/test_spec.rb:23" => ["lib/model.rb"],
      "./qa/specs/features/api/test_spec.rb:40" => ["lib/second.rb"],
      "./qa/specs/features/ui/test_spec_2.rb:11" => ["app/controller.rb"]
    }
  end

  let(:frontend_map) do
    {
      "./qa/specs/features/ui/create_project_spec.rb:12" => [
        "/builds/gitlab-org/gitlab/app/assets/javascripts/projects/new/index.js"
      ]
    }
  end

  let(:backend_mapping) { instance_double(QA::Tools::Ci::CodePathsMapping, import: backend_map) }
  let(:frontend_mapping) { instance_double(QA::Tools::Ci::CodePathsMapping, import: frontend_map) }

  before do
    allow(QA::Tools::Ci::CodePathsMapping).to receive(:new).and_return(backend_mapping, frontend_mapping)
  end

  context "with a changed file in the backend mapping" do
    let(:changed_files) { ["lib/second.rb"] }

    it "returns the spec file once, without the example line" do
      expect(selector.execute).to eq(["qa/specs/features/api/test_spec.rb"])
    end
  end

  context "with a changed file outside the mapping" do
    let(:changed_files) { ["lib/new.rb"] }

    it "returns no specs" do
      expect(selector.execute).to be_empty
    end
  end

  context "when the backend mapping can't be read" do
    let(:changed_files) { ["lib/model.rb"] }
    let(:backend_map) { nil }

    it "returns no specs" do
      expect(selector.execute).to be_empty
    end
  end

  context "with a changed frontend file" do
    let(:changed_files) { ["app/assets/javascripts/projects/new/index.js"] }

    it "skips the frontend mapping when frontend selection is off" do
      stub_env('FRONTEND_SELECTIVE_EXECUTION', 'false')

      expect(selector.execute).to be_empty
    end

    it "matches the frontend mapping after removing the build path when frontend selection is on" do
      stub_env('FRONTEND_SELECTIVE_EXECUTION', 'true')

      expect(selector.execute).to eq(["qa/specs/features/ui/create_project_spec.rb"])
    end
  end
end
