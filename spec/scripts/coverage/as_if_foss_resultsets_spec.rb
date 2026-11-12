# frozen_string_literal: true

require 'fast_spec_helper'
require 'tmpdir'
require_relative '../../../scripts/coverage/as_if_foss_resultsets'

RSpec.describe AsIfFossResultsets, feature_category: :tooling do
  let(:dir) { Dir.mktmpdir }
  let(:ee_file) { File.join(dir, 'ee.json') }
  let(:foss_file) { File.join(dir, 'foss.json') }

  subject(:rewrite) { described_class.new(root: '/builds/gitlab-org/gitlab').rewrite([ee_file, foss_file]) }

  before do
    File.write(ee_file, '{"rspec-unit-1-278964":{"coverage":{"/builds/gitlab-org/gitlab/app/a.rb":{"lines":[1]}}}}')
    File.write(foss_file,
      '{"rspec-unit-1-13083":{"coverage":{"/builds/gitlab-org/gitlab-foss/app/a.rb":{"lines":[0]}}}}')
  end

  after do
    FileUtils.rm_rf(dir)
  end

  it 'rewrites the gitlab-foss paths to the paths of this project' do
    rewrite

    expect(File.read(foss_file))
      .to eq('{"rspec-unit-1-13083":{"coverage":{"/builds/gitlab-org/gitlab/app/a.rb":{"lines":[0]}}}}')
  end

  it 'leaves resultsets without gitlab-foss paths as they are' do
    expect { rewrite }.not_to change { File.read(ee_file) }
  end

  it 'returns how many resultsets it rewrote' do
    expect(rewrite).to eq(1)
  end

  context 'when the project is in a subgroup' do
    subject(:rewrite) { described_class.new(root: '/builds/gitlab-org/security/gitlab').rewrite([foss_file]) }

    before do
      File.write(foss_file, '{"a":{"coverage":{"/builds/gitlab-org/security/gitlab-foss/app/a.rb":{"lines":[0]}}}}')
    end

    it 'rewrites the paths of the gitlab-foss project next to it' do
      rewrite

      expect(File.read(foss_file))
        .to eq('{"a":{"coverage":{"/builds/gitlab-org/security/gitlab/app/a.rb":{"lines":[0]}}}}')
    end
  end
end
