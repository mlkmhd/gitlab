# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BlobViewer::Citation, feature_category: :source_code_management do
  include FakeBlobHelpers

  let(:project) { build(:project) }
  let(:blob) { fake_blob(path: 'CITATION.cff') }

  it 'matches CITATION.cff blobs' do
    expect(described_class.can_render?(blob)).to be(true)
  end

  it 'does not match other blobs' do
    expect(described_class.can_render?(fake_blob(path: 'README.md'))).to be(false)
  end
end
