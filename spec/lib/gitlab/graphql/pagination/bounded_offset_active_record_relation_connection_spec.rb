# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Graphql::Pagination::BoundedOffsetActiveRecordRelationConnection, feature_category: :api do
  let_it_be(:users) { create_list(:user, 5) }

  let(:context) { instance_double(GraphQL::Query::Context, schema: GitlabSchema, :[] => nil, namespace: {}) }
  let(:items) { User.id_in(users).order(:id) }
  let(:reversed_items) { -> { User.id_in(users).order(id: :desc) } }

  def bounded_connection(**args)
    described_class.new(items, reversed_items: reversed_items, default_count_limit: 3, context: context, **args)
  end

  def cursor(offset)
    GitlabSchema.cursor_encoder.encode(offset.to_s, nonce: true)
  end

  def page(connection)
    {
      nodes: connection.nodes,
      cursors: connection.nodes.map { |node| connection.cursor_for(node) },
      has_previous_page: connection.has_previous_page,
      has_next_page: connection.has_next_page
    }
  end

  def count_queries(&block)
    ActiveRecord::QueryRecorder.new(&block).log.grep(/SELECT COUNT/)
  end

  it 'exposes the default count limit' do
    expect(bounded_connection.default_count_limit).to eq(3)
  end

  it_behaves_like 'a connection with collection methods' do
    let(:connection) { bounded_connection }
  end

  it_behaves_like 'a redactable connection' do
    let(:connection) { bounded_connection(max_page_size: 10) }
    let(:unwanted) { users.second }
  end

  describe 'pages' do
    using RSpec::Parameterized::TableSyntax

    where(:args) do
      [
        [{}],
        [{ first: 2 }],
        [{ first: 5 }],
        [{ first: 7 }],
        [{ first: 2, after: 2 }],
        [{ first: 2, after: 3 }],
        [{ first: 2, after: 5 }],
        [{ first: 2, before: 4 }],
        [{ last: 2 }],
        [{ last: 5 }],
        [{ last: 7 }],
        [{ last: 2, before: 4 }],
        [{ last: 2, after: 1 }],
        [{ last: 2, after: 3 }],
        [{ last: 2, after: 4 }],
        [{ last: 2, after: 5 }],
        [{ first: 5, max_page_size: 2 }],
        [{ last: 5, max_page_size: 2 }],
        [{ max_page_size: nil }], # no page size: served by the offset connection
        [{ first: 3, last: 2 }] # served by the offset connection
      ]
    end

    with_them do
      let(:connection_args) do
        cursor_args = %i[after before]

        args.to_h { |key, value| [key, cursor_args.include?(key) ? cursor(value) : value] }
      end

      let(:offset_connection) do
        Gitlab::Graphql::Pagination::OffsetActiveRecordRelationConnection
          .new(items, context: context, **connection_args)
      end

      it 'matches the offset connection' do
        expect(page(bounded_connection(**connection_args))).to eq(page(offset_connection))
      end

      context 'without rows' do
        let(:items) { User.none }
        let(:reversed_items) { -> { User.none } }

        it 'matches the offset connection' do
          expect(page(bounded_connection(**connection_args))).to eq(page(offset_connection))
        end
      end
    end
  end

  describe '#has_next_page' do
    it 'answers from the page without a count' do
      connection = bounded_connection(first: 2, after: cursor(2))

      expect(count_queries { expect(connection.has_next_page).to be(true) }).to be_empty
    end
  end

  describe 'last page' do
    let(:connection) { bounded_connection(last: 2) }

    it 'reads the nodes and previous page without a count' do
      queries = count_queries do
        expect(connection.nodes).to eq(users.last(2))
        expect(connection.has_previous_page).to be(true)
      end

      expect(queries).to be_empty
    end

    it 'counts once for its cursors' do
      expect(count_queries { connection.nodes.each { |node| connection.cursor_for(node) } }.size).to eq(1)
    end

    context 'with an after cursor' do
      it 'reads the nodes and previous page without a count when more rows follow the cursor than the page holds' do
        connection = bounded_connection(last: 2, after: cursor(1))

        queries = count_queries do
          expect(connection.nodes).to eq(users.last(2))
          expect(connection.has_previous_page).to be(true)
        end

        expect(queries).to be_empty
      end

      it 'builds cursors without a count when the page holds every row after the cursor' do
        connection = bounded_connection(last: 2, after: cursor(3))

        expect(count_queries { connection.nodes.each { |node| connection.cursor_for(node) } }).to be_empty
      end
    end

    context 'when the page holds every row' do
      let(:connection) { bounded_connection(last: 5) }

      it 'builds cursors without a count' do
        expect(count_queries { connection.nodes.each { |node| connection.cursor_for(node) } }).to be_empty
      end
    end
  end
end
