# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Ai::DapFactory::Validator, :aggregate_failures, feature_category: :dap_triggers do
  let(:project) { nil }
  let(:result) { described_class.new(content: content, project: project).execute }
  let(:error_codes) { result.errors.map(&:code) }
  let(:error_paths) { result.errors.map(&:path) }
  let(:warning_codes) { result.warnings.map(&:code) }
  let(:warning_paths) { result.warnings.map(&:path) }

  let(:statuses) do
    {
      'triage' => 'Start',
      'plan' => 'Planning breakdown',
      'build' => 'In dev',
      'review' => 'In review',
      'ship' => 'Done'
    }
  end

  let(:stages) do
    {
      'triage' => { 'start' => 'automated', 'flow' => 11, 'exit' => 'automated' },
      'plan' => { 'start' => 'automated', 'flow' => 12, 'exit' => 'automated' },
      'build' => { 'start' => 'automated', 'flow' => 13, 'exit' => 'automated', 'mark_merge_requests_ready' => true },
      'review' => { 'start' => 'automated', 'exit' => 'manual', 'flow' => 'developer/v1' }
    }
  end

  let(:document) do
    {
      'factory' => 'test',
      'status' => statuses,
      'stages' => stages,
      'review' => { 'label' => 'software-factory', 'max_fix_runs' => 5 }
    }
  end

  let(:content) { document.to_yaml }

  def with_stage(key, value)
    stages.merge(key => value)
  end

  it 'accepts a complete file and builds the configuration' do
    expect(result).to be_valid

    configuration = result.configuration
    expect(configuration.factory_name).to eq('test')
    expect(configuration.stages.map(&:key)).to eq(Gitlab::Ai::DapFactory::Configuration::STAGES)
    expect(configuration.stage(:build)).to have_attributes(status: 'In dev', flow: 13)
    expect(configuration.stage(:review)).to have_attributes(flow: 'developer/v1')
    expect(configuration.stage(:verify)).to be_skipped
    expect(configuration.triggered_stages.map(&:key)).to eq(%w[triage plan build review])
    expect(configuration.review).to have_attributes(label: 'software-factory', reviewer: nil, max_fix_runs: 5)
  end

  it 'marks triage and plan as intake stages, which run before a workplan exists' do
    expect(result.configuration.stages.select(&:intake?).map(&:key)).to eq(%w[triage plan])
  end

  it 'routes an automated exit to the next stage that is not skipped' do
    configuration = result.configuration

    expect(configuration.status_on_finish_for(configuration.stage(:build))).to eq('In review')
    expect(configuration.status_on_finish_for(configuration.stage(:review))).to be_nil
  end

  it 'accepts a file with only statuses and no stage settings, as a manual factory has' do
    content = <<~YAML
      factory: "test"
      status:
        triage: Start
        plan: Planning breakdown
        build: In dev
        verify: Verification
        review: In review
        ship: Verification
      review:
        max_fix_runs: 3
    YAML

    result = described_class.new(content: content).execute

    expect(result).to be_valid
    expect(result.warnings).to be_empty
    expect(result.configuration.stages).to all(have_attributes(skipped?: false, automated_start?: false))
    expect(result.configuration.triggered_stages).to be_empty
  end

  describe 'the file as a whole' do
    it 'reports independent mistakes together, instead of one per push' do
      document['status'] = statuses.merge('plan' => 'x' * 33)
      document['stages'] = stages.merge(
        'build' => { 'start' => 'manual', 'exit' => 'automated' },
        'review' => stages['review'].merge('flow' => 'Generate Workplan')
      )

      expect(error_paths).to contain_exactly('status.plan', 'stages.build.exit', 'stages.review.flow')
    end

    it 'checks routing and shared statuses only once every stage reads cleanly' do
      document['status'] = statuses.merge('plan' => 'x' * 33, 'ship' => 'In dev')
      document['stages'] = stages.merge('ship' => { 'start' => 'automated', 'flow' => 15, 'exit' => 'automated' })

      expect(error_codes).to eq([:missing_status])
    end

    context 'when the YAML does not parse' do
      let(:content) { "stages:\n  triage: [" }

      it 'says what is wrong and where' do
        expect(error_codes).to eq([:invalid_yaml])
        expect(result.errors.first.message).to start_with('The file is not valid YAML: did not find')
        expect(result.errors.first.message).to include('line 3')
      end
    end

    context 'when the file is empty' do
      let(:content) { '' }

      it { expect(error_codes).to eq([:empty]) }
    end

    context 'when the file is not a mapping' do
      let(:content) { "- triage\n" }

      it { expect(error_codes).to eq([:not_a_mapping]) }
    end

    context 'when the file is an empty mapping' do
      let(:document) { {} }

      it { expect(error_codes).to eq([:empty]) }
    end

    context 'when a key is a symbol' do
      let(:content) { ":status:\n  triage: Start\n" }

      it 'reports the key instead of silently ignoring the block' do
        expect(result).to be_valid
        expect(warning_paths).to eq([':status'])
        expect(result.configuration.stages).to all(be_skipped)
      end
    end

    context 'when the file is too large' do
      let(:content) { "factory: #{'a' * described_class::MAX_BYTES}" }

      it { expect(error_codes).to eq([:too_large]) }
    end

    context 'when the file is nested too deeply to be read' do
      let(:content) { "#{(1..101).map { |depth| "#{' ' * (depth - 1)}key#{depth}:" }.join("\n")} 1" }

      it { expect(error_codes).to eq([:too_large]) }
    end

    context 'when it uses an alias' do
      let(:content) { "factory: &name test\nstatus:\n  triage: *name\n" }

      it 'reads it like the fix loop does' do
        expect(result).to be_valid
        expect(result.configuration.stage(:triage).status).to eq('test')
      end
    end

    context 'with more unknown keys than are reported' do
      let(:document) { super().merge((1..25).index_by { |i| "extra#{i}" }) }

      it 'warns about the first ones and counts the rest' do
        expect(result).to be_valid
        expect(warning_codes.tally).to eq(unknown_key: 20, unknown_keys_omitted: 1)
        expect(result.warnings.last).to have_attributes(path: nil, message: '5 more unknown settings are ignored.')
      end
    end

    context 'with an unknown top-level key' do
      let(:document) { super().merge('owner' => 'me') }

      it 'warns and still accepts the file' do
        expect(result).to be_valid
        expect(warning_paths).to eq(['owner'])
      end
    end

    context 'with only a factory name' do
      let(:document) { { 'factory' => 'test' } }

      it 'skips every stage' do
        expect(result).to be_valid
        expect(result.configuration.stages).to all(be_skipped)
      end
    end

    context 'when the factory name is not text' do
      let(:document) { super().merge('factory' => ['test']) }

      it { expect(error_codes).to eq([:invalid_factory]) }
    end

    context 'without a factory name' do
      let(:document) { super().except('factory') }

      it 'is valid, with no name' do
        expect(result).to be_valid
        expect(result.configuration.factory_name).to be_nil
      end
    end
  end

  describe 'status' do
    it 'must be a mapping' do
      document['status'] = ['Start']

      expect(error_codes).to eq([:invalid_status_block])
    end

    it 'requires a status name for each stage it lists' do
      document['status'] = statuses.merge('verify' => nil, 'ship' => 3, 'plan' => 'x' * 33)

      expect(error_paths).to contain_exactly('status.verify', 'status.ship', 'status.plan')
      expect(error_codes.uniq).to eq([:missing_status])
    end

    it 'accepts the keys that only the flows of the factory read' do
      document['status'] = statuses.merge(
        'complete' => 'Complete',
        'by_work_item_type' => [{ 'type_id' => 5, 'build' => 'In dev' }]
      )

      expect(result).to be_valid
      expect(result.warnings).to be_empty
    end

    it 'warns about other keys' do
      document['status'] = statuses.merge('deploy' => 'Deploying')

      expect(result).to be_valid
      expect(warning_paths).to eq(['status.deploy'])
    end

    it 'lets stages share a status when no stage starts on it' do
      document['status'] = statuses.merge('verify' => 'Verification', 'ship' => 'verification')

      expect(result).to be_valid
    end

    it 'rejects a shared status that starts a flow, ignoring case' do
      document['status'] = statuses.merge('ship' => 'in dev')

      expect(error_paths).to contain_exactly('status.build', 'status.ship')
      expect(error_codes.uniq).to eq([:duplicate_status])
    end
  end

  describe 'stages' do
    context 'when stages is not a mapping' do
      let(:stages) { ['triage'] }

      it { expect(error_codes).to eq([:invalid_stages]) }
    end

    context 'with a stage that is not a Software Factory stage' do
      let(:stages) { super().merge('deploy' => { 'start' => 'manual' }) }

      it { expect(error_paths).to eq(['stages.deploy']) }
    end

    context 'with more unknown stages than are reported' do
      let(:stages) { super().merge((1..25).to_h { |i| ["stage#{i}", {}] }) }

      it 'rejects the first ones and counts the rest' do
        expect(error_codes.tally).to eq(unknown_stage: 20, unknown_stages_omitted: 1)
        expect(result.errors.last).to have_attributes(path: 'stages',
          message: '5 more keys are not Software Factory stages.')
      end
    end

    context 'when a stage is not a mapping' do
      let(:stages) { super().merge('ship' => 'skipped') }

      it 'says how to skip a stage' do
        expect(error_codes).to eq([:invalid_stage])
        expect(result.errors.first.message).to include('remove it from status')
      end
    end

    context 'with settings for a stage without a status' do
      let(:stages) { super().merge('verify' => { 'start' => 'manual' }) }

      it { expect(error_paths).to eq(['stages.verify']) }
    end

    context 'with an unknown stage setting' do
      let(:stages) { super().merge('ship' => { 'owner' => 'me' }) }

      it 'warns about it' do
        expect(result).to be_valid
        expect(warning_paths).to eq(['stages.ship.owner'])
      end
    end

    it 'starts and exits a stage manually without settings' do
      expect(result.configuration.stage(:ship)).to have_attributes(start_mode: 'manual', exit_mode: 'manual')
    end

    it 'requires start and exit to be automated or manual' do
      document['stages'] = with_stage('ship', { 'start' => 'auto', 'exit' => 1 })

      expect(error_codes).to contain_exactly(:invalid_start, :invalid_exit)
    end

    it 'rejects a manual start with an automated exit' do
      document['stages'] = with_stage('plan', { 'start' => 'manual', 'exit' => 'automated' })

      expect(error_codes).to eq([:automated_exit_needs_automated_start])
    end

    it 'requires a flow when start is automated' do
      document['stages'] = with_stage('plan', stages['plan'].except('flow'))

      expect(error_codes).to eq([:missing_flow])
    end

    it 'rejects a flow when start is manual' do
      document['stages'] = with_stage('ship', { 'flow' => 5 })

      expect(error_codes).to eq([:flow_needs_automated_start])
    end

    describe 'flow' do
      it 'reads a catalog item ID written as text, ignoring surrounding spaces' do
        document['stages'] = with_stage('plan', stages['plan'].merge('flow' => ' 12 '))

        expect(result).to be_valid
        expect(result.configuration.stage(:plan).flow).to eq(12)
      end

      it 'reads a foundational flow reference, ignoring surrounding spaces' do
        document['stages'] = with_stage('plan', stages['plan'].merge('flow' => ' fix_pipeline/v1 '))

        expect(result).to be_valid
        expect(result.configuration.stage(:plan).flow).to eq('fix_pipeline/v1')
      end

      it 'reads the reference of a foundational flow that has no released version yet' do
        document['stages'] = with_stage('plan', stages['plan'].merge('flow' => 'fix_pipeline/experimental'))

        expect(result).to be_valid
        expect(result.configuration.stage(:plan).flow).to eq('fix_pipeline/experimental')
      end

      it 'rejects text that is neither an ID nor a reference' do
        document['stages'] = with_stage('plan', stages['plan'].merge('flow' => 'Generate Workplan'))

        expect(error_codes).to eq([:invalid_flow])
        expect(error_paths).to eq(['stages.plan.flow'])
      end

      it 'rejects an ID that is not positive' do
        document['stages'] = with_stage('plan', stages['plan'].merge('flow' => 0))

        expect(error_codes).to eq([:invalid_flow])
      end
    end

    it 'rejects mark_merge_requests_ready without an automated exit' do
      document['stages'] = with_stage('ship', { 'mark_merge_requests_ready' => true })

      expect(error_codes).to eq([:ready_needs_automated_exit])
    end

    it 'requires mark_merge_requests_ready to be true or false' do
      document['stages'] = with_stage('build', stages['build'].merge('mark_merge_requests_ready' => 'yes'))

      expect(error_codes).to eq([:invalid_mark_merge_requests_ready])
    end

    describe 'review' do
      it 'runs its flow on a merge request event, not on a status change' do
        document['stages'] = with_stage('review', stages['review'].merge('flow' => 5))

        expect(result.configuration.stage(:review)).to have_attributes(triggered?: true, status_triggered?: false)
      end

      it 'requires a flow when start is automated' do
        document['stages'] = with_stage('review', stages['review'].except('flow'))

        expect(error_codes).to eq([:missing_flow])
      end

      it 'can share a status with a stage, because no flow starts on it' do
        document['status'] = statuses.merge('ship' => 'In review')
        document['stages'] = with_stage('review', stages['review'].merge('flow' => 5))

        expect(result).to be_valid
      end

      it 'rejects an automated exit' do
        document['stages'] = with_stage('review', stages['review'].merge('exit' => 'automated'))

        expect(error_codes).to eq([:automated_exit_not_supported])
      end
    end

    it 'rejects an automated exit with no active stage after it' do
      document['status'] = statuses.except('review')
      document['stages'] = stages.except('review').merge(
        'ship' => { 'start' => 'automated', 'flow' => 15, 'exit' => 'automated' }
      )

      expect(error_codes).to eq([:no_next_stage])
    end
  end

  describe 'the review block' do
    it 'is optional, and gives the defaults of the fix loop' do
      document.delete('review')

      expect(result).to be_valid
      expect(result.configuration.review.max_fix_runs)
        .to eq(Ai::FlowTriggers::FixLoop::Config::DEFAULT_MAX_FIX_RUNS)
    end

    it 'applies the rules of the fix loop' do
      document['review'] = { 'max_fix_runs' => 11 }

      expect(error_paths).to eq(['review'])
      expect(result.errors.first.message).to include('max_fix_runs')
    end

    it 'rejects the keys of the old CI referee, as the fix loop does' do
      document['review'] = { 'reviewer' => 'GitLabDuo', 'max_rounds' => 3, 'cap_round' => true }

      expect(error_codes).to eq([:invalid_review])
      expect(result.errors.first.message).to include('`max_rounds`', '`cap_round`')
    end
  end

  context 'with a project' do
    let_it_be(:project) { create(:project, :in_group) }
    let_it_be(:root) { project.root_ancestor }
    let_it_be(:organization) { project.organization }

    let_it_be(:triage_flow) { create(:ai_catalog_item, :flow, :public, organization: organization) }
    let_it_be(:plan_flow) { create(:ai_catalog_item, :flow, :public, organization: organization) }
    let_it_be(:developer) do
      create(:ai_catalog_item, :flow, :public, organization: organization, foundational_flow_reference: 'developer/v1')
    end

    let_it_be(:consumers) do
      [triage_flow, plan_flow, developer].map do |item|
        create(:ai_catalog_item_consumer, :child_item_consumer, project: project, item: item)
      end
    end

    let(:stages) do
      super().merge(
        'triage' => super()['triage'].merge('flow' => triage_flow.id),
        'plan' => super()['plan'].merge('flow' => plan_flow.id),
        'build' => super()['build'].merge('flow' => developer.id),
        'review' => super()['review'].merge('flow' => 'developer/v1')
      )
    end

    before_all do
      ['Start', 'Planning breakdown', 'In dev', 'In review', 'Done'].each do |name|
        create(:work_item_custom_status, namespace: root, name: name)
      end
    end

    def plan_with_flow(flow)
      document['stages'] = with_stage('plan', stages['plan'].merge('flow' => flow))
    end

    it 'accepts statuses that exist in the project and flows enabled in it, by ID or by reference' do
      expect(result).to be_valid
      expect(result.warnings).to be_empty
      expect(result.configuration.stage(:build).flow).to eq(developer.id)
      expect(result.configuration.stage(:review).flow).to eq('developer/v1')
    end

    it 'accepts a foundational flow referenced only by name' do
      document['stages'] = with_stage('build', stages['build'].merge('flow' => plan_flow.id))

      expect(result).to be_valid
      expect(result.configuration.stage(:review).flow).to eq('developer/v1')
    end

    it 'looks the flows up in two queries, however many stages reference them' do
      control = ActiveRecord::QueryRecorder.new { described_class.new(content: content, project: project).execute }
      catalog_queries = control.log.grep(/ai_catalog_item/)

      expect(catalog_queries.size).to eq(2)
    end

    it 'checks the flow of a stage whose status was rejected, without checking the status' do
      document['status'] = statuses.merge('plan' => nil)
      plan_with_flow(non_existing_record_id)

      expect(error_codes).to contain_exactly(:missing_status, :flow_not_enabled)
      expect(error_paths).to contain_exactly('status.plan', 'stages.plan.flow')
    end

    it 'reports an unknown status and a flow that is not enabled together' do
      document['status'] = statuses.merge('review' => 'In reveiw')
      plan_with_flow(non_existing_record_id)

      expect(error_codes).to contain_exactly(:unknown_status, :flow_not_enabled)
      expect(error_paths).to contain_exactly('status.review', 'stages.plan.flow')
    end

    it 'warns when the flow of Review is not Duo Developer, because the fix loop does not apply' do
      document['stages'] = with_stage('review', stages['review'].merge('flow' => triage_flow.id))

      expect(result).to be_valid
      expect(warning_codes).to eq([:fix_loop_not_applied])
      expect(warning_paths).to eq(['stages.review.flow'])
    end

    context 'when flow chaining is off for the group' do
      before do
        stub_feature_flags(ai_flow_trigger_chaining: false)
      end

      it 'warns that automated exits and the fix loop do not chain' do
        expect(result).to be_valid
        expect(warning_codes.uniq).to eq([:chaining_off])
        expect(warning_paths).to contain_exactly(
          'stages.triage.exit', 'stages.plan.exit', 'stages.build.exit', 'stages.review.start'
        )
      end

      it 'warns only about the exits when Review is not in the factory' do
        document['status'] = statuses.except('review')
        document['stages'] = stages.except('review')

        expect(result).to be_valid
        expect(warning_paths).to contain_exactly('stages.triage.exit', 'stages.plan.exit', 'stages.build.exit')
      end

      it 'warns only about the exits when Review starts manually' do
        document['stages'] = with_stage('review', { 'start' => 'manual' })

        expect(result).to be_valid
        expect(warning_paths).to contain_exactly('stages.triage.exit', 'stages.plan.exit', 'stages.build.exit')
      end
    end

    it 'uses the spelling of the project for a status' do
      document['status'] = statuses.merge('build' => 'in DEV')

      expect(result.configuration.stage(:build).status).to eq('In dev')
    end

    it 'accepts a factory with no flows, with nothing to look up' do
      document['stages'] = {}

      expect(result).to be_valid
      expect(result.configuration.triggered_stages).to be_empty
    end

    it 'rejects a status that does not exist' do
      document['status'] = statuses.merge('ship' => 'Shipped')

      expect(error_paths).to eq(['status.ship'])
      expect(error_codes).to eq([:unknown_status])
    end

    describe 'a flow the project has not enabled' do
      shared_examples 'a flow that is not enabled' do
        it 'is rejected with one answer, whether the flow exists or not' do
          plan_with_flow(flow)

          expect(error_codes).to eq([:flow_not_enabled])
          expect(error_paths).to eq(['stages.plan.flow'])
          expect(result.errors.first.message).to include('Enable it in the AI Catalog first')
        end
      end

      context 'with a public flow the project has not enabled' do
        let(:flow) { create(:ai_catalog_item, :flow, :public, organization: organization).id }

        it_behaves_like 'a flow that is not enabled'
      end

      context 'with a flow the project has, but disabled' do
        let(:flow) do
          item = create(:ai_catalog_item, :flow, :public, organization: organization)
          create(:ai_catalog_item_consumer, :child_item_consumer, project: project, item: item, enabled: false)
          item.id
        end

        it_behaves_like 'a flow that is not enabled'
      end

      context 'with a private flow of the project itself' do
        let(:flow) { create(:ai_catalog_item, :flow, :private, project: project).id }

        it_behaves_like 'a flow that is not enabled'
      end

      context 'with a foundational flow referenced by name' do
        let(:flow) do
          create(:ai_catalog_item, :flow, :public, organization: organization,
            foundational_flow_reference: 'fix_pipeline/v1')
          'fix_pipeline/v1'
        end

        it_behaves_like 'a flow that is not enabled'
      end

      context 'with an ID that does not exist' do
        let(:flow) { non_existing_record_id }

        it_behaves_like 'a flow that is not enabled'
      end

      context 'with an ID larger than the database can hold' do
        let(:flow) { 10**30 }

        it_behaves_like 'a flow that is not enabled'
      end

      context 'with a reference that does not exist' do
        let(:flow) { 'nope/v1' }

        it_behaves_like 'a flow that is not enabled'
      end

      context 'with a private flow of another project' do
        let(:flow) { create(:ai_catalog_item, :flow, :private, project: create(:project, :in_group)).id }

        it_behaves_like 'a flow that is not enabled'
      end

      context 'with a deleted flow' do
        let(:flow) { create(:ai_catalog_item, :flow, :public, :soft_deleted, organization: organization).id }

        it_behaves_like 'a flow that is not enabled'
      end

      context 'with a flow the group enabled for all its projects through inheritance' do
        let(:flow) do
          item = create(:ai_catalog_item, :flow, :public, organization: organization)
          create(:ai_catalog_item_consumer, :inheritance, group: root, item: item)
          item.id
        end

        it_behaves_like 'a flow that is not enabled'
      end
    end

    it 'accepts an enabled third-party flow' do
      item = create(:ai_catalog_item, :third_party_flow, :public, organization: organization)
      create(:ai_catalog_item_consumer, :child_item_consumer, project: project, item: item)
      plan_with_flow(item.id)

      expect(result).to be_valid
      expect(result.configuration.stage(:plan).flow).to eq(item.id)
    end

    it 'rejects an enabled item that is not a flow' do
      agent = create(:ai_catalog_item_consumer, project: project)
      plan_with_flow(agent.ai_catalog_item_id)

      expect(error_codes).to eq([:not_a_flow])
      expect(error_paths).to eq(['stages.plan.flow'])
    end
  end

  context 'with a project in a group that uses the default statuses' do
    let_it_be(:project) { create(:project, :in_group) }

    let(:statuses) { { 'build' => 'in progress', 'ship' => 'Done' } }
    let(:stages) { {} }

    it 'accepts a default status, with its own spelling' do
      expect(result).to be_valid
      expect(result.configuration.stage(:build).status).to eq('In progress')
    end

    it 'rejects a status that is not a default status' do
      document['status'] = statuses.merge('ship' => 'Shipped')

      expect(error_codes).to eq([:unknown_status])
      expect(error_paths).to eq(['status.ship'])
    end
  end
end
