# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Members::UnassignIssuables::BaseService, feature_category: :user_management do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:group) { create(:group) }
  let_it_be(:user) { create(:user) }

  subject(:service) { described_class.new(user, group, user) }

  where(:hook, :args) do
    :assignee_class | []
    :id_column      | []
    :issuable_for   | [nil]
    :save_assignees | [nil, []]
  end

  with_them do
    it 'must be implemented by a subclass' do
      expect { service.send(hook, *args) }.to raise_error(NotImplementedError)
    end
  end

  it 'requires subclasses to implement payload' do
    expect { service.send(:payload, processed: 0, skipped: 0, still_assigned: 0) }.to raise_error(NotImplementedError)
  end
end
