# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Graphql::Pagination::WindowedArrayConnection, feature_category: :code_review_workflow do
  let(:context) { instance_double(GraphQL::Query::Context, schema: GitlabSchema, namespace: {}) }
  let(:values) { (1..10).to_a }
  let(:loads) { [] }
  let(:windowed_array) do
    Gitlab::Graphql::WindowedArray.new(values.size, ->(offset, limit) {
      loads << [offset, limit]
      values[offset, limit]
    })
  end

  def cursor(index)
    GitlabSchema.cursor_encoder.encode(index.to_s, nonce: true)
  end

  def page_of(connection)
    {
      nodes: connection.nodes,
      cursors: connection.nodes.map { |node| connection.cursor_for(node) },
      start_cursor: connection.start_cursor,
      end_cursor: connection.end_cursor,
      has_next_page: connection.has_next_page,
      has_previous_page: connection.has_previous_page
    }
  end

  where(:arguments) do
    [
      [{}],
      [{ max_page_size: 4 }],
      [{ first: 3 }],
      [{ first: 20 }],
      [{ last: 3 }],
      [{ first: 5, last: 2 }],
      [{ after: 2 }],
      [{ after: 2, first: 3 }],
      [{ after: 2, last: 3 }],
      [{ after: 10 }],
      [{ after: 12 }],
      [{ before: 5 }],
      [{ before: 5, first: 2 }],
      [{ before: 5, last: 2 }],
      [{ before: 1 }],
      [{ before: 12 }],
      [{ after: 2, before: 8 }],
      [{ after: 2, before: 8, first: 2 }],
      [{ after: 2, before: 8, last: 2 }]
    ]
  end

  with_them do
    let(:connection_arguments) do
      { context: context, max_page_size: 100 }
        .merge(arguments)
        .merge(arguments.slice(:after, :before).transform_values { |index| cursor(index) })
    end

    it 'returns the same page as ArrayConnection and loads only that window' do
      expected = page_of(Gitlab::Graphql::Pagination::ArrayConnection.new(values, **connection_arguments))
      page = page_of(described_class.new(windowed_array, **connection_arguments))

      expect(page).to eq(expected)
      expect(loads).to eq(page[:nodes].empty? ? [] : [[values.index(page[:nodes].first), page[:nodes].size]])
    end
  end

  context 'when the window has nil items' do
    def page_for(values, **arguments)
      windowed_array = Gitlab::Graphql::WindowedArray.new(values.size, ->(offset, limit) { values[offset, limit] })

      page_of(described_class.new(windowed_array, context: context, max_page_size: 100, **arguments))
    end

    it 'leaves them out of the nodes but keeps the cursors at their positions' do
      expect(page_for([1, 2, nil, 4, 5, 6], first: 4)).to eq(
        nodes: [1, 2, 4],
        cursors: [cursor(1), cursor(2), cursor(4)],
        start_cursor: cursor(1),
        end_cursor: cursor(4),
        has_next_page: true,
        has_previous_page: false
      )
    end

    it 'moves the end cursor past a window of only nil items' do
      page = page_for([nil, nil, nil, 4], first: 3)

      expect(page).to include(nodes: [], end_cursor: cursor(3), has_next_page: true)
    end
  end
end
