# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClickHouse::HttpClient, feature_category: :database do
  describe '.log_comment' do
    it 'serializes the available context attributes and omits the rest' do
      user = build_stubbed(:user, id: 42)
      group = build_stubbed(:group, id: 7, path: 'gitlab-org', traversal_ids: [7])

      Labkit::Correlation::CorrelationId.use_id('cid1') do
        Gitlab::ApplicationContext.with_context(user: user, namespace: group, feature_category: 'database') do
          expect(Namespace).not_to receive(:find_by_full_path)

          expect(Gitlab::Json::SafeParser.parse(described_class.log_comment)).to eq(
            'correlation_id' => 'cid1',
            'user_id' => 42,
            'root_namespace_id' => 7,
            'application' => Gitlab.process_name,
            'feature_category' => 'database'
          )
        end
      end
    end
  end

  describe 'root_namespace_id' do
    let_it_be(:root) { create(:group) }
    let_it_be(:subgroup) { create(:group, parent: root) }
    let_it_be(:project) { create(:project, group: subgroup) }

    def emitted
      Gitlab::Json::SafeParser.parse(described_class.log_comment)['root_namespace_id']
    end

    it 'is taken from the context when a namespace is present' do
      Gitlab::ApplicationContext.with_context(namespace: subgroup) do
        expect(emitted).to eq(root.id)
      end
    end

    it 'is omitted when only a project is present and its namespace is not loaded' do
      Gitlab::ApplicationContext.with_context(project: Project.find(project.id)) do
        expect(emitted).to be_nil
      end
    end

    it 'is omitted when there is no namespace or project' do
      Gitlab::ApplicationContext.with_context(feature_category: 'database') do
        expect(Gitlab::Json::SafeParser.parse(described_class.log_comment))
          .not_to have_key('root_namespace_id')
      end
    end
  end

  describe '.build_post_proc' do
    it 'posts to a URL carrying the escaped log comment' do
      allow(described_class).to receive(:log_comment).and_return('{"correlation_id":"cid 1"}')
      response = instance_double(HTTParty::Response, body: '{}', code: 200, headers: {})

      expect(Gitlab::HTTP).to receive(:post)
        .with('http://ch:8123/?database=main&log_comment=%7B%22correlation_id%22%3A%22cid+1%22%7D', anything)
        .and_return(response)

      described_class.build_post_proc.call('http://ch:8123/?database=main', {}, { 'query' => 'SELECT 1' })
    end

    describe 'empty response body' do
      let(:post_proc) { described_class.build_post_proc }
      let(:body) { '' }
      let(:code) { 200 }
      let(:message) { 'Empty response for a select limited by the guest_web_request rule' }

      subject(:response) { post_proc.call('http://ch:8123/', {}, { 'query' => 'SELECT 1' }) }

      before do
        allow(Gitlab::Runtime).to receive(:puma?).and_return(true)
        allow(Gitlab::HTTP).to receive(:post)
          .and_return(instance_double(HTTParty::Response, body: body, code: code, headers: {}))
      end

      context 'when the query is a limited select' do
        before do
          allow(ClickHouse::ReadOnlyMarker).to receive(:active?).and_return(true)
        end

        it 'returns a failed response naming the rule' do
          expect(response).not_to be_success
          expect(response.body).to eq(message)
        end

        context 'when the body is not empty' do
          let(:body) { '{"meta":[],"data":[],"rows":0}' }

          it { is_expected.to be_success }
        end

        context 'when no limit rule applies' do
          before do
            stub_feature_flags(click_house_guest_query_limits: false)
          end

          it 'passes the empty body through' do
            expect(response).to be_success
            expect(response.body).to eq('')
          end
        end
      end

      context 'when the query is not a select' do
        it { is_expected.to be_success }
      end

      it 'makes ClickHouse::Client.select raise DatabaseError', :click_house do
        expect { ClickHouse::Client.select('SELECT 1', :main) }
          .to raise_error(ClickHouse::Client::DatabaseError, message)
      end
    end
  end

  describe '.with_query_settings' do
    let(:url) { 'http://ch:8123/?database=main' }
    let(:counter) { instance_double(Prometheus::Client::Counter, increment: nil) }

    def query_params(result)
      Rack::Utils.parse_query(URI.parse(result).query)
    end

    before do
      allow(described_class).to receive(:select_counter).and_return(counter)
      allow(Gitlab).to receive(:process_name).and_return('web')
      allow(Gitlab::Runtime).to receive(:puma?).and_return(true)
    end

    context 'when the query is not a select' do
      it 'adds only the log comment' do
        expect(query_params(described_class.with_query_settings(url)).keys)
          .to contain_exactly('database', 'log_comment')
        expect(counter).not_to have_received(:increment)
      end
    end

    context 'when the query is a select' do
      before do
        allow(ClickHouse::ReadOnlyMarker).to receive(:active?).and_return(true)
      end

      it 'adds the guest limits and counts the select' do
        Gitlab::ApplicationContext.with_context(feature_category: 'database') do
          expect(query_params(described_class.with_query_settings(url))).to include(
            'max_rows_to_read' => '10000000',
            'max_bytes_to_read' => '1073741824',
            'read_overflow_mode' => 'break',
            'max_execution_time' => '5',
            'timeout_overflow_mode' => 'break',
            'readonly' => '2'
          )
        end

        expect(counter).to have_received(:increment).with(
          application: 'web', feature_category: 'database', query_limit_type: 'guest_web_request'
        )
      end

      it 'adds no limits for an authenticated request' do
        Gitlab::ApplicationContext.with_context(user: build_stubbed(:user)) do
          expect(query_params(described_class.with_query_settings(url))).not_to have_key('max_rows_to_read')
        end

        expect(counter).to have_received(:increment).with(
          application: 'web', feature_category: 'unknown', query_limit_type: 'none'
        )
      end

      context 'when click_house_guest_query_limits is disabled' do
        before do
          stub_feature_flags(click_house_guest_query_limits: false)
        end

        it 'adds no limits and counts the select as none' do
          expect(query_params(described_class.with_query_settings(url))).not_to have_key('max_rows_to_read')
          expect(counter).to have_received(:increment).with(hash_including(query_limit_type: 'none'))
        end
      end
    end
  end

  describe 'guest select against ClickHouse', :click_house do
    before do
      allow(Gitlab::Runtime).to receive(:puma?).and_return(true)
    end

    it 'applies the limits to select only' do
      result = ClickHouse::Client.select(
        "SELECT getSetting('max_rows_to_read') AS rows, getSetting('read_overflow_mode') AS mode", :main
      )

      expect(result).to eq([{ 'rows' => 10_000_000, 'mode' => 'break' }])
    end

    it 'rejects writes from a guest select' do
      expect { ClickHouse::Client.select('INSERT INTO events (id) VALUES (1)', :main) }
        .to raise_error(ClickHouse::Client::DatabaseError, /readonly mode/)
    end
  end
end
