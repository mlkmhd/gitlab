# frozen_string_literal: true

# Expects `write_release`, which runs the service for one release write and returns its result.
RSpec.shared_examples 'a release write counted toward the release write limits' do
  using RSpec::Parameterized::TableSyntax

  context 'with release write limits', :clean_gitlab_redis_rate_limiting do
    let(:release_writes_throttled_result) do
      { status: :error, http_status: 429, message: Gitlab::ApplicationRateLimiter.throttled_error_message }
    end

    where(:limit_setting, :enforce_flag) do
      :release_writes_limit_per_project | :rate_limit_release_writes_per_project
      :release_writes_limit_per_user    | :rate_limit_release_writes_per_user
    end

    with_them do
      before do
        stub_application_setting(limit_setting => 1)
      end

      it 'refuses the write over the limit before any tag or render', :aggregate_failures do
        expect(write_release[:status]).to eq(:success)

        expect(Banzai::Renderer).not_to receive(:cacheless_render_field)

        expect { expect(write_release).to include(release_writes_throttled_result) }
          .not_to change { project.repository.tag_names.size }
      end

      context 'when the enforce flag is disabled' do
        before do
          stub_feature_flags(enforce_flag => false)
        end

        it 'allows the write over the limit' do
          write_release

          expect(write_release[:status]).to eq(:success)
        end
      end
    end

    it 'counts a write refused by the per-project limit toward the per-user limit', :aggregate_failures do
      stub_application_setting(release_writes_limit_per_project: 1, release_writes_limit_per_user: 2)

      expect(write_release[:status]).to eq(:success)
      expect(write_release).to include(release_writes_throttled_result)

      stub_application_setting(release_writes_limit_per_project: 0)

      # The third write is under the per-user limit unless the refused one counted
      expect(write_release).to include(release_writes_throttled_result)
    end
  end
end

# Expects `execute_service(**params)`, which runs the service for a write that sets the description to
# `**Awesome** release!`, with `params` overriding the write's own.
RSpec.shared_examples 'a release write that renders the description before the save transaction' do
  # Transactions open before the write, which spec isolation adds to
  let!(:outer_depth) { Release.connection.open_transactions }
  let(:render_depths) { [] }

  before do
    allow(Banzai::Renderer).to receive(:cacheless_render_field).and_wrap_original do |method, object, *args|
      render_depths << Release.connection.open_transactions if object.is_a?(Release)
      method.call(object, *args)
    end
  end

  shared_examples 'a release write that renders the description inside the save transaction' do
    it 'renders the description inside the save transaction', :aggregate_failures do
      execute_service

      expect(render_depths).to be_present
      expect(render_depths).to all(be > outer_depth)
    end
  end

  it 'renders the description once, outside the save transaction', :aggregate_failures do
    release = execute_service[:release].reload

    expect(render_depths).to eq([outer_depth])
    expect(release.cached_html_up_to_date?(:description)).to be(true)
    expect(release.description_html).to include('>Awesome</strong>')
  end

  context 'when the release is invalid' do
    it 'does not render the description' do
      execute_service(name: 'x' * 256)

      expect(render_depths).to be_empty
    end
  end

  context 'when release_description_render_before_save is disabled' do
    before do
      stub_feature_flags(release_description_render_before_save: false)
    end

    it_behaves_like 'a release write that renders the description inside the save transaction'
  end
end
