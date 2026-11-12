# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::Ci::Config::Interpolation::Template, feature_category: :pipeline_composition do
  subject { described_class.new(YAML.safe_load(config), ctx) }

  let(:config) do
    <<~CFG
    test:
      spec:
        env: $[[ inputs.env ]]

    $[[ inputs.key ]]:
      name: $[[ inputs.key ]]
      parallel: $[[ inputs.parallel ]]
      allow_failure: $[[ inputs.allow_failure ]]
      script: 'echo "This job makes $[[ inputs.parallel ]] jobs for the $[[ inputs.env ]] env"'
    CFG
  end

  let(:ctx) do
    { inputs: { allow_failure: true, env: 'dev', key: 'abc', parallel: 6 } }
  end

  it 'collects interpolation blocks' do
    expect(subject.size).to eq 4
  end

  it 'interpolates the values properly' do
    expect(subject.interpolated).to eq YAML.safe_load <<~RESULT
    test:
      spec:
        env: dev

    abc:
      name: abc
      parallel: 6
      allow_failure: true
      script: 'echo "This job makes 6 jobs for the dev env"'
    RESULT
  end

  context 'when interpolation can not be performed' do
    let(:config) { '$[[ xxx.yyy ]]: abc' }

    it 'does not interpolate the config' do
      expect(subject).not_to be_valid
      expect(subject.interpolated).to be_nil
    end
  end

  context 'when template consists of nested arrays with hashes and values' do
    let(:config) do
      <<~CFG
      test:
        - a-$[[ inputs.key ]]-b
        - c-$[[ inputs.key ]]-d:
            d-$[[ inputs.key ]]-e
          val: 1
      CFG
    end

    it 'performs a valid interpolation' do
      result = { 'test' => ['a-abc-b', { 'c-abc-d' => 'd-abc-e', 'val' => 1 }] }

      expect(subject).to be_valid
      expect(subject.interpolated).to eq result
    end
  end

  context 'when template contains symbols that need interpolation' do
    subject do
      described_class.new({ '$[[ inputs.key ]]': 'cde' }, ctx)
    end

    it 'performs a valid interpolation' do
      expect(subject).to be_valid
      expect(subject.interpolated).to eq({ 'abc' => 'cde' })
    end
  end

  context 'when template is too large' do
    before do
      stub_const('Gitlab::Ci::Config::Interpolation::Config::MAX_NODES', 1)
    end

    it 'returns an error' do
      expect(subject.interpolated).to be_nil
      expect(subject.errors.count).to eq 1
      expect(subject.errors.first).to eq 'config too large'
    end
  end

  context 'when there are too many interpolation blocks' do
    before do
      stub_const("#{described_class}::MAX_BLOCKS", 1)
    end

    it 'returns an error' do
      expect(subject.interpolated).to be_nil
      expect(subject.errors.count).to eq 1
      expect(subject.errors.first).to eq 'too many interpolation blocks'
    end
  end

  context 'when template uses array indexing' do
    let(:config) do
      <<~CFG
      test:
        script: $[[ inputs.some_array[0] ]]
      CFG
    end

    let(:ctx) do
      { inputs: { some_array: ['echo hello', 'echo world'] } }
    end

    it 'interpolates the array element' do
      expect(subject.interpolated).to eq({ 'test' => { 'script' => 'echo hello' } })
    end
  end

  context 'when an interpolated value inside a larger string contains backslash sequences' do
    let(:config) do
      <<~CFG
      test:
        script: 'run $[[ inputs.cmd ]] now'
      CFG
    end

    let(:ctx) do
      { inputs: { cmd: 'sed s/\1/x/' } }
    end

    it 'inserts the value verbatim without interpreting backreferences' do
      expect(subject.interpolated).to eq({ 'test' => { 'script' => 'run sed s/\1/x/ now' } })
    end
  end

  context 'when an interpolated value contains interpolation blocks' do
    let(:config) do
      <<~CFG
      test:
        script: '$[[ inputs.body ]] $[[ inputs.body ]] $[[ inputs.body ]] $[[ inputs.other ]]'
      CFG
    end

    let(:ctx) do
      { inputs: { body: '$[[ inputs.body ]]$[[ inputs.other ]]', other: 'x' } }
    end

    it 'inserts each value once without interpolating it again' do
      body = '$[[ inputs.body ]]$[[ inputs.other ]]'

      expect(subject.interpolated).to eq({ 'test' => { 'script' => "#{body} #{body} #{body} x" } })
    end
  end

  context 'when using the default function' do
    let(:config) do
      <<~CFG
      test:
        image: 'registry.example.com/app:$[[ component.version | default(component.sha) ]]'
        tags: $[[ inputs.tags | default(inputs.fallback_tags) ]]
        stage: $[[ inputs.stage | default('test') ]]
        allow_failure: $[[ inputs.allow_failure | default(inputs.fallback_allow_failure) ]]
        script: $[[ inputs.script | default(inputs.fallback_script) ]]
      CFG
    end

    let(:ctx) do
      {
        inputs: {
          tags: nil,
          fallback_tags: %w[docker linux],
          stage: nil,
          allow_failure: false,
          fallback_allow_failure: true,
          script: '',
          fallback_script: '$[[ inputs.tags ]]'
        },
        component: { version: nil, sha: 'abc123' }
      }
    end

    before do
      allow(Gitlab::Ci::Config::FeatureFlags).to receive(:enabled?)
        .with(:ci_interpolation_default_function)
        .and_return(true)
    end

    context 'when a block is invalid' do
      let(:config) do
        <<~CFG
        test:
          image: 'registry.example.com/app:$[[ component.sha ]]'
          script: #{block}
        CFG
      end

      shared_examples 'an invalid template' do |errors|
        it 'does not interpolate any block', :aggregate_failures do
          expect(subject).not_to be_valid
          expect(subject.interpolated).to be_nil
          expect(subject.errors).to match_array(errors)
        end
      end

      context 'with invalid syntax' do
        let(:block) { '$[[ component.version | default component.sha ]]' }

        it_behaves_like 'an invalid template', [
          'no function matching `default component.sha`: ' \
            'check that the function name, arguments, and types are correct'
        ]
      end

      context 'with a field that is not in the context' do
        let(:block) { '$[[ component.version | default(component.reference) ]]' }

        it_behaves_like 'an invalid template', [
          'error in `default` function: invalid argument: ' \
            'unknown interpolation provided: `reference` in `component.reference`'
        ]
      end

      context 'with an array index out of bounds' do
        let(:block) { '$[[ component.version | default(inputs.fallback_tags[5]) ]]' }

        it_behaves_like 'an invalid template', [
          'error in `default` function: invalid argument: ' \
            'array index 5 out of bounds (size: 2) in `inputs.fallback_tags[5]`'
        ]
      end

      # The block is split on every `|`, so a literal cannot contain one.
      context 'with a literal that contains a pipe' do
        let(:block) { "$[[ component.version | default('a|b') ]]" }

        it_behaves_like 'an invalid template', [
          "no function matching `default('a`: check that the function name, arguments, and types are correct",
          "no function matching `b')`: check that the function name, arguments, and types are correct"
        ]
      end

      # The block ends at the first `]]`, so a literal cannot contain one.
      context 'with a literal that contains the block end' do
        let(:block) { "$[[ component.version | default('a]]b') ]]" }

        it_behaves_like 'an invalid template', [
          "no function matching `default('a`: check that the function name, arguments, and types are correct"
        ]
      end

      context 'with a boolean literal' do
        let(:block) { '$[[ component.version | default(true) ]]' }

        it_behaves_like 'an invalid template', [
          'error in `default` function: invalid argument: ' \
            'invalid pattern used for interpolation. valid pattern is $[[ inputs.input ]]'
        ]
      end

      context 'with more functions than allowed' do
        let(:block) { "$[[ component.version | default('a') | default('b') | default('c') | default('d') ]]" }

        it_behaves_like 'an invalid template', ['too many functions in interpolation block']
      end
    end

    it 'replaces empty values with the fallback, keeps types and does not interpolate the fallback again' do
      expect(subject.interpolated).to eq({
        'test' => {
          'image' => 'registry.example.com/app:abc123',
          'tags' => %w[docker linux],
          'stage' => 'test',
          'allow_failure' => false,
          'script' => '$[[ inputs.tags ]]'
        }
      })
    end
  end
end
