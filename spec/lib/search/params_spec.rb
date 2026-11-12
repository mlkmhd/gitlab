# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::Params, feature_category: :global_search do
  subject(:search_params) { described_class.new(params, detect_abuse: detect_abuse) }

  let(:search) { 'search' }
  let(:group_id) { 123 }
  let(:params) { ActionController::Parameters.new(group_id: 123, search: search) }
  let(:detect_abuse) { true }

  describe 'detect_abuse conditional' do
    it 'does not call AbuseDetection' do
      expect(Gitlab::Search::AbuseDetection).not_to receive(:new)
      described_class.new(params, detect_abuse: false)
    end

    it 'uses AbuseDetection by default' do
      expect(Gitlab::Search::AbuseDetection).to receive(:new).at_least(:once).and_call_original

      search_params
    end
  end

  describe '#[]' do
    it 'feels like regular params' do
      expect(search_params[:group_id]).to eq(params[:group_id])
    end

    it 'has indifferent access' do
      params = described_class.new({ 'search' => search, group_id: group_id })
      expect(params['group_id']).to eq(group_id)
      expect(params[:search]).to eq(search)
    end

    it 'also works on attr_reader attributes' do
      expect(search_params[:query_string]).to eq(search_params.query_string)
    end
  end

  describe '#slice' do
    let(:controller_params) { ActionController::Parameters.new(group_id: 123, search: search, exclude_forks: true) }
    let(:params) { described_class.new(controller_params) }

    it 'returns a new params object with only the specified keys' do
      sliced = params.slice(:exclude_forks, :group_id, :project_id)

      expect(sliced).to be_a(Hash)
      expect(sliced[:exclude_forks]).to be(true)
      expect(sliced[:group_id]).to eq(123)
      expect(sliced[:project_id]).to be_nil
    end

    it 'works with string keys' do
      sliced = params.slice('exclude_forks', 'group_id', 'project_id')

      expect(sliced).to be_a(Hash)
      expect(sliced['exclude_forks']).to be(true)
      expect(sliced['group_id']).to eq(123)
      expect(sliced['project_id']).to be_nil
    end

    it 'handles mixed string and symbol keys' do
      sliced = params.slice(:exclude_forks, 'group_id')

      expect(sliced).to be_a(Hash)
      expect(sliced[:exclude_forks]).to be(true)
      expect(sliced[:group_id]).to eq(123)
      expect(sliced[:project_id]).to be_nil
    end
  end

  describe '#query_string' do
    let(:term) { 'term' }

    it "uses 'search' parameter" do
      params = described_class.new({ search: search })
      expect(params.query_string).to eq(search)
    end

    it "uses 'term' parameter" do
      params = described_class.new({ term: term })
      expect(params.query_string).to eq(term)
    end

    it "prioritizes 'search' over 'term'" do
      params = described_class.new({ search: search, term: term })
      expect(params.query_string).to eq(search)
    end

    it 'strips surrounding whitespace from query string' do
      params = described_class.new({ search: "     #{search}           " })
      expect(params.query_string).to eq(search)
    end
  end

  describe '#validate' do
    context 'when detect_abuse is disabled' do
      let(:detect_abuse) { false }

      it 'does NOT validate AbuseDetector' do
        expect(Gitlab::Search::AbuseDetection).not_to receive(:new)
        search_params.validate
      end
    end

    it 'validates AbuseDetector on validation' do
      expect(Gitlab::Search::AbuseDetection).to receive(:new).at_least(:once).and_call_original
      search_params.validate
    end

    context 'when query has too many terms' do
      let(:search) { Array.new(::Search::Params::SEARCH_TERM_LIMIT + 1, 'a').join(' ') }

      it { is_expected.not_to be_valid }
    end

    context 'when query is too long' do
      let(:search) { 'a' * (::Search::Params::SEARCH_CHAR_LIMIT + 1) }

      it { is_expected.not_to be_valid }
    end

    context 'when a date param is malformed' do
      let(:params) { ActionController::Parameters.new(group_id: 123, search: search, created_after: '2026-99-99') }

      it { is_expected.not_to be_valid }

      it 'adds an error naming the offending param' do
        search_params.validate

        expect(search_params.errors[:created_after]).to include('must be a valid date')
      end
    end

    context 'when an assignee ID filter is oversized' do
      let(:max) { ::Search::Params::MAX_ASSIGNEE_IDS }
      let(:params) do
        ActionController::Parameters.new(
          group_id: 123, search: search, assignee_ids: (1..(max + 1)).map(&:to_s)
        )
      end

      it { is_expected.not_to be_valid }

      it 'adds an error naming the offending param and the limit' do
        search_params.validate

        expect(search_params.errors[:assignee_ids]).to include("has too many IDs (maximum is #{max})")
      end

      it 'leaves the values in place so the caller fails closed rather than searching a truncated list' do
        expect(search_params[:assignee_ids].size).to eq(max + 1)
      end
    end

    context 'when assignee_ids is a scalar, not an array' do
      let(:params) { ActionController::Parameters.new(group_id: 123, search: search, assignee_ids: '5') }

      it 'wraps it in an array so a backend filter builder never receives a bare scalar' do
        expect(search_params[:assignee_ids]).to eq(['5'])
      end
    end

    context 'when not[assignee_ids] is a scalar, not an array' do
      let(:params) do
        ActionController::Parameters.new(group_id: 123, search: search, not: { assignee_ids: '5' })
      end

      it 'wraps it in an array after the not[] conversion' do
        expect(search_params[:not_assignee_ids]).to eq(['5'])
      end
    end
  end

  describe 'coerces date params' do
    using RSpec::Parameterized::TableSyntax

    let(:params) { ActionController::Parameters.new(group_id: 123, search: search, **{ date_key => input }) }

    around do |example|
      Time.use_zone('UTC') { example.run }
    end

    # Every malformed shape behaves identically, whichever way ActiveSupport
    # fails on it; a blank value is absent rather than an error.
    where(:date_key, :input, :expected_value, :expected_valid, :why) do
      :created_after | '2026-01-31' | lazy { Time.zone.local(2026, 1, 31) } | true | 'valid date'
      :created_before | '2026-01-31T08:00:00Z' | lazy { Time.zone.local(2026, 1, 31, 8) } | true | 'valid datetime'
      :created_after | '2026-99-99' | nil | false | 'out of range, in_time_zone RAISES'
      :updated_before | '2026-13-01' | nil | false | 'month out of range, in_time_zone RAISES'
      :created_before | 'not-a-date' | nil | false | 'unparseable, in_time_zone returns nil'
      :updated_after | 'garbage 2026' | nil | false | 'unparseable, in_time_zone RAISES'
      :updated_before | '99999999999999' | nil | false | 'out of range, in_time_zone RAISES'
      :created_after | '' | nil | true | 'blank is absent, not an error'
      :updated_after | '   ' | nil | true | 'whitespace is absent, not an error'
      :created_after | '2026-01-01T10:00Z' | nil | false | 'ISO 8601, no seconds, time dropped'
      :updated_before | '2026-01-01T99:99:99Z' | nil | false | 'malformed datetime, not a plain date'
      :created_after | 'March' | nil | false | 'lenient month name, not accepted'
      :updated_before | '1/2/3' | nil | false | 'lenient slash-separated date, not accepted'
    end

    with_them do
      it 'coerces or rejects the value' do
        expect(search_params[date_key]).to eq(expected_value)
        expect(search_params.valid_date_params?).to be(expected_valid)
      end

      it 'never leaves a raw String in params for a backend to receive' do
        expect(search_params[date_key]).not_to be_a(String)
      end
    end

    context 'when the value is already a Time' do
      let(:date_key) { :created_after }
      let(:input) { Time.zone.local(2026, 5, 1) }

      it 'passes it through untouched' do
        expect(search_params[:created_after]).to eq(input)
        expect(search_params).to be_valid
      end
    end

    context 'when the value is already a Date' do
      let(:date_key) { :created_after }
      let(:input) { Date.new(2026, 5, 1) }

      it 'widens it to midnight in the request zone' do
        expect(search_params[:created_after]).to be_a(ActiveSupport::TimeWithZone)
        expect(search_params[:created_after]).to eq(Time.zone.local(2026, 5, 1))
        expect(search_params).to be_valid
      end
    end

    context 'when an offset-less datetime is parsed under a non-UTC zone' do
      let(:date_key) { :created_after }
      let(:input) { '2026-01-31T09:00:00' }

      around do |example|
        Time.use_zone('Asia/Tokyo') { example.run }
      end

      it 'reads the time in the request zone, not the server zone' do
        expect(search_params[:created_after]).to eq(Time.zone.local(2026, 1, 31, 9))
        expect(search_params).to be_valid
      end
    end

    context 'when several date params are malformed' do
      let(:params) do
        ActionController::Parameters.new(
          group_id: 123, search: search,
          created_after: '2026-99-99', updated_before: 'not-a-date', created_before: '2026-01-31'
        )
      end

      let(:date_key) { :created_after }
      let(:input) { nil }

      it 'reports each offending param and keeps the valid one' do
        expect(search_params.invalid_date_params).to contain_exactly(:created_after, :updated_before)
        expect(search_params[:created_before]).to eq(Time.zone.local(2026, 1, 31))
      end
    end

    context 'when no date param is given' do
      let(:params) { ActionController::Parameters.new(group_id: 123, search: search) }
      let(:date_key) { :created_after }
      let(:input) { nil }

      it 'is valid and adds no date keys' do
        expect(search_params.valid_date_params?).to be(true)
        expect(search_params[:created_after]).to be_nil
      end
    end
  end

  describe '#valid_assignee_ids?' do
    using RSpec::Parameterized::TableSyntax

    let(:max) { ::Search::Params::MAX_ASSIGNEE_IDS }
    let(:params) { ActionController::Parameters.new(group_id: 123, search: search, **{ key => value }) }

    # `not` is nested under a `not` hash by the caller and flattened to
    # not_assignee_ids by #convert_not_params, so the limit has to be checked
    # after that conversion, on raw_params.
    where(:key, :size, :expected) do
      :assignee_ids     | lazy { max }     | true
      :assignee_ids     | lazy { max + 1 } | false
      :not_assignee_ids | lazy { max + 1 } | false
      :assignee_ids     | 1                | true
    end

    with_them do
      let(:value) { (1..size).map(&:to_s) }

      it { expect(search_params.valid_assignee_ids?).to be(expected) }
    end

    context 'when the filter is absent' do
      let(:params) { ActionController::Parameters.new(group_id: 123, search: search) }

      it { expect(search_params.valid_assignee_ids?).to be(true) }
    end

    context 'when the oversized list arrives inside the not hash' do
      let(:params) do
        ActionController::Parameters.new(
          group_id: 123, search: search, not: { assignee_ids: (1..(max + 1)).map(&:to_s) }
        )
      end

      it 'is still rejected after not-param flattening' do
        expect(search_params.valid_assignee_ids?).to be(false)
        expect(search_params.oversized_assignee_id_params).to contain_exactly(:not_assignee_ids)
      end
    end

    context 'when assignee_ids is a Hash rather than a list, e.g. assignee_ids[0]=5' do
      let(:params) do
        ActionController::Parameters.new(
          group_id: 123, search: search, assignee_ids: { '0' => '5', '1' => '7' }
        )
      end

      it 'is rejected rather than silently wrapped as a single-element array' do
        expect(search_params.valid_assignee_ids?).to be(false)
        expect(search_params.malformed_assignee_id_params).to contain_exactly(:assignee_ids)
      end

      it 'adds an error naming the offending param' do
        search_params.validate

        expect(search_params.errors[:assignee_ids]).to include('must be a list of IDs')
      end
    end

    context 'when not[assignee_ids] is a Hash rather than a list' do
      let(:params) do
        ActionController::Parameters.new(
          group_id: 123, search: search, not: { assignee_ids: { '0' => '5' } }
        )
      end

      it 'is still rejected after not-param flattening' do
        expect(search_params.valid_assignee_ids?).to be(false)
        expect(search_params.malformed_assignee_id_params).to contain_exactly(:not_assignee_ids)
      end
    end
  end

  describe '#abusive?' do
    let(:abuse_detection) { instance_double(Gitlab::Search::AbuseDetection) }

    context 'when detect_abuse is false' do
      let(:detect_abuse) { false }

      it 'is not considered as abusive' do
        expect(abuse_detection).not_to receive(:errors)
        expect(search_params).not_to be_abusive
      end
    end

    context 'when detect_abuse is true' do
      before do
        allow(search_params).to receive(:abuse_detection).and_return abuse_detection
        allow(abuse_detection).to receive(:errors).and_return abuse_errors
      end

      context 'when there are abuse validation errors' do
        let(:abuse_errors) { { foo: ['bar'] } }

        it 'is considered abusive' do
          expect(search_params).to be_abusive
        end
      end

      context 'when there are NOT any abuse validation errors' do
        let(:abuse_errors) { {} }

        context 'and there are other validation errors' do
          it 'is NOT considered abusive' do
            allow(search_params).to receive(:valid?) do
              search_params.errors.add :project_id, 'validation error unrelated to abuse'
              false
            end

            expect(search_params).not_to be_abusive
          end
        end

        context 'and there are NO other validation errors' do
          it 'is NOT considered abusive' do
            allow(search_params).to receive(:valid?).and_return(true)

            expect(search_params).not_to be_abusive
          end
        end
      end
    end
  end

  describe '#email_lookup?' do
    it 'is true if at least 1 word in search is an email' do
      expect(described_class.new({ search: 'email@example.com' })).to be_email_lookup
      expect(described_class.new({ search: 'foo email@example.com bar' })).to be_email_lookup
      expect(described_class.new({ search: 'foo bar' })).not_to be_email_lookup
    end
  end

  describe 'converts boolean params' do
    using RSpec::Parameterized::TableSyntax

    shared_context 'with inputs' do
      where(:input, :expected) do
        '0'     | false
        '1'     | true
        'yes'   | true
        'no'    | false
        'true'  | true
        'false' | false
        true    | true
        false   | false
      end
    end

    described_class::BOOLEAN_PARAMS.each do |boolean_param|
      describe "for #{boolean_param}" do
        let(:params) { ActionController::Parameters.new(group_id: 123, search: search, boolean_param => input) }

        include_context 'with inputs'

        with_them do
          it 'transforms param' do
            expect(search_params[boolean_param]).to eq(expected)
          end
        end
      end
    end
  end

  describe 'converts not params' do
    using RSpec::Parameterized::TableSyntax

    where(:input, :expected_key, :expected_value) do
      { not: { source_branch: 'good-bye' } }              | 'not_source_branch' | 'good-bye'
      { not: { label_name: %w[hello-world labelName] } }  | 'not_label_name'    | %w[hello-world labelName]
      { label_name: %w[hello-world labelName] }           | 'label_name'        | %w[hello-world labelName]
      { source_branch: 'foo-bar' }                        | 'source_branch'     | 'foo-bar'
    end

    let(:params) { ActionController::Parameters.new(group_id: 123, search: search, **input) }

    with_them do
      it 'transforms param' do
        expect(search_params[expected_key]).to eq(expected_value)
      end
    end

    context 'when not param is not a hash' do
      let(:params) { ActionController::Parameters.new(group_id: 123, search: search, not: 'test') }

      it 'ignores the not param and removes it from params' do
        expect(search_params['not']).to be_nil
      end
    end
  end

  describe 'converts type param to work_item_type_ids' do
    using RSpec::Parameterized::TableSyntax

    let(:task_type) { build(:work_item_system_defined_type, :task) }
    let(:issue_type) { build(:work_item_system_defined_type, :issue) }

    where(:type_input, :expected_ids) do
      ['task']                     | lazy { [task_type.id] }
      ['TASK']                     | lazy { [task_type.id] }
      ['Task']                     | lazy { [task_type.id] }
      %w[TASK Issue]               | lazy { [task_type.id, issue_type.id] }
      ['nonexistent']              | []
      %w[task nonexistent issue]   | lazy { [task_type.id, issue_type.id] }
    end

    with_them do
      let(:params) { ActionController::Parameters.new(search: search, type: type_input) }

      it 'converts type to work_item_type_ids and removes type param' do
        expect(search_params[:work_item_type_ids]).to match_array(expected_ids)
        expect(search_params[:type]).to be_nil
      end
    end

    context 'when type param is not present' do
      let(:params) { ActionController::Parameters.new(search: search) }

      it 'does not set work_item_type_ids' do
        expect(search_params[:work_item_type_ids]).to be_nil
      end
    end
  end

  describe 'converts legacy scope names' do
    using RSpec::Parameterized::TableSyntax

    where(:input_scope, :expected_scope) do
      'issues'         | 'work_items'
      'work_items'     | 'work_items'
      'blobs'          | 'blobs'
      'merge_requests' | 'merge_requests'
      nil              | nil
      ''               | ''
    end

    let(:params) { ActionController::Parameters.new(group_id: 123, search: search, scope: input_scope) }

    with_them do
      it 'converts scope parameter' do
        expect(search_params[:scope]).to eq(expected_scope)
      end
    end

    context 'when scope is not present' do
      let(:params) { ActionController::Parameters.new(group_id: 123, search: search) }

      it 'does not add scope parameter' do
        expect(search_params[:scope]).to be_nil
      end
    end

    context 'with Hash params instead of ActionController::Parameters' do
      let(:params) { { group_id: 123, search: search, scope: 'issues' } }

      it 'converts scope parameter' do
        expect(search_params[:scope]).to eq('work_items')
      end
    end
  end
end
