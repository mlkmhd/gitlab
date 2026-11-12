# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Participable, feature_category: :team_planning do
  let_it_be(:user1) { create(:user) }
  let_it_be(:user2) { create(:user) }
  let_it_be(:user3) { create(:user) }

  let_it_be(:project) { create(:project, :public) }
  let_it_be_with_refind(:private_project) { create(:project, :private) }

  let(:model) do
    Class.new do
      include Participable
    end
  end

  let(:instance) { model.new }

  describe '.participant' do
    it 'adds the participant attributes to the existing list' do
      model.participant(:foo)
      model.participant(:bar)

      expect(model.participant_attrs).to eq([:foo, :bar])
    end
  end

  describe '#participants' do
    it 'returns the list of participants' do
      model.participant(:foo)
      model.participant(:bar)

      expect(instance).to receive(:foo).and_return(user2)
      expect(instance).to receive(:bar).and_return(user3)
      expect(instance).to receive(:project).exactly(4).and_return(project)

      participants = instance.participants(user1)

      expect(participants).to include(user2)
      expect(participants).to include(user3)
    end

    it 'caches the list of filtered participants' do
      expect(instance).to receive(:all_participants_hash).once.and_return({})
      expect(instance).to receive(:filter_by_ability).once

      instance.participants(user1)
      instance.participants(user1)
    end

    it 'supports attributes returning another Participable' do
      other_model = Class.new do
        include Participable
      end

      other_model.participant(:bar)
      model.participant(:foo)

      other = other_model.new

      expect(instance).to receive(:foo).and_return(other)
      expect(other).to receive(:bar).and_return(user2)
      expect(instance).to receive(:project).exactly(4).and_return(project)

      expect(instance.participants(user1)).to eq([user2])
    end

    context 'when using a Proc as an attribute' do
      it 'calls the supplied Proc' do
        user_arg = nil
        ext_arg = nil

        model.participant ->(user, ext) do
          user_arg = user
          ext_arg = ext
        end

        expect(instance).to receive(:project).exactly(4).and_return(project)

        instance.participants(user1)

        expect(user_arg).to eq(user1)
        expect(ext_arg).to be_an_instance_of(Gitlab::ReferenceExtractor)
      end
    end

    context 'when participable is a personal snippet' do
      let(:model) { PersonalSnippet }
      let(:instance) { model.new(author: user1) }

      before do
        allow(model).to receive(:participant_attrs).and_return([:foo, :bar])
      end

      it 'returns the list of participants' do
        expect(instance).to receive(:foo).and_return(user1)
        expect(instance).to receive(:bar).and_return(user2)

        participants = instance.participants(user1)
        expect(participants).to contain_exactly(user1)
      end
    end

    context 'when participable is not readable by the current user' do
      before_all do
        private_project.add_developer(user2)
      end

      it 'returns participants with project/group access' do
        allow(model).to receive(:participant_attrs).and_return([:bar])

        allow(instance).to receive_message_chain(:model_name, :element) { 'class' }
        allow(instance).to receive(:bar).and_return(user2)
        expect(instance).to receive(:project).exactly(4).and_return(private_project)

        expect(instance.participants(user1)).to contain_exactly(user2)
      end
    end

    context 'when participable is not readable by a participant' do
      before_all do
        private_project.add_developer(user1)
      end

      it 'does not return participants without project/group access' do
        allow(model).to receive(:participant_attrs).and_return([:bar])

        allow(instance).to receive_message_chain(:model_name, :element) { 'class' }
        allow(instance).to receive(:bar).and_return(user2)
        expect(instance).to receive(:project).exactly(4).and_return(private_project)

        expect(instance.participants(user1)).to be_empty
      end
    end

    context 'when participable is confidential' do
      before_all do
        private_project.add_guest(user1)
        private_project.add_developer(user2)
      end

      context 'when participable is Issue' do
        let(:model) { Issue }
        let(:instance) { model.new(author: user1, project: private_project, confidential: true) }

        it 'filters participants based on confidential issue access' do
          allow(model).to receive(:participant_attrs).and_return([:foo, :bar])

          allow(instance).to receive_messages(foo: user1, bar: user2)

          expect(instance.participants(user2)).to contain_exactly(user2)
        end
      end

      context 'when participable is non-Issue' do
        it 'filters participants based on regular project/group access instead of confidential issue access' do
          allow(model).to receive(:participant_attrs).and_return([:foo, :bar])

          allow(instance).to receive_message_chain(:model_name, :element) { 'class' }
          allow(instance).to receive_messages(
            confidential?: true,
            resource_parent: private_project,
            foo: user1,
            bar: user2
          )
          expect(instance).to receive(:project).exactly(4).and_return(private_project)

          expect(instance.participants(user2)).to contain_exactly(user1, user2)
        end
      end
    end

    context 'when participable is a group level object' do
      let(:group) { create(:group, :private) }

      it 'returns the list of participants' do
        allow(model).to receive(:participant_attrs).and_return([:foo, :bar])

        group.add_reporter(user1)
        group.add_reporter(user3)

        allow(instance).to receive_message_chain(:model_name, :element) { 'class' }
        expect(instance).to receive(:foo).and_return(user2)
        expect(instance).to receive(:bar).and_return(user3)
        expect(instance).to receive(:project).exactly(3).and_return(nil)
        expect(instance).to receive(:namespace).exactly(2).and_return(group)

        participants = instance.participants(user1)

        expect(participants).not_to include(user1) # not returned by participant attr
        expect(participants).not_to include(user2) # not a member of group
        expect(participants).to include(user3) # member of group
      end
    end

    context 'when participable is neither project nor group level object' do
      let(:group) { create(:group, :private) }

      it 'returns no participants' do
        allow(model).to receive(:participant_attrs).and_return([:foo])

        user = create(:user)

        group.add_reporter(user)

        allow(instance).to receive_message_chain(:model_name, :element) { 'class' }
        expect(instance).to receive(:foo).and_return(user)
        expect(instance).to receive(:project).exactly(3).and_return(nil)

        # user is returned by participant attr and is a member of the group,
        # but participable model is neither a group or project object
        participants = instance.participants(user)

        expect(participants).to be_empty
      end
    end

    context 'with multiple system notes from the same author and mentioned_users' do
      it 'skips expensive checks if the author is already in participants list' do
        allow(model).to receive(:participant_attrs).and_return([:notes])

        note1 = build(:system_note, author: user1)
        note2 = build(:system_note, author: user1) # only skip system notes with no mentioned users
        note3 = build(:system_note, author: user1, note: "assigned to #{user2.to_reference}")
        note4 = build(:note, author: user2)

        allow(instance).to receive_message_chain(:model_name, :element) { 'class' }
        allow(instance).to receive_messages(project: project, notes: [note1, note2, note3, note4])

        allow(Ability).to receive(:allowed?).with(anything, :read_project, anything).and_return(true)
        allow(Ability).to receive(:allowed?).with(anything, :read_note, anything).exactly(3).times.and_return(true)
        expect(instance.participants(user1)).to contain_exactly(user1, user2)
      end
    end

    it_behaves_like 'participants for issuable with read ability', :issue
    it_behaves_like 'participants for issuable with read ability', :merge_request
  end

  describe '#participant?' do
    before do
      allow(model).to receive(:participant_attrs).and_return([:foo, :bar])
    end

    it 'returns whether the user is a participant' do
      allow(instance).to receive_messages(foo: user2, bar: user3, project: project)

      expect(instance.participant?(user1)).to be false
      expect(instance.participant?(user2)).to be true
      expect(instance.participant?(user3)).to be true
    end

    it 'caches the list of raw participants' do
      expect(instance).to receive(:raw_participants).once.and_return([])
      expect(instance).to receive(:project).exactly(4).and_return(project)

      instance.participant?(user1)
      instance.participant?(user1)
    end

    context 'when the user is a direct participant of an issuable' do
      let_it_be_with_refind(:issuable_project) { create(:project, :public) }
      let_it_be_with_refind(:author) { create(:user) }
      let_it_be_with_refind(:assignee) { create(:user) }
      let_it_be_with_refind(:reviewer) { create(:user) }

      let_it_be_with_refind(:merge_request) do
        create(:merge_request, source_project: issuable_project, author: author, assignees: [assignee],
          reviewers: [reviewer])
      end

      let_it_be_with_refind(:issue) { create(:issue, project: issuable_project, author: author, assignees: [assignee]) }

      it 'skips the full participants check for the author and loaded assignees and reviewers' do
        loaded_merge_request = MergeRequest.preload(:assignees, :reviewers).find(merge_request.id)
        loaded_issue = Issue.preload(:assignees).find(issue.id)

        [loaded_merge_request, loaded_issue].each do |issuable|
          expect(issuable).not_to receive(:raw_participants)
        end

        expect(loaded_merge_request.participant?(author)).to be true
        expect(loaded_merge_request.participant?(assignee)).to be true
        expect(loaded_merge_request.participant?(reviewer)).to be true
        expect(loaded_issue.participant?(author)).to be true
        expect(loaded_issue.participant?(assignee)).to be true
      end

      it 'runs no queries for the author once read access is cached', :request_store do
        loaded_merge_request = MergeRequest.preload(:author, :target_project).find(merge_request.id)
        author.can?(:read_project, loaded_merge_request.project)

        expect { loaded_merge_request.participant?(author) }.not_to exceed_all_query_limit(0)
      end

      it 'falls through to the full participants check for other users when associations are loaded' do
        loaded_merge_request = MergeRequest.preload(:assignees, :reviewers).find(merge_request.id)

        expect(loaded_merge_request).to receive(:raw_participants).once.and_call_original

        expect(loaded_merge_request.participant?(create(:user))).to be false
      end

      it 'falls through to the full participants check when reviewers are not loaded' do
        unloaded_merge_request = MergeRequest.find(merge_request.id)

        expect(unloaded_merge_request).to receive(:raw_participants).once.and_call_original

        expect(unloaded_merge_request.participant?(reviewer)).to be true
      end

      it 'returns false for the author when the author cannot read the issuable' do
        private_issue = create(:issue, project: create(:project, :private), author: author)

        expect(private_issue.participant?(author)).to be false
      end
    end

    context 'when participable is a personal snippet' do
      let(:model) { PersonalSnippet }
      let(:instance) { model.new(author: user1) }

      it 'returns whether the user is a participant' do
        allow(instance).to receive_messages(foo: user1, bar: user2)

        expect(instance.participant?(user1)).to be true
        expect(instance.participant?(user2)).to be false
        expect(instance.participant?(user3)).to be false
      end
    end

    context 'when participable is a group level object' do
      let(:group) { create(:group, :private) }

      before do
        group.add_reporter(user1)
        group.add_reporter(user2)
      end

      it 'returns whether the user is a participant' do
        allow(instance).to receive_messages(foo: user1, bar: user3, project: nil, namespace: group)

        expect(instance.participant?(user1)).to be true # returned by participant attr and a member of group
        expect(instance.participant?(user2)).to be false # returned by participant attr
        expect(instance.participant?(user3)).to be false # not a member of group
      end

      context 'when participable is neither project nor group level object' do
        it 'returns whether the user is a participant' do
          allow(instance).to receive_messages(foo: user1, project: nil)

          # user1 is returned by participant attr and is a member of group,
          # but participable model is neither a group or project object
          expect(instance.participant?(user1)).to be false
        end
      end
    end
  end
end
