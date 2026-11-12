# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'ActionDispatch::Journey::Router Patch', feature_category: :database do
  before do
    load Rails.root.join('config/initializers/action_dispatch_journey_router.rb')
  end

  describe '#filter_routes' do
    let(:set) { ActionDispatch::Routing::RouteSet.new }

    before do
      stub_const('PagesController', Class.new(ApplicationController))

      set.draw do
        get '*namespace_id/:project_id/*all',
          to: 'pages#show',
          constraints: {
            namespace_id: Gitlab::PathRegex.full_namespace_route_regex,
            project_id: Gitlab::PathRegex.project_route_regex
          }

        get '/api/v4/projects', to: 'pages#index'
      end
    end

    context 'when a route with lookaround constraints is a candidate but does not match' do
      it 'skips it and routes to the matching route' do
        params = set.recognize_path('/api/v4/projects', method: :get)

        expect(params).to eq(controller: 'pages', action: 'index')
      end

      it 'raises a routing error when no route matches' do
        expect { set.recognize_path('/api/v4/groups', method: :get) }
          .to raise_error(ActionController::RoutingError)
      end
    end

    it 'still routes paths that match a route with lookaround constraints' do
      params = set.recognize_path('/group/project/anything', method: :get)

      expect(params).to include(controller: 'pages', action: 'show', namespace_id: 'group', project_id: 'project')
    end
  end
end
