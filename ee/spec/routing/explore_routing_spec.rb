# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Explore::AiCatalogController, "routing", feature_category: :ai_catalog_curation do
  specify "skills to #index" do
    expect(get("/explore/ai-catalog/skills")).to route_to('explore/ai_catalog#index')
  end

  specify "a single skill to #index" do
    expect(get("/explore/ai-catalog/skills/1")).to route_to('explore/ai_catalog#index', id: '1')
  end
end

RSpec.describe Explore::AnalyticsDashboardsController, "routing",
  feature_category: :custom_dashboards_foundation do
  # The FOSS counterpart asserting this route does not resolve lives in
  # spec/routing/explore_routing_spec.rb.
  specify "to #index" do
    expect(get("/explore/analytics_dashboards")).to route_to('explore/analytics_dashboards#index')
  end

  specify "to #index with a vue route" do
    expect(get("/explore/analytics_dashboards/duo_and_sdlc_trends")).to route_to(
      'explore/analytics_dashboards#index',
      vueroute: 'duo_and_sdlc_trends'
    )
  end
end
