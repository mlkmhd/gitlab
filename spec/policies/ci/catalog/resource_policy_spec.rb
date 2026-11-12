# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::Catalog::ResourcePolicy, feature_category: :pipeline_composition do
  let(:user) { build(:user) }
  let(:resource) { build(:ci_catalog_resource, project: build(:project)) }

  subject(:policy) { described_class.new(user, resource) }

  it { is_expected.to delegate_to(ProjectPolicy) }
end
