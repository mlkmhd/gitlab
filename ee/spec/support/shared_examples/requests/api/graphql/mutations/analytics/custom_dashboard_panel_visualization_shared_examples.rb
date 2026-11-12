# frozen_string_literal: true

# Shared validation coverage for custom dashboard mutations that accept panel
# visualizations. A panel's `visualization` is an inline config object,
# validated against the dashboard JSON schema.
#
# The including context must:
#   - define `mutation` and `mutation_response`
#   - define `user`
#   - build the mutation `variables` so the dashboard config's panels come from
#     the `panels` let defined here
RSpec.shared_examples 'a custom dashboard mutation validating panel visualizations' do
  shared_examples 'rejecting the panel' do
    it 'returns a validation error' do
      post_graphql_mutation(mutation, current_user: user)

      expect(mutation_response['dashboard']).to be_nil
      expect(mutation_response['errors']).to include(a_string_matching(%r{/panels/0}))
    end
  end

  context 'when a panel visualization is an invalid config object' do
    let(:panels) do
      [{ title: 'Broken Panel', visualization: { type: 'NotAChartType' }, gridAttributes: { width: 4, height: 2 } }]
    end

    it_behaves_like 'rejecting the panel'
  end

  context 'when a panel supplies no visualization' do
    let(:panels) { [{ title: 'Empty Panel', gridAttributes: { width: 4, height: 2 } }] }

    it_behaves_like 'rejecting the panel'
  end

  context 'when a panel references a visualization by name' do
    let(:panels) do
      [{ title: 'Referenced Panel', visualization: 'number', gridAttributes: { width: 4, height: 2 } }]
    end

    it_behaves_like 'rejecting the panel'
  end
end
