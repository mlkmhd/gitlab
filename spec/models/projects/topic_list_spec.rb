# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::TopicList, feature_category: :groups_and_projects do
  using RSpec::Parameterized::TableSyntax

  let_it_be_with_refind(:project) { create(:project) }

  describe '#names' do
    where(:value, :expected_names) do
      'topicA, topicB'           | %w[topicA topicB]
      ['topicA', ' topicB ', ''] | %w[topicA topicB]
      'topicA, , topicA'         | %w[topicA]
      'topicA, TOPICA, topicB'   | %w[topicA topicB]
      %w[TopicA topicA]          | %w[TopicA]
    end

    with_them do
      it 'normalizes the assigned value' do
        expect(described_class.new(project, value).names).to eq(expected_names)
      end
    end
  end

  describe '#validate_new_topics' do
    before_all do
      create(:topic, name: 'bx::code::c', slug: 'bxcodec', organization: project.organization)
      create(:topic, name: 'other organization', slug: 'otherorganization', organization: create(:organization))
    end

    where(:value, :expected_errors) do
      'bx::code::c++'         | ["'bx::code::c++' is invalid: Slug has already been taken"]
      'topic1, bx::code::c++' | ["'bx::code::c++' is invalid: Slug has already been taken"]
      'new topic, newtopic'   | ["'newtopic' is invalid: Slug has already been taken"]
      'café'                  | ["'café' is invalid: Name must only include ASCII characters"]
      'BX::CODE::C, topic1'   | []
      'bx::code::c, newtopic' | []
      'otherorganization'     | []
      ''                      | []
    end

    with_them do
      it 'adds an error on topics for each topic that cannot be created' do
        described_class.new(project, value).validate_new_topics

        expect(project.errors[:topics]).to eq(expected_errors)
      end
    end
  end

  context 'when the organization has a topic that Ruby and PostgreSQL lowercase differently' do
    # Ruby downcases U+0130 to "i" and a combining dot, PostgreSQL to "i".
    let_it_be_with_refind(:legacy_topic) do
      build(:topic, name: 'İstanbul', slug: 'istanbul', organization: project.organization).tap do |topic|
        topic.save!(validate: false)
      end
    end

    it 'does not validate it as a new topic' do
      described_class.new(project, 'İstanbul, café').validate_new_topics

      expect(project.errors[:topics]).to eq(["'café' is invalid: Name must only include ASCII characters"])
    end

    it 'assigns it to a project that does not have it', :aggregate_failures do
      expect(project.update(topic_list: 'İstanbul')).to be(true)
      expect(project.reload.topics).to contain_exactly(legacy_topic)
    end

    context 'when the project has it' do
      before_all do
        create(:project_topic, project: project, topic: legacy_topic)
      end

      it 'saves a list that keeps it, changed or not', :aggregate_failures do
        expect(project.update(topic_list: 'İstanbul')).to be(true)
        expect(project.update(topic_list: 'İstanbul, foo')).to be(true)
        expect(project.reload.topics).to contain_exactly(legacy_topic, have_attributes(name: 'foo'))
      end
    end
  end
end
