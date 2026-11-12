# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Gitlab::Scim::GroupPatchOperation, feature_category: :system_access do
  subject(:operation) { described_class.new(params) }

  describe 'the operation predicates' do
    context 'with a mixed-case op' do
      let(:params) { { op: 'Replace' } }

      it 'matches the op without case' do
        expect(operation.replace?).to be(true)
        expect(operation.add?).to be(false)
        expect(operation.remove?).to be(false)
      end
    end

    context 'with add' do
      let(:params) { { op: 'ADD' } }

      it { expect(operation.add?).to be(true) }
    end

    context 'with remove' do
      let(:params) { { op: 'remove' } }

      it { expect(operation.remove?).to be(true) }
    end

    context 'without an op' do
      let(:params) { {} }

      it 'matches no operation' do
        expect([operation.add?, operation.remove?, operation.replace?]).to all(be(false))
      end
    end
  end

  describe '#changes_members?' do
    where(:params, :changes_members) do
      [
        [{ op: 'add', path: 'members' }, true],
        [{ op: 'remove', path: 'MEMBERS[value eq "abc"]' }, true],
        [{ op: 'replace', path: 'displayName' }, false],
        [{ op: 'replace', value: { 'Members' => [] } }, true],
        [{ op: 'replace', value: { members: [{ value: 'abc' }] } }, true],
        [{ op: 'replace', value: { displayName: 'engineering' } }, false],
        [{ op: 'replace', value: 'engineering' }, false]
      ]
    end

    with_them do
      it { expect(operation.changes_members?).to be(changes_members) }
    end
  end

  describe '#supported_filter_path?' do
    where(:params, :supported) do
      [
        [{ op: 'remove', path: 'members[value eq "abc"]' }, true],
        [{ op: 'remove', path: 'Members[VALUE EQ "abc"]' }, true],
        [{ op: 'remove', path: 'members[display eq "abc"]' }, false],
        [{ op: 'add', path: 'members[value eq "abc"]' }, false],
        [{ op: 'replace', path: 'members[value eq "abc"]' }, false],
        [{ op: 'remove', path: 'members' }, true],
        [{ op: 'replace', value: {} }, true]
      ]
    end

    with_them do
      it { expect(operation.supported_filter_path?).to be(supported) }
    end
  end

  describe '#remove_without_path?' do
    where(:params, :without_path) do
      [
        [{ op: 'remove', value: { members: [] } }, true],
        [{ op: 'remove', path: 'members' }, false],
        [{ op: 'add', value: { members: [] } }, false]
      ]
    end

    with_them do
      it { expect(operation.remove_without_path?).to be(without_path) }
    end
  end

  describe '#removes_all_members?' do
    where(:params, :removes_all) do
      [
        [{ op: 'remove', path: 'members' }, true],
        [{ op: 'remove', path: 'members', value: [] }, false],
        [{ op: 'remove', path: 'members[value eq "abc"]' }, false],
        [{ op: 'replace', path: 'members' }, false]
      ]
    end

    with_them do
      it { expect(operation.removes_all_members?).to be(removes_all) }
    end
  end

  describe '#full_member_sync?' do
    where(:params, :full_sync) do
      [
        [{ op: 'replace', path: 'members', value: [] }, true],
        [{ op: 'replace', value: { members: [] } }, true],
        [{ op: 'remove', path: 'members' }, true],
        [{ op: 'replace', path: 'displayName', value: 'engineering' }, false],
        [{ op: 'add', path: 'members', value: [] }, false]
      ]
    end

    with_them do
      it { expect(operation.full_member_sync?).to be(full_sync) }
    end
  end

  describe '#valid_members?' do
    where(:params, :valid) do
      [
        [{ op: 'add', path: 'members', value: [{ value: 'abc' }] }, true],
        [{ op: 'add', path: 'members', value: [] }, true],
        [{ op: 'add', path: 'members', value: ['abc'] }, false],
        [{ op: 'add', path: 'members', value: [{ display: 'abc' }] }, false],
        [{ op: 'add', path: 'members', value: [{ value: '' }] }, false],
        [{ op: 'add', path: 'members', value: [{ value: 1 }] }, false],
        [{ op: 'add', path: 'members', value: [{ value: ['abc'] }] }, false],
        [{ op: 'add', path: 'members', value: { value: 'abc' } }, false],
        [{ op: 'add', path: 'members', value: 'abc' }, false],
        [{ op: 'add', path: 'members' }, false],
        [{ op: 'add', value: { members: [{ value: 'abc' }] } }, true],
        [{ op: 'add', value: { members: ['abc'] } }, false],
        [{ op: 'add', value: { members: nil } }, false],
        [{ op: 'replace', value: { members: [{ value: 'abc' }] } }, true],
        [{ op: 'replace', value: { displayName: 'engineering' } }, true],
        [{ op: 'replace', path: 'displayName', value: 'engineering' }, true],
        [{ op: 'remove', path: 'members' }, true],
        [{ op: 'remove', path: 'members[value eq "abc"]' }, true]
      ]
    end

    with_them do
      it { expect(operation.valid_members?).to be(valid) }
    end
  end

  describe '#members' do
    where(:params, :members) do
      [
        [{ op: 'add', path: 'Members', value: [{ value: 'abc' }] }, [{ value: 'abc' }]],
        [{ op: 'add', value: { 'Members' => [{ value: 'abc' }] } }, [{ value: 'abc' }]],
        [{ op: 'add', path: 'externalId', value: 'abc' }, nil],
        [{ op: 'add', path: 'members', value: 'abc' }, 'abc'],
        [{ op: 'remove', path: 'members', value: [{ value: 'abc' }] }, [{ value: 'abc' }]],
        [{ op: 'remove', path: 'Members[VALUE EQ "Ab-12-Cd"]' }, [{ value: 'Ab-12-Cd' }]],
        [{ op: 'remove', path: 'members[display eq "abc"]' }, nil],
        [{ op: 'replace', path: 'members', value: [] }, []],
        [{ op: 'replace', value: { members: [{ value: 'abc' }] } }, [{ value: 'abc' }]],
        [{ op: 'replace', value: { displayName: 'engineering' } }, nil],
        [{ op: 'replace', value: [{ value: 'abc' }] }, nil],
        [{ op: 'replace', path: 'displayName', value: 'engineering' }, nil]
      ]
    end

    with_them do
      it { expect(operation.members).to eq(members) }
    end
  end

  describe '#member_extern_uids' do
    where(:params, :extern_uids) do
      [
        [{ op: 'add', path: 'members', value: [{ value: 'abc' }, { value: 'def' }] }, %w[abc def]],
        [{ op: 'add', path: 'members', value: ['abc'] }, []],
        [{ op: 'remove', path: 'members[value eq "abc"]' }, ['abc']],
        [{ op: 'replace', path: 'members', value: [] }, []],
        [{ op: 'replace', path: 'displayName', value: 'engineering' }, []]
      ]
    end

    with_them do
      it { expect(operation.member_extern_uids).to eq(extern_uids) }
    end
  end

  describe '#display_name' do
    where(:params, :display_name) do
      [
        [{ op: 'replace', value: { id: 'abc', displayName: 'engineering' } }, 'engineering'],
        [{ op: 'Replace', path: 'displayName', value: 'engineering' }, 'engineering'],
        [{ op: 'replace', value: { 'DisplayName' => 'engineering' } }, 'engineering'],
        [{ op: 'replace', path: 'members', value: [] }, nil],
        [{ op: 'replace', value: { members: [] } }, nil],
        [{ op: 'remove', path: 'displayName' }, nil]
      ]
    end

    with_them do
      it { expect(operation.display_name).to eq(display_name) }
    end
  end

  describe '#external_id' do
    where(:params, :external_id) do
      [
        [{ op: 'Add', path: 'externalId', value: 'abc' }, 'abc'],
        [{ op: 'replace', value: { externalId: 'abc', displayName: 'engineering' } }, 'abc'],
        [{ op: 'replace', path: 'displayName', value: 'engineering' }, nil],
        [{ op: 'remove', path: 'externalId' }, nil]
      ]
    end

    with_them do
      it { expect(operation.external_id).to eq(external_id) }
    end
  end
end
