# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::Taggable, feature_category: :continuous_integration do
  let_it_be(:taggings_model) do
    Class.new(Ci::ApplicationRecord) do |_model|
      connection.create_table :_test_gitlab_ci_taggings, force: true do |t|
        t.integer :tag_id
        t.integer :test_ci_taggable_id

        t.index [:tag_id, :test_ci_taggable_id], unique: true, name: '_test_taggable_idx'
      end

      self.table_name = '_test_gitlab_ci_taggings'

      def self.name
        'TestCiTaggings'
      end

      include BulkInsertSafe

      belongs_to :tag, class_name: 'Ci::Tag', optional: false
    end
  end

  let_it_be(:taggable_model) do
    Class.new(Ci::ApplicationRecord) do |_model|
      connection.create_table :_test_gitlab_ci_taggable, force: true do |t|
        t.string :name
      end

      self.table_name = '_test_gitlab_ci_taggable'

      def self.name
        'TestCiTaggable'
      end

      include Ci::Taggable
    end
  end

  let_it_be(:configuration_class) do
    Class.new do
      attr_accessor :join_model, :unique_by

      def attributes_map(record)
        { test_ci_taggable_id: record.id }
      end

      def uses_taggings?
        true
      end
    end
  end

  let_it_be(:configuration) do
    configuration_class.new.tap do |c|
      c.join_model = taggings_model
      c.unique_by = [:tag_id, :test_ci_taggable_id]
    end
  end

  let(:taggable_record) { taggable_model.new(name: 'tags') }

  before do
    taggable_model.has_many :taggings, anonymous_class: taggings_model
    taggable_model.has_many :tags, class_name: 'Ci::Tag', through: :taggings, source: :tag

    taggings_model.scope :scoped_taggables, -> {
      where('_test_gitlab_ci_taggings.test_ci_taggable_id = _test_gitlab_ci_taggable.id')
    }
    taggings_model.scope :scoped_taggables_in_partition, -> { scoped_taggables } # the test table has no partitions

    allow(taggable_model).to receive(:taggings_join_model) { taggings_model }

    config = instance_double(Gitlab::Ci::Tags::BulkInsert::ConfigurationFactory, build: configuration)

    allow(Gitlab::Ci::Tags::BulkInsert::ConfigurationFactory).to receive(:new)
      .with(an_instance_of(taggable_model)).and_return(config)
  end

  it { expect(taggable_record).to have_many(:taggings) }
  it { expect(taggable_record).to have_many(:tags).class_name('Ci::Tag').through(:taggings) }

  it { expect(taggable_record.tag_list).to be_empty }
  it { expect(taggable_record.tag_list).to be_a(Gitlab::Ci::Tags::TagList) }

  it 'sets the tag list' do
    taggable_record.tag_list = 'ruby, docker, postgres'

    expect(taggable_record.tag_list).to match_array(%w[ruby docker postgres])
    expect(taggable_record.tag_list).to be_a(Gitlab::Ci::Tags::TagList)
  end

  it 'persists the tag list' do
    taggable_record.tag_list = 'ruby, docker, postgres'

    expect { taggable_record.save! }.to change { Ci::Tag.count }.by(3)
  end

  it 'loads the tag list' do
    taggable_record.tag_list = 'ruby, docker, postgres'
    taggable_record.save!
    fresh_record = taggable_model.find(taggable_record.id)

    expect(fresh_record.tag_list).to match_array(%w[ruby docker postgres])
    expect(fresh_record.tags).to be_all(Ci::Tag)
  end

  it 'removes unwanted tags from the list' do
    taggable_record.tag_list = 'ruby, docker, postgres'
    taggable_record.save!

    taggable_record.tag_list = 'ruby, docker'
    expect { taggable_record.save! }
      .to change { taggings_model.count }.by(-1)

    expect(taggable_record.reload.tag_list).to match_array(%w[ruby docker])
  end

  it 'updates the tag list' do
    taggable_record.tag_list = 'ruby, docker, postgres'
    taggable_record.save!

    taggable_record.tag_list = 'ruby, docker, elasticsearch, golang'

    expect { taggable_record.save! }
      .to change { Ci::Tag.count }.by(2)
      .and change { taggings_model.count }.by(1)

    expect(taggable_record.reload.tag_list).to match_array(%w[ruby docker elasticsearch golang])
  end

  describe 'tag scopes' do
    let!(:tags) { taggable_model.create!(name: 'tags', tag_list: 'ruby, docker, postgres') }
    let!(:other_tags) { taggable_model.create!(name: 'other tags', tag_list: 'ruby, golang') }

    shared_examples 'filtering by tag names' do
      describe '.tagged_with' do
        it { expect(taggable_model.tagged_with('ruby')).to match_array([tags, other_tags]) }
        it { expect(taggable_model.tagged_with('ruby, docker')).to match_array([tags]) }
        it { expect(taggable_model.tagged_with(%w[ruby docker])).to match_array([tags]) }
        it { expect(taggable_model.tagged_with(%w[ruby docker golang])).to be_empty }
        it { expect(taggable_model.tagged_with('ruby, ruby')).to match_array([tags, other_tags]) }
        it { expect(taggable_model.tagged_with('ruby, unknown')).to be_empty }
        it { expect(taggable_model.tagged_with('')).to match_array([tags, other_tags]) }
        it { expect(taggable_model.tagged_with('uby', like_search_enabled: false)).to be_empty }
        it { expect(taggable_model.tagged_with('uby', like_search_enabled: true)).to match_array([tags, other_tags]) }
        it { expect(taggable_model.tagged_with('uby')).to be_empty }
      end

      describe '.with_tag' do
        it { expect(taggable_model.with_tag('docker')).to match_array([tags]) }
        it { expect(taggable_model.with_tag('unknown')).to be_empty }
        it { expect(taggable_model.with_tag('ola', like_search_enabled: true)).to match_array([other_tags]) }
      end
    end

    it_behaves_like 'filtering by tag names'

    it 'filters on the looked-up tag ID' do
      sql = taggable_model.with_tag('docker').to_sql

      expect(sql).to include("tag_id\" = #{Ci::Tag.find_by(name: 'docker').id}")
      expect(sql).not_to include('FROM "tags"')
    end

    it { expect(taggable_model.with_all_tags_by_name(%w[ruby ruby])).to match_array([tags, other_tags]) }

    it 'skips the taggables query when a tag does not exist' do
      relation = taggable_model.tagged_with('ruby, unknown')

      expect { relation.to_a }.not_to exceed_query_limit(0)
    end

    context 'when ci_runner_tag_filter_by_tag_ids is disabled' do
      before do
        stub_feature_flags(ci_runner_tag_filter_by_tag_ids: false)
      end

      it_behaves_like 'filtering by tag names'
    end
  end

  describe '#reload' do
    before do
      taggable_record.tag_list = 'ruby, docker, postgres'
      taggable_record.save!
    end

    it { expect { taggable_record.reload }.to change { taggable_record.tag_list.object_id } }
  end
end
