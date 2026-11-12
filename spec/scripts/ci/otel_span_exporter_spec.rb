# frozen_string_literal: true

require 'fast_spec_helper'
require 'tmpdir'

require_relative '../../support/webmock'
require_relative '../../../scripts/ci/otel_span_exporter'

RSpec.describe OtelSpanExporter, feature_category: :tooling do
  let(:trace_id) { '000000000000000000000000acb87def' }
  let(:job_span_id) { 'c929c65f80a6df0f' }
  let(:endpoint) { 'https://example.otel.gitlab-o11y.com:14318' }
  let(:traces_url) { "#{endpoint}/v1/traces" }
  let(:env) do
    {
      'GLCI_OTEL_ENDPOINT' => endpoint,
      'CI_TRACEPARENT' => "00-#{trace_id}-#{job_span_id}-01",
      'CI_TRACESTATE' => 'gitlab=pipeline:2;job:3',
      'CI_PIPELINE_ID' => '2',
      'CI_JOB_ID' => '3',
      'CI_JOB_NAME' => 'verify-tests-yml',
      'CI_PROJECT_ID' => '278964',
      'CI_PROJECT_NAME' => 'gitlab',
      'CI_PROJECT_NAMESPACE' => 'gitlab-org',
      'CI_PROJECT_TITLE' => 'GitLab',
      'CI_PROJECT_URL' => 'https://gitlab.com/gitlab-org/gitlab',
      'CI_SERVER_VERSION' => '19.5.0-pre'
    }
  end

  let(:exit_code) { 0 }
  let(:argv) do
    %W[
      --name verify-tff-mapping --command scripts/verify-tff-mapping
      --start-time-ns 1000 --end-time-ns 2500 --exit-code #{exit_code}
    ]
  end

  let(:stderr) { StringIO.new }

  subject(:run) { described_class.run(argv, env: env, stderr: stderr) }

  def exported_payload
    payload = nil

    expect(WebMock).to have_requested(:post, traces_url).with { |request|
      payload = Gitlab::Json::SafeParser.parse(request.body)
    }

    payload
  end

  def exported_span
    exported_payload.dig('resourceSpans', 0, 'scopeSpans', 0, 'spans', 0)
  end

  def attribute_values(attributes)
    attributes.to_h { |attribute| [attribute['key'], attribute['value'].each_value.first] }
  end

  before do
    stub_request(:post, traces_url).to_return(status: 200)
  end

  context 'when the command succeeded' do
    it 'exits successfully' do
      expect(run).to eq(0)
    end

    it 'exports a span parented to the job span' do
      run

      expect(exported_span).to include(
        'traceId' => trace_id,
        'parentSpanId' => job_span_id,
        'traceState' => 'gitlab=pipeline:2;job:3',
        'name' => 'verify-tff-mapping',
        'kind' => described_class::SPAN_KIND_INTERNAL,
        'startTimeUnixNano' => '1000',
        'endTimeUnixNano' => '2500',
        'status' => { 'code' => described_class::STATUS_CODE_OK }
      )
      expect(exported_span['spanId']).to match(/\A\h{16}\z/)
    end

    it 'records job metadata and only the command name' do
      run

      expect(attribute_values(exported_span['attributes'])).to eq(
        'cicd.pipeline.run.id' => '2',
        'cicd.pipeline.task.name' => 'verify-tests-yml',
        'cicd.pipeline.task.run.id' => '3',
        'process.executable.name' => 'verify-tff-mapping',
        'process.exit.code' => '0'
      )
    end

    it 'uses the resource attributes of the pipeline export and the recommended project attributes' do
      run

      expect(attribute_values(exported_payload.dig('resourceSpans', 0, 'resource', 'attributes'))).to eq(
        'service.name' => 'gitlab-ci',
        'service.version' => '19.5.0-pre',
        'vcs.owner.name' => 'gitlab-org',
        'vcs.provider.name' => 'gitlab',
        'vcs.repository.name' => 'GitLab',
        'gitlab.vcs.repository.id' => '278964',
        'vcs.repository.url.full' => 'https://gitlab.com/gitlab-org/gitlab',
        'gitlab.project.id' => '278964',
        'gitlab.project.name' => 'gitlab'
      )
    end
  end

  context 'when the command failed' do
    let(:exit_code) { 3 }

    it 'exits successfully' do
      expect(run).to eq(0)
    end

    it 'exports an error span' do
      run

      expect(exported_span['status']).to eq('code' => described_class::STATUS_CODE_ERROR, 'message' => 'exit status 3')
      expect(attribute_values(exported_span['attributes'])).to include('process.exit.code' => '3')
    end
  end

  context 'when the wrapper supplies the preallocated span context' do
    let(:span_id) { '1234567890abcdef' }
    let(:argv) do
      super() + ['--span-id', span_id, '--parent-traceparent', "00-#{trace_id}-#{job_span_id}-01", '--tracestate', '']
    end

    before do
      env['CI_TRACEPARENT'] = "00-#{trace_id}-#{span_id}-01"
    end

    it 'uses the supplied span ID and original parent without parenting itself' do
      run

      expect(exported_span).to include('spanId' => span_id, 'parentSpanId' => job_span_id, 'traceState' => '')
    end
  end

  context 'with operation metadata' do
    let(:argv) { super() + %w[--operation-kind test --operation-name rspec --attempt 2] }

    it 'exports operation attributes and a numeric attempt without classifying success' do
      run

      expect(attribute_values(exported_span['attributes'])).to include(
        'gitlab.cicd.operation.kind' => 'test', 'gitlab.cicd.operation.name' => 'rspec',
        'gitlab.cicd.operation.attempt' => '2'
      )
      expect(attribute_values(exported_span['attributes'])).not_to have_key('gitlab.cicd.failure.category')
    end

    it 'omits unsupported metadata without suppressing the ordinary span' do
      argv[argv.index('test')] = 'secret value'
      argv[argv.index('rspec')] = 'secret value'
      argv[argv.index('2')] = '-1'

      expect(run).to eq(0)
      expect(attribute_values(exported_span['attributes']).keys.grep(/gitlab\.cicd\.operation/)).to be_empty
    end
  end

  context 'with structured RSpec evidence' do
    let(:exit_code) { 1 }
    let(:argv) { super() + %w[--operation-kind test --rspec-report report.json] }
    let(:report) { StringIO.new('{"summary":{"failure_count":1,"errors_outside_of_examples_count":0}}') }

    before do
      allow(File).to receive(:open).with('report.json', File::RDONLY | File::NONBLOCK).and_yield(report)
      allow(report).to receive(:stat).and_return(instance_double(File::Stat,
        file?: true, size: 100, mtime: Time.now))
    end

    it 'exports failure evidence as span attributes without report content or paths' do
      run

      expect(attribute_values(exported_span['attributes'])).to include(
        'gitlab.cicd.failure.category' => 'user:test:failure', 'gitlab.cicd.failure.source' => 'rspec_report'
      )
      expect(exported_payload.keys).to eq(['resourceSpans'])
      expect(exported_span['status']['code']).to eq(described_class::STATUS_CODE_ERROR)
      expect(exported_payload.to_s).not_to include('report.json', 'failure_count')
    end
  end

  describe '.run with --prepare-context' do
    let(:stdout) { StringIO.new }

    subject(:prepare_context) do
      described_class.run(['--prepare-context'], env: env, stderr: stderr, stdout: stdout)
    end

    it 'generates a child context without exporting a span' do
      expect(prepare_context).to eq(0)
      expect(stdout.string.chomp).to match(/\A00-#{trace_id}-[0-9a-f]{16}-01\z/)
      expect(stdout.string.chomp.split('-')[2]).not_to eq(job_span_id)
      expect(WebMock).not_to have_requested(:post, traces_url)
    end

    context 'with different trace flags' do
      before do
        env['CI_TRACEPARENT'] = "00-#{trace_id}-#{job_span_id}-00"
      end

      it 'preserves the flags' do
        prepare_context

        expect(stdout.string.chomp).to end_with('-00')
      end
    end

    context 'with invalid context' do
      before do
        env['CI_TRACEPARENT'] = 'invalid'
      end

      it 'does not supply a new context' do
        expect(prepare_context).to eq(0)
        expect(stdout.string).to be_empty
      end
    end

    context 'when span ID generation fails' do
      before do
        allow(SecureRandom).to receive(:hex).and_raise(RuntimeError)
      end

      it 'warns without failing the command or supplying context' do
        expect(prepare_context).to eq(0)
        expect(stdout.string).to be_empty
        expect(stderr.string).to include('span context preparation failed: RuntimeError')
      end
    end
  end

  context 'with resource usage enabled' do
    let(:collector) { instance_double(OtelSpanResourceUsage) }
    let(:argv) { super() + ['--resource-snapshot', '{}'] }

    before do
      env['GLCI_OTEL_RESOURCE_USAGE'] = 'true'
      allow(OtelSpanResourceUsage).to receive(:new).and_return(collector)
      allow(collector).to receive(:attributes).with('{}').and_return(
        'gitlab.cicd.resource_usage.cpu_time_seconds' => 1.5,
        'gitlab.cicd.resource_usage.memory_headroom_end_bytes' => 100,
        'gitlab.cicd.network.receive_bytes' => 1024,
        'gitlab.cicd.network.transmit_bytes' => 0
      )
    end

    context 'with an independent network toggle' do
      where(:network_usage, :network_enabled) { [[nil, false], ['false', false], ['true', true]] }

      with_them do
        before do
          env['GLCI_OTEL_NETWORK_USAGE'] = network_usage
        end

        it 'uses the explicit environment', :aggregate_failures do
          expect(run).to eq(0)
          expect(OtelSpanResourceUsage).to have_received(:new).with(network_enabled: network_enabled)
        end
      end
    end

    context 'when measurement exceeds its budget' do
      before do
        stub_const('OtelSpanExporter::ENRICHMENT_TIMEOUT_S', 0.01)
        allow(collector).to receive(:attributes) { sleep 1 }
      end

      it 'still sends the ordinary span' do
        expect(run).to eq(0)
        expect(exported_span['name']).to eq('verify-tff-mapping')
        expect(attribute_values(exported_span['attributes']).keys.grep(/resource_usage/)).to be_empty
      end
    end

    it 'exports usage as numeric span attributes without changing context or status' do
      run

      expect(exported_span['attributes']).to include(
        { 'key' => 'gitlab.cicd.resource_usage.cpu_time_seconds', 'value' => { 'doubleValue' => 1.5 } },
        { 'key' => 'gitlab.cicd.resource_usage.memory_headroom_end_bytes', 'value' => { 'intValue' => '100' } },
        { 'key' => 'gitlab.cicd.network.receive_bytes', 'value' => { 'intValue' => '1024' } },
        { 'key' => 'gitlab.cicd.network.transmit_bytes', 'value' => { 'intValue' => '0' } }
      )
      expect(exported_span).to include('parentSpanId' => job_span_id, 'status' => { 'code' => 1 })
    end

    it 'exports the ordinary span and logs the failure when collection fails' do
      allow(collector).to receive(:attributes).and_raise(IOError, 'disk unavailable')

      expect(run).to eq(0)
      expect(exported_span['name']).to eq('verify-tff-mapping')
      expect(stderr.string).to include('resource usage enrichment failed: IOError: disk unavailable')
    end

    it 'logs a programming error raised by collection' do
      allow(collector).to receive(:attributes).and_raise(NoMethodError, "undefined method 'lines' for nil")

      expect(run).to eq(0)
      expect(exported_span['name']).to eq('verify-tff-mapping')
      expect(stderr.string).to include("resource usage enrichment failed: NoMethodError: undefined method 'lines'")
    end

    it 'does not collect when disabled' do
      env['GLCI_OTEL_RESOURCE_USAGE'] = 'false'
      expect(collector).not_to receive(:attributes)

      run
    end

    it 'prepares the context and bounded snapshot in the same process' do
      allow(collector).to receive(:snapshot).and_return({ 'cpu_usage_usec' => 123 })
      stdout = StringIO.new

      described_class.run(['--prepare-resource-context'], env: env, stdout: stdout)

      context, snapshot = stdout.string.lines.map(&:chomp)
      expect(context).to match(/\A00-#{trace_id}-[0-9a-f]{16}-01\z/)
      expect(Gitlab::Json::SafeParser.parse(snapshot)).to eq('cpu_usage_usec' => 123)
      expect(WebMock).not_to have_requested(:post, traces_url)
    end

    it 'keeps the span context and logs when snapshot preparation unexpectedly fails' do
      allow(collector).to receive(:snapshot).and_raise(IOError, 'proc unavailable')
      stdout = StringIO.new

      expect(described_class.run(['--prepare-resource-context'], env: env, stdout: stdout, stderr: stderr)).to eq(0)
      expect(stdout.string.lines.last.chomp).to eq('{}')
      expect(stdout.string.lines.first).to start_with("00-#{trace_id}-")
      expect(stderr.string).to include('resource usage snapshot failed: IOError: proc unavailable')
      expect(stdout.string).not_to include('WARNING')
    end

    it 'redacts the endpoint from a logged snapshot failure' do
      allow(collector).to receive(:snapshot).and_raise(IOError, "failed for #{endpoint}")

      described_class.run(['--prepare-resource-context'], env: env, stdout: StringIO.new, stderr: stderr)

      expect(stderr.string).to include('resource usage snapshot failed: IOError: failed for [REDACTED]')
      expect(stderr.string).not_to include('example.otel.gitlab-o11y.com')
    end
  end

  context 'with the real resource collector' do
    let(:tmp_dir) { Dir.mktmpdir }
    let(:cgroup_directory) { File.join(tmp_dir, 'cgroup', 'job') }
    let(:disk) { OtelSpanDiskUsage.new(project_dir: tmp_dir) }
    let(:collector) do
      OtelSpanResourceUsage.new(
        cgroup_file: File.join(tmp_dir, 'membership'),
        mountinfo_file: File.join(tmp_dir, 'mountinfo'),
        disk: disk
      )
    end

    before do
      FileUtils.mkdir_p(cgroup_directory)
      File.write(File.join(tmp_dir, 'membership'), "0::/job\n")
      File.write(File.join(tmp_dir, 'mountinfo'), "1 2 0:1 / #{File.join(tmp_dir, 'cgroup')} rw - cgroup2 cgroup rw\n")
      write_cgroup_counters(cpu: 100)
      env['GLCI_OTEL_RESOURCE_USAGE'] = 'true'
      allow(OtelSpanResourceUsage).to receive(:new).and_return(collector)
    end

    after do
      FileUtils.rm_rf(tmp_dir)
    end

    def write_cgroup_counters(cpu:)
      File.write(File.join(cgroup_directory, 'cpu.stat'), "usage_usec #{cpu}\n")
      File.write(File.join(cgroup_directory, 'memory.current'), '200')
      File.write(File.join(cgroup_directory, 'memory.max'), '1000')
      File.write(File.join(cgroup_directory, 'memory.events'), "high 0\nmax 0\noom 0\noom_kill 0\n")
    end

    context 'when a counter exceeds the OTLP integer range' do
      let(:argv) { super() + ['--resource-snapshot', Gitlab::Json.generate(collector.snapshot)] }

      before do
        write_cgroup_counters(cpu: '9' * 400)
      end

      it 'exports the span with the remaining measurements' do
        expect(run).to eq(0)
        expect(stderr.string).to be_empty

        attributes = attribute_values(exported_span['attributes'])
        expect(attributes).to include('gitlab.cicd.resource_usage.memory_end_bytes' => '200')
        expect(attributes).not_to have_key('gitlab.cicd.resource_usage.cpu_time_seconds')
      end
    end

    context 'when the filesystem stat stalls past its own deadline' do
      let(:stdin) { instance_double(IO, close: nil) }
      let(:stdout) { instance_double(IO) }
      let(:stderr_io) { instance_double(IO, read: '') }
      let(:waiter) { instance_double(Process::Waiter, alive?: true, pid: 12345) }

      before do
        stub_const('RUBY_PLATFORM', 'x86_64-linux')
        allow(stdout).to receive(:read).with(1024) { sleep 5 }
        allow(Open3).to receive(:popen3).and_yield(stdin, stdout, stderr_io, waiter)
        allow(Process).to receive(:kill)
      end

      it 'keeps the cgroup snapshot within the enrichment budget and cleans up the subprocess' do
        output = StringIO.new

        described_class.run(['--prepare-resource-context'], env: env, stdout: output, stderr: stderr)

        snapshot = Gitlab::Json::SafeParser.parse(output.string.lines.last)
        expect(snapshot).to include('memory_bytes' => 200)
        expect(snapshot).not_to have_key('disk')
        expect(Process).to have_received(:kill).with('KILL', 12345)
        expect(stderr.string).to be_empty
      end
    end
  end

  context 'when classification exceeds its budget' do
    where(:exit_code) { [0, 1] }

    before do
      stub_const('OtelSpanExporter::ENRICHMENT_TIMEOUT_S', 0.01)
      allow(OtelSpanFailureClassifier).to receive(:attributes) { sleep 1 }
    end

    with_them do
      it 'exports the command outcome without report evidence' do
        expect(run).to eq(0)
        expect(exported_span['status']['code']).to eq(exit_code == 0 ? 1 : 2)
        values = attribute_values(exported_span['attributes'])
        expect(values['gitlab.cicd.failure.category']).to eq(exit_code == 0 ? nil : 'user:unknown')
      end
    end
  end

  context 'when the end time is not given' do
    let(:argv) { %w[--name verify-tff-mapping --start-time-ns 1000 --exit-code 0] }

    it 'ends the span now' do
      allow(Process).to receive(:clock_gettime).and_call_original
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_REALTIME, :nanosecond).and_return(5000)

      run

      expect(exported_span['endTimeUnixNano']).to eq('5000')
    end
  end

  context 'when the command name is not given' do
    let(:argv) { %w[--name verify-tff-mapping --start-time-ns 1000 --end-time-ns 2500 --exit-code 0] }

    it 'exports the span without the command name' do
      run

      expect(attribute_values(exported_span['attributes'])).not_to have_key('process.executable.name')
    end
  end

  context 'when the arguments are invalid' do
    where(:argv) do
      [
        [%w[--name verify-tff-mapping --start-time-ns 1000 --end-time-ns 2500]],
        [%w[--name verify-tff-mapping --start-time-ns now --end-time-ns 2500 --exit-code 0]],
        [['--name', 'verify-tff-mapping', '--start-time-ns', '', '--exit-code', '0']],
        [%w[--unknown]],
        [%w[--name test --start-time-ns 1000 --exit-code 0 --span-id invalid]],
        [%w[--name test --start-time-ns 1000 --exit-code 0 --span-id 0000000000000000]]
      ]
    end

    with_them do
      it 'warns and exits successfully without exporting a span' do
        expect(run).to eq(0)
        expect(WebMock).not_to have_requested(:post, traces_url)
        expect(stderr.string).to include('invalid arguments')
      end
    end
  end

  describe 'authentication' do
    context 'when GITLAB_OBSERVABILITY_TOKEN is set' do
      before do
        env['GITLAB_OBSERVABILITY_TOKEN'] = " ingest-token\n"
      end

      it 'sends the stripped token as a bearer token' do
        run

        expect(WebMock).to have_requested(:post, traces_url)
          .with(headers: { 'Authorization' => 'Bearer ingest-token', 'Content-Type' => 'application/json' })
      end
    end

    context 'when GITLAB_OBSERVABILITY_TOKEN contains control characters' do
      before do
        env['GITLAB_OBSERVABILITY_TOKEN'] = "ingest\rtoken"
      end

      it 'does not send an Authorization header' do
        run

        expect(WebMock).to have_requested(:post, traces_url).with { |request| !request.headers.key?('Authorization') }
      end
    end

    context 'when GITLAB_OBSERVABILITY_TOKEN is not set' do
      it 'does not send an Authorization header' do
        run

        expect(WebMock).to have_requested(:post, traces_url).with { |request| !request.headers.key?('Authorization') }
      end
    end
  end

  context 'when GLCI_OTEL_ENDPOINT has a trailing slash' do
    let(:endpoint) { 'https://example.otel.gitlab-o11y.com:14318/' }
    let(:traces_url) { 'https://example.otel.gitlab-o11y.com:14318/v1/traces' }

    it 'appends the traces path once' do
      run

      expect(WebMock).to have_requested(:post, traces_url)
    end
  end

  context 'when GLCI_OTEL_ENDPOINT is not set' do
    before do
      env.delete('GLCI_OTEL_ENDPOINT')
    end

    it 'does not export a span' do
      expect(run).to eq(0)
      expect(WebMock).not_to have_requested(:post, /v1/)
      expect(stderr.string).to be_empty
    end
  end

  context 'when CI_TRACEPARENT is invalid' do
    where(:traceparent) do
      [
        nil,
        'invalid',
        '00-000000000000000000000000ACB87DEF-c929c65f80a6df0f-01',
        '00-00000000000000000000000000000000-c929c65f80a6df0f-01',
        '00-000000000000000000000000acb87def-0000000000000000-01'
      ]
    end

    with_them do
      before do
        env['CI_TRACEPARENT'] = traceparent
      end

      it 'skips the export with a warning' do
        expect(run).to eq(0)
        expect(WebMock).not_to have_requested(:post, traces_url)
        expect(stderr.string).to include('CI_TRACEPARENT is missing or invalid')
      end
    end
  end

  describe 'export failures' do
    context 'when an invalid endpoint contains credentials' do
      let(:endpoint) { 'https://username:secret password@example.com' }

      it 'warns without disclosing the endpoint or credentials' do
        expect(run).to eq(0)
        expect(stderr.string).to include('span export failed: URI::InvalidURIError')
        expect(stderr.string).not_to include('username', 'secret password', 'example.com')
      end
    end

    context 'when the export raises an unexpected error' do
      let(:endpoint) { 'https://username:secret@example.otel.gitlab-o11y.com:14318' }

      before do
        env['GITLAB_OBSERVABILITY_TOKEN'] = 'ingest-token'
        message = "undefined method for #{endpoint} (username, secret, example.otel.gitlab-o11y.com) ingest-token"
        allow(Net::HTTP).to receive(:start).and_raise(NoMethodError, message)
      end

      it 'warns with the redacted error message' do
        expect(run).to eq(0)
        expect(stderr.string).to include(
          'span export failed: NoMethodError: undefined method for [REDACTED] ([REDACTED], [REDACTED], [REDACTED]) ' \
            '[REDACTED]'
        )
      end
    end

    context 'when the endpoint returns an error' do
      before do
        stub_request(:post, traces_url).to_return(status: 503)
      end

      it 'warns and exits successfully' do
        expect(run).to eq(0)
        expect(stderr.string).to include('span export failed with HTTP 503')
      end
    end

    context 'when the request times out' do
      before do
        env['GITLAB_OBSERVABILITY_TOKEN'] = 'ingest-token'
        stub_request(:post, traces_url).to_timeout
      end

      it 'warns without the token and exits successfully' do
        expect(run).to eq(0)
        expect(stderr.string).to include('span export failed: Net::OpenTimeout')
        expect(stderr.string).not_to include('ingest-token')
      end
    end

    context 'when the export exceeds the overall deadline' do
      before do
        allow(Timeout).to receive(:timeout).and_call_original
        allow(Timeout).to receive(:timeout).with(described_class::EXPORT_TIMEOUT_S).and_raise(Timeout::Error)
      end

      it 'warns and exits successfully' do
        expect(run).to eq(0)
        expect(stderr.string).to include('span export failed: Timeout::Error')
      end
    end
  end
end
