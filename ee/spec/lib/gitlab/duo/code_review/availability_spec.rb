# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::CodeReview::Availability, feature_category: :dap_code_review do
  using RSpec::Parameterized::TableSyntax

  shared_examples 'a method delegated to the availability class' do |method_name|
    subject(:available) { ::Gitlab::Duo::CodeReview.public_send(method_name, container) }

    where(:container_factory, :availability_class) do
      :project             | Gitlab::Duo::CodeReview::Availability::Project
      :group               | Gitlab::Duo::CodeReview::Availability::Namespace
      :namespace           | Gitlab::Duo::CodeReview::Availability::Namespace
      :application_setting | Gitlab::Duo::CodeReview::Availability::Instance
    end

    with_them do
      let(:container) { build_stubbed(container_factory) }

      it 'delegates to the availability class for the container' do
        expect_next_instance_of(availability_class, container) do |instance|
          expect(instance).to receive(method_name).and_return(true)
        end

        expect(available).to be(true)
      end
    end

    context 'with an unsupported container' do
      let(:container) { build_stubbed(:user) }

      it 'raises an error' do
        expect { available }.to raise_error(ArgumentError, 'Unsupported container type: User')
      end
    end
  end

  describe '.available?' do
    it_behaves_like 'a method delegated to the availability class', :available?
  end

  describe '.automatic_review_available?' do
    it_behaves_like 'a method delegated to the availability class', :automatic_review_available?
  end

  describe '.depth_settings_available?' do
    it_behaves_like 'a method delegated to the availability class', :depth_settings_available?
  end

  describe '.default_depth' do
    it_behaves_like 'a method delegated to the availability class', :default_depth
  end

  describe '.decisions_settings_available?' do
    it_behaves_like 'a method delegated to the availability class', :decisions_settings_available?
  end
end
