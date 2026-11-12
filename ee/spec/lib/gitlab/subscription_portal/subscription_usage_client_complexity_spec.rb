# frozen_string_literal: true

require 'spec_helper'

# graphql-ruby multiplies a connection's node selections by the page size, so one more field on a
# paginated query can exceed CustomersDot's limit for self-managed without any GitLab spec
# noticing. Estimating the complexity here surfaces that in review instead of production.
RSpec.describe Gitlab::SubscriptionPortal::SubscriptionUsageClient, 'CustomersDot query complexity',
  feature_category: :consumables_cost_management do
  # PaymentAppSchema::DEFAULT_MAX_COMPLEXITY in CustomersDot: license-key requests have no
  # current_user, so this is the limit self-managed instances get.
  customers_dot_max_complexity = 200

  # Largest page GitLab asks CustomersDot for on each connection, or CustomersDot's
  # `max_page_size` when GitLab does not pass `first`/`last` (graphql-ruby then uses it).
  page_sizes = {
    'consumers' => ::GitlabSubscriptions::SubscriptionsUsage::UserUsage::MAX_USERS_PER_PAGE,
    # Dashboard page size. GitLab forwards an API caller's `first` unclamped and CustomersDot computes
    # complexity from it, so a larger page is rejected today: https://gitlab.com/gitlab-org/gitlab/-/work_items/638870
    'events' => 20,
    'userBudgetCapOverrides' => 20,
    'blockedStatuses' => 20,
    'sessions' => described_class::SESSIONS_PAGE_SIZE,
    'sessionNamespaces' => described_class::SESSION_NAMESPACES_PAGE_SIZE
  }.freeze

  # Connections CustomersDot caps with a `complexity:` proc instead of multiplying by the page
  # size: UsageType.sessions, QueryType.sessionNamespaces and, since
  # https://gitlab.com/gitlab-org/customers-gitlab-com/-/merge_requests/17862, UsersUsageType.consumers.
  capped_connections = {
    'consumers' => 20,
    'sessions' => 20,
    'sessionNamespaces' => 20
  }.freeze

  # Mirrors GraphQL::Schema::Field#calculate_complexity for a schema where every field has the
  # default complexity of 1: a field costs 1 plus its selections; a connection costs
  # page size * node selections, plus 1 per direct child and 1 per pageInfo selection, plus 1.
  estimator = Module.new do
    def self.of(query_text, page_sizes:, capped_connections:)
      operation = GraphQL.parse(query_text).definitions.first

      selections_complexity(operation.selections, page_sizes, capped_connections)
    end

    def self.selections_complexity(selections, page_sizes, capped)
      selections.sum { |field| field_complexity(field, page_sizes, capped) }
    end

    def self.field_complexity(field, page_sizes, capped)
      return 1 + selections_complexity(field.selections, page_sizes, capped) unless connection?(field)

      items = 0
      metadata = 0

      field.selections.each do |child|
        metadata += 1

        if child.name.in?(%w[nodes edges])
          items += selections_complexity(child.selections, page_sizes, capped)
        else
          metadata += child.selections.size
        end
      end

      page_size = page_sizes.fetch(field.name) do
        raise "Add `#{field.name}` to page_sizes: the largest page GitLab requests on this connection"
      end

      subfields = (page_size * items) + metadata
      cap = capped[field.name]

      cap ? [subfields, cap].min : subfields + 1
    end

    def self.connection?(field)
      field.selections.any? { |child| child.name.in?(%w[nodes edges]) }
    end
  end

  queries = described_class.constants.grep(/_(QUERY|MUTATION)\z/).sort

  it 'reproduces the complexity CustomersDot reported for the uncapped consumers page' do
    # https://gitlab.com/gitlab-org/gitlab/-/work_items/638822: 20 consumers * 10 node fields.
    complexity = estimator.of(described_class::GET_CONSUMERS_QUERY, page_sizes: page_sizes, capped_connections: {})

    expect(complexity).to eq(210)
  end

  it 'covers every query and mutation the client defines' do
    expect(queries).to include(:GET_CONSUMERS_QUERY, :GET_USER_EVENTS_QUERY, :GET_SESSIONS_QUERY)
  end

  queries.each do |constant|
    it "keeps #{constant} within the CustomersDot limit for license-key requests" do
      complexity = estimator.of(
        described_class.const_get(constant, false), page_sizes: page_sizes, capped_connections: capped_connections
      )

      expect(complexity).to be <= customers_dot_max_complexity,
        "#{constant} has an estimated complexity of #{complexity}, above CustomersDot's #{customers_dot_max_complexity}"
    end
  end
end
