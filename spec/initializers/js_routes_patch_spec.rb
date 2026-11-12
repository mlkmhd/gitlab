# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'JsRoutes nil query parameter patch', feature_category: :tooling do
  subject(:core) { JsRoutes.generate(exclude: [/.*/]) }

  before do
    # js-routes switches to the new behavior from Rails 8.1
    allow(Rails).to receive(:version).and_return('8.1.0')
  end

  it 'keeps serializing nil query parameters with an equals sign' do
    expect(core).to match(/this\.is_not_nullable\(value\) \|\|\s+true\s+\?/)
  end
end
