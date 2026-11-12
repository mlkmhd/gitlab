# frozen_string_literal: true

require 'fast_spec_helper'
require 'grape_entity'

RSpec.describe ::API::Entities::Scim::Error, feature_category: :system_access do
  let(:params) { { detail: 'error' } }
  let(:entity) do
    described_class.new(params)
  end

  subject(:json_response) { entity.as_json }

  it 'contains the schemas' do
    expect(json_response[:schemas]).not_to be_empty
  end

  it 'contains the detail' do
    expect(json_response[:detail]).to eq(params[:detail])
  end

  it 'contains the status' do
    expect(json_response[:status]).to eq(412)
  end

  it 'leaves out scimType when none is given' do
    expect(json_response).not_to have_key(:scimType)
  end

  context 'with a scim_type' do
    let(:params) { { detail: 'error', scim_type: 'mutability' } }

    it 'contains the scimType' do
      expect(json_response[:scimType]).to eq('mutability')
    end
  end
end
