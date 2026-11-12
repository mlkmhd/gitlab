# frozen_string_literal: true

require 'fast_spec_helper'
RSpec.describe API::Helpers::Mcp::JsonRpc, feature_category: :mcp_server do
  let(:helper_class) do
    Class.new do
      include API::Helpers::Mcp::JsonRpc

      attr_reader :params, :rendered, :response_status, :response_body

      def initialize(params)
        @params = params
      end

      # Records what the endpoint would render instead of halting the request.
      def render_structured_api_error!(response, status)
        @rendered = { response: response, status: status }
      end

      def status(value)
        @response_status = value
      end

      def body(value)
        @response_body = value
      end
    end
  end

  def build_helper(params)
    helper_class.new(params)
  end

  describe '#jsonrpc_request_id' do
    let(:instance) { build_helper({ id: id }) }

    subject(:request_id) { instance.jsonrpc_request_id }

    context 'when the id is one the JSON-RPC spec allows' do
      where(:id) { [1, 'abc-123'] }

      with_them do
        it 'returns the id unchanged' do
          expect(request_id).to eql(id)
        end
      end
    end

    context 'when the id is any other type' do
      where(:id) { [1.5, true, nil, { 'foo' => 'bar' }, %w[a b]] }

      with_them do
        it 'returns nil so a client is never handed an id it could not have sent' do
          expect(request_id).to be_nil
        end
      end
    end
  end

  describe '#jsonrpc_notification?' do
    subject(:notification) { build_helper({ method: rpc_method }).jsonrpc_notification? }

    context 'when the method starts with the notifications/ prefix' do
      where(:rpc_method) { %w[notifications/initialized notifications/cancelled] }

      with_them do
        it { is_expected.to be(true) }
      end
    end

    context 'when the method is an ordinary request' do
      where(:rpc_method) { %w[initialize ping tools/list tools/call] }

      with_them do
        it { is_expected.to be(false) }
      end
    end
  end

  describe '#reject_missing_jsonrpc_request_id!' do
    subject(:reject) { instance.reject_missing_jsonrpc_request_id! }

    context 'when a notification has no id' do
      let(:instance) { build_helper({ method: 'notifications/initialized' }) }

      it 'accepts the request without rendering an error' do
        reject

        expect(instance.rendered).to be_nil
      end
    end

    context 'when an ordinary request has no id' do
      let(:instance) { build_helper({ method: 'ping' }) }

      it 'rejects it with HTTP 400 and the Invalid Request error code', :aggregate_failures do
        reject

        expect(instance.rendered[:status]).to eq(400)
        expect(instance.rendered[:response][:jsonrpc]).to eq('2.0')
        expect(instance.rendered[:response][:error][:code]).to eq(-32_600)
        expect(instance.rendered[:response][:error][:message]).to eq('Invalid Request')
      end

      it 'reports that the id is missing' do
        reject

        expect(instance.rendered[:response][:error][:data]).to eq({ validations: ['id is missing'] })
      end

      it 'leaves the id key out of the response' do
        reject

        expect(instance.rendered[:response]).not_to have_key(:id)
      end
    end

    context 'when the request has an id' do
      where(:id) { [1, 'abc-123'] }

      with_them do
        let(:instance) { build_helper({ method: 'ping', id: id }) }

        it 'leaves validating it to Grape and renders nothing' do
          reject

          expect(instance.rendered).to be_nil
        end
      end
    end
  end

  describe '#render_invalid_jsonrpc_request!' do
    subject(:render_error) do
      instance.render_invalid_jsonrpc_request!(['method is empty'])
    end

    context 'when the request id is a string or an integer' do
      where(:id) { [1, 'abc-123'] }

      with_them do
        let(:instance) { build_helper({ id: id }) }

        it 'echoes the id unchanged', :aggregate_failures do
          render_error

          expect(instance.rendered[:status]).to eq(400)
          expect(instance.rendered[:response][:id]).to eql(id)
          expect(instance.rendered[:response][:error][:data]).to eq({ validations: ['method is empty'] })
        end
      end
    end

    context 'when the request id is absent or not usable' do
      where(:request_params) { [{}, { id: nil }, { id: 1.5 }, { id: { 'foo' => 'bar' } }] }

      with_them do
        let(:instance) { build_helper(request_params) }

        it 'leaves the id key out of the response' do
          render_error

          expect(instance.rendered[:response]).not_to have_key(:id)
        end
      end
    end
  end

  describe '#render_invalid_jsonrpc_params!' do
    it 'renders HTTP 400 with the Invalid params error and the message', :aggregate_failures do
      instance = build_helper({ id: 1 })

      instance.render_invalid_jsonrpc_params!('unsupported protocol version')

      expect(instance.rendered[:status]).to eq(400)
      expect(instance.rendered[:response]).to eq(
        jsonrpc: '2.0',
        error: { code: -32_602, message: 'Invalid params', data: { params: 'unsupported protocol version' } },
        id: 1
      )
    end

    context 'when the request id is absent or not usable' do
      where(:request_params) { [{}, { id: 1.5 }] }

      with_them do
        it 'keeps the id key with a null value' do
          instance = build_helper(request_params)

          instance.render_invalid_jsonrpc_params!('bad')

          expect(instance.rendered[:response]).to include(id: nil)
        end
      end
    end
  end

  describe '#method_not_found!' do
    it 'renders HTTP 404 with the Method not found error and the requested method', :aggregate_failures do
      instance = build_helper({ id: 1 })

      instance.method_not_found!('no/such/method')

      expect(instance.rendered[:status]).to eq(404)
      expect(instance.rendered[:response]).to eq(
        jsonrpc: '2.0',
        error: { code: -32_601, message: 'Method not found', data: { method: 'no/such/method' } },
        id: 1
      )
    end
  end

  describe '#format_jsonrpc_response' do
    context 'when the request has an id and a result' do
      it 'returns the result envelope with the id' do
        expect(build_helper({ id: 1 }).format_jsonrpc_response({ tools: [] }))
          .to eq(jsonrpc: '2.0', result: { tools: [] }, id: 1)
      end
    end

    context 'when the request is a notification or there is no result' do
      where(:request_params, :result) do
        [
          [{}, { tools: [] }],
          [{ id: 1 }, nil]
        ]
      end

      with_them do
        it 'answers 202 Accepted with an empty body', :aggregate_failures do
          instance = build_helper(request_params)

          instance.format_jsonrpc_response(result)

          expect(instance.response_status).to eq(:accepted)
          expect(instance.response_body).to be_a(Gitlab::Json::Precompiled).and have_attributes(to_s: '')
        end
      end
    end
  end
end
