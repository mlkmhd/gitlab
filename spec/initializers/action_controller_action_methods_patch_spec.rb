# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'ActionController action_methods patch', feature_category: :rails_platform do
  # AbstractController::Base.action_methods and AbstractController::UrlFor::ClassMethods#action_methods
  # as of Rails 8.0 and 8.1, which the patch replaces.
  def rails_action_methods(controller)
    methods = controller.public_instance_methods(true) - controller.send(:internal_methods)
    methods.concat(controller.public_instance_methods(false)) if Rails.gem_version < Gem::Version.new('8.1')
    methods.map!(&:to_s)
    methods = methods.to_set

    controller._routes ? methods - controller._routes.named_routes.helper_names : methods
  end

  it 'is applied' do
    expect(ActionController::Base.singleton_class.ancestors)
      .to include(ActionControllerActionMethodsPatch::ClassMethods)
  end

  it 'computes the same action methods as Rails' do
    [ApplicationController, ProjectsController, Projects::IssuesController, Admin::UsersController,
      Groups::MilestonesController, Profiles::NotificationsController].each do |controller|
      controller.clear_action_methods!

      expect(controller.action_methods).to eq(rails_action_methods(controller)), controller.name
    end
  end

  it 'excludes the url helpers and keeps the actions' do
    expect(ProjectsController.action_methods).to include('show', 'edit', 'update')
    expect(ProjectsController.action_methods).not_to include('project_path', 'root_url')
  end

  it 'excludes the helpers of the route set a controller includes' do
    routes = ActionDispatch::Routing::RouteSet.new
    routes.draw { get 'things', to: 'things#index', as: :things }

    controller = Class.new(ApplicationController) do
      include routes.url_helpers
      def index; end
    end
    stub_const('PatchSpecController', controller)

    expect(controller._routes).to eq(routes)
    expect(controller.public_instance_methods).to include(:things_path, :things_url)
    expect(controller.action_methods).to include('index')
    expect(controller.action_methods).not_to include('things_path', 'things_url')
    expect(controller.action_methods).to eq(rails_action_methods(controller))
  end
end
