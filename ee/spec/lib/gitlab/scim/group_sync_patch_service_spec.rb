# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Scim::GroupSyncPatchService, feature_category: :system_access do
  let(:scim_group_uid) { SecureRandom.uuid }
  let(:service) { described_class.new(scim_group_uid: scim_group_uid, operations: operations) }

  describe '#execute' do
    shared_examples 'rejects the request' do |message|
      it 'returns an error without scheduling the worker' do
        expect(Authn::SyncScimGroupMembersWorker).not_to receive(:perform_async)

        result = service.execute

        expect(result).to be_error
        expect(result.message).to eq(message)
      end
    end

    context 'with add operation' do
      let_it_be(:user) { create(:user) }
      let_it_be(:identity) { create(:scim_identity, user: user, group: nil) }
      let(:operations) do
        [
          {
            op: 'Add',
            path: 'members',
            value: [{ value: identity.extern_uid }]
          }
        ]
      end

      it 'schedules the worker to add members' do
        expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
          .with(scim_group_uid, [user.id], 'add')

        service.execute
      end

      it 'returns success' do
        allow(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)

        result = service.execute

        expect(result).to be_success
      end

      context 'with case-insensitive operation' do
        let(:operations) do
          [
            {
              op: 'ADD',
              path: 'MEMBERS',
              value: [{ value: identity.extern_uid }]
            }
          ]
        end

        it 'schedules the worker correctly' do
          expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
            .with(scim_group_uid, [user.id], 'add')

          service.execute
        end
      end

      context 'with non-existent user identity' do
        let(:operations) do
          [
            {
              op: 'Add',
              path: 'members',
              value: [{ value: 'non-existent' }]
            }
          ]
        end

        it 'does not schedule the worker' do
          expect(Authn::SyncScimGroupMembersWorker).not_to receive(:perform_async)

          service.execute
        end
      end

      context 'with externalId operation' do
        let(:operations) do
          [
            {
              op: 'Add',
              path: 'externalId',
              value: scim_group_uid
            }
          ]
        end

        it 'does not schedule the worker' do
          expect(Authn::SyncScimGroupMembersWorker).not_to receive(:perform_async)

          service.execute
        end

        it 'returns success' do
          result = service.execute

          expect(result).to be_success
        end
      end

      context 'with a path other than members or externalId' do
        let(:operations) { [{ op: 'Add', path: 'displayName', value: 'engineering' }] }

        it 'does not schedule the worker' do
          expect(Authn::SyncScimGroupMembersWorker).not_to receive(:perform_async)

          expect(service.execute).to be_success
        end
      end

      context 'with members in a value without a path' do
        let(:operations) { [{ op: 'Add', value: { 'Members' => [{ value: identity.extern_uid }] } }] }

        it 'schedules the worker to add members' do
          expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
            .with(scim_group_uid, [user.id], 'add')

          expect(service.execute).to be_success
        end
      end

      context 'with a members filter path' do
        let(:operations) { [{ op: 'Add', path: "members[value eq \"#{identity.extern_uid}\"]" }] }

        it_behaves_like 'rejects the request',
          'Filter paths are only supported for removing a member with members[value eq "<id>"]'
      end
    end

    context 'with remove operation' do
      let_it_be(:user) { create(:user) }
      let_it_be(:identity) { create(:scim_identity, user: user, group: nil) }
      let(:operations) do
        [
          {
            op: 'Remove',
            path: 'members',
            value: [{ value: identity.extern_uid }]
          }
        ]
      end

      it 'schedules the worker to remove members' do
        expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
          .with(scim_group_uid, [user.id], 'remove')

        service.execute
      end

      it 'returns success' do
        allow(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)

        result = service.execute

        expect(result).to be_success
      end

      context 'with filter expression path' do
        let(:operations) do
          [
            {
              op: 'Remove',
              path: "members[value eq \"#{identity.extern_uid}\"]"
            }
          ]
        end

        it 'schedules the worker to remove the member' do
          expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
            .with(scim_group_uid, [user.id], 'remove')

          service.execute
        end

        context 'with case-insensitive path' do
          let(:operations) do
            [
              {
                op: 'Remove',
                path: "Members[VALUE EQ \"#{identity.extern_uid}\"]"
              }
            ]
          end

          it 'schedules the worker to remove the member' do
            expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
              .with(scim_group_uid, [user.id], 'remove')

            service.execute
          end
        end

        context 'with non-existent user identity' do
          let(:operations) do
            [
              {
                op: 'Remove',
                path: 'members[value eq "non-existent"]'
              }
            ]
          end

          it 'does not schedule the worker' do
            expect(Authn::SyncScimGroupMembersWorker).not_to receive(:perform_async)

            service.execute
          end
        end

        context 'with unsupported filter attribute' do
          let(:operations) do
            [
              {
                op: 'Remove',
                path: "members[display eq \"#{identity.extern_uid}\"]"
              }
            ]
          end

          it_behaves_like 'rejects the request',
            'Filter paths are only supported for removing a member with members[value eq "<id>"]'
        end
      end

      context 'with members path and no value' do
        let(:operations) { [{ op: 'Remove', path: 'members' }] }

        it 'schedules the worker to remove everyone synced through the SCIM group' do
          expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
            .with(scim_group_uid, [], 'replace')

          expect(service.execute).to be_success
        end
      end

      context 'without a path' do
        let(:operations) { [{ op: 'Remove', value: { members: [{ value: identity.extern_uid }] } }] }

        it_behaves_like 'rejects the request', 'Removing from a group requires a path'
      end

      context 'when removing all members is combined with another member change' do
        let(:operations) do
          [
            { op: 'Remove', path: 'members' },
            { op: 'Add', path: 'members', value: [{ value: identity.extern_uid }] }
          ]
        end

        it_behaves_like 'rejects the request',
          "Replacing or removing all group members can't be combined with other member changes " \
            "in the same request"
      end

      context 'when the same member is added and removed in the same request' do
        let(:operations) do
          [
            { op: 'Add', path: 'members', value: [{ value: identity.extern_uid }] },
            { op: 'Remove', path: "members[value eq \"#{identity.extern_uid.upcase}\"]" }
          ]
        end

        it_behaves_like 'rejects the request', "The same member can't be added and removed in the same request"
      end
    end

    context 'with replace operation' do
      let(:operations) do
        [
          {
            op: 'Replace',
            value: { id: scim_group_uid, displayName: 'engineering' }
          }
        ]
      end

      it 'does not schedule the worker' do
        expect(Authn::SyncScimGroupMembersWorker).not_to receive(:perform_async)

        service.execute
      end

      it 'returns success' do
        expect(service.execute).to be_success
      end

      context 'with displayName path' do
        let(:operations) { [{ op: 'Replace', path: 'displayName', value: 'engineering' }] }

        it 'does not schedule the worker' do
          expect(Authn::SyncScimGroupMembersWorker).not_to receive(:perform_async)

          service.execute
        end

        it 'returns success' do
          expect(service.execute).to be_success
        end
      end

      context 'with members path' do
        let_it_be(:user) { create(:user) }
        let_it_be(:identity) { create(:scim_identity, user: user, group: nil) }
        let(:operations) do
          [
            {
              op: 'Replace',
              path: 'members',
              value: [{ value: identity.extern_uid }]
            }
          ]
        end

        it 'schedules the worker to replace members' do
          expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
            .with(scim_group_uid, [user.id], 'replace')

          service.execute
        end

        it 'returns success' do
          allow(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)

          expect(service.execute).to be_success
        end

        context 'with case-insensitive path' do
          let(:operations) do
            [
              {
                op: 'REPLACE',
                path: 'MEMBERS',
                value: [{ value: identity.extern_uid }]
              }
            ]
          end

          it 'schedules the worker to replace members' do
            expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
              .with(scim_group_uid, [user.id], 'replace')

            service.execute
          end
        end

        context 'with an empty members list' do
          let(:operations) { [{ op: 'Replace', path: 'members', value: [] }] }

          it 'schedules the worker to replace members with no users' do
            expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
              .with(scim_group_uid, [], 'replace')

            service.execute
          end
        end

        context 'with a non-array value' do
          let(:operations) { [{ op: 'Replace', path: 'members', value: 'invalid' }] }

          it 'does not schedule the worker' do
            expect(Authn::SyncScimGroupMembersWorker).not_to receive(:perform_async)

            service.execute
          end
        end
      end

      context 'with members in a value without a path' do
        let_it_be(:user) { create(:user) }
        let_it_be(:identity) { create(:scim_identity, user: user, group: nil) }
        let(:operations) do
          [{ op: 'Replace', value: { displayName: 'engineering', members: [{ value: identity.extern_uid }] } }]
        end

        it 'schedules the worker to replace members' do
          expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
            .with(scim_group_uid, [user.id], 'replace')

          service.execute
        end

        context 'with a differently cased key' do
          let(:operations) { [{ op: 'Replace', value: { 'Members' => [] } }] }

          it 'schedules the worker to replace members with no users' do
            expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
              .with(scim_group_uid, [], 'replace')

            service.execute
          end
        end
      end

      context 'without a path and with a value that is not an object' do
        let(:operations) { [{ op: 'Replace', value: 'engineering' }] }

        it 'does not schedule the worker' do
          expect(Authn::SyncScimGroupMembersWorker).not_to receive(:perform_async)

          service.execute
        end

        it 'returns success' do
          expect(service.execute).to be_success
        end
      end

      context 'with a members filter path' do
        let(:operations) { [{ op: 'Replace', path: 'members[value eq "abc"]', value: {} }] }

        it_behaves_like 'rejects the request',
          'Filter paths are only supported for removing a member with members[value eq "<id>"]'
      end

      context 'when another operation in the same request uses an unsupported filter path' do
        let_it_be(:identity) { create(:scim_identity, user: create(:user), group: nil) }
        let(:operations) do
          [
            { op: 'Add', path: 'members', value: [{ value: identity.extern_uid }] },
            { op: 'Replace', path: 'members[value eq "abc"]', value: {} }
          ]
        end

        it_behaves_like 'rejects the request',
          'Filter paths are only supported for removing a member with members[value eq "<id>"]'
      end

      context 'when the members replace is combined with another member change' do
        let_it_be(:identity) { create(:scim_identity, user: create(:user), group: nil) }

        context 'with an add on members' do
          let(:operations) do
            [
              { op: 'Replace', path: 'members', value: [{ value: identity.extern_uid }] },
              { op: 'Add', path: 'members', value: [{ value: identity.extern_uid }] }
            ]
          end

          it_behaves_like 'rejects the request',
            "Replacing or removing all group members can't be combined with other member changes " \
              "in the same request"
        end

        context 'with a remove using a filter path' do
          let(:operations) do
            [
              { op: 'Remove', path: "members[value eq \"#{identity.extern_uid}\"]" },
              { op: 'Replace', path: 'members', value: [] }
            ]
          end

          it_behaves_like 'rejects the request',
            "Replacing or removing all group members can't be combined with other member changes " \
              "in the same request"
        end

        context 'with a second members replace' do
          let(:operations) do
            [
              { op: 'Replace', path: 'members', value: [] },
              { op: 'Replace', value: { members: [{ value: identity.extern_uid }] } }
            ]
          end

          it_behaves_like 'rejects the request',
            "Replacing or removing all group members can't be combined with other member changes " \
              "in the same request"
        end

        context 'with an operation that does not change members' do
          let(:operations) do
            [
              { op: 'Replace', path: 'displayName', value: 'engineering' },
              { op: 'Replace', path: 'members', value: [{ value: identity.extern_uid }] }
            ]
          end

          it 'schedules the worker to replace members' do
            expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
              .with(scim_group_uid, [identity.user_id], 'replace')

            expect(service.execute).to be_success
          end
        end
      end
    end

    context 'with members that are not objects with a string value' do
      where(:operations) do
        [
          [[{ op: 'Add', path: 'members', value: ['abc'] }]],
          [[{ op: 'Add', value: { members: ['abc'] } }]],
          [[{ op: 'Add', path: 'members', value: [{ display: 'abc' }] }]],
          [[{ op: 'Add', path: 'members', value: [{ value: 1 }] }]],
          [[{ op: 'Add', path: 'members', value: [{ value: ['abc'] }] }]],
          [[{ op: 'Add', path: 'members', value: { value: 'abc' } }]],
          [[{ op: 'Add', path: 'members' }]],
          [[{ op: 'Remove', path: 'members', value: ['abc'] }]],
          [[{ op: 'Replace', path: 'members', value: 'abc' }]],
          [[{ op: 'Replace', value: { members: [nil] } }]]
        ]
      end

      with_them do
        it_behaves_like 'rejects the request', 'Group members must be a list of objects that each have a string value'
      end
    end

    context 'with multiple operations' do
      let_it_be(:user1) { create(:user) }
      let_it_be(:user2) { create(:user) }
      let_it_be(:identity1) { create(:scim_identity, user: user1, group: nil) }
      let_it_be(:identity2) { create(:scim_identity, user: user2, group: nil) }
      let(:operations) do
        [
          {
            op: 'Add',
            path: 'members',
            value: [{ value: identity1.extern_uid }]
          },
          {
            op: 'Remove',
            path: 'members',
            value: [{ value: identity2.extern_uid }]
          }
        ]
      end

      it 'schedules workers for each operation' do
        expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
          .with(scim_group_uid, [user1.id], 'add')
        expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
          .with(scim_group_uid, [user2.id], 'remove')

        service.execute
      end
    end

    context 'with empty or invalid values' do
      let(:operations) do
        [
          {
            op: 'Add',
            path: 'members',
            value: []
          }
        ]
      end

      it 'does not schedule the worker' do
        expect(Authn::SyncScimGroupMembersWorker).not_to receive(:perform_async)

        service.execute
      end
    end

    context 'with an unsupported operation' do
      let(:operations) { [{ op: 'Move', path: 'members', value: [{ value: 'abc' }] }] }

      it 'does not schedule the worker' do
        expect(Authn::SyncScimGroupMembersWorker).not_to receive(:perform_async)

        expect(service.execute).to be_success
      end
    end

    context 'with a rename or an externalId change' do
      let_it_be(:saml_group_link) do
        create(:saml_group_link, saml_group_name: 'engineering', scim_group_uid: SecureRandom.uuid)
      end

      let(:scim_group_uid) { saml_group_link.scim_group_uid }

      where(:operations, :error_message) do
        [
          [
            [{ op: 'replace', value: { id: 'abc', displayName: 'platform' } }],
            "Renaming a group isn't supported. Create a SAML group link named \"platform\", " \
              "provision the group again from your identity provider, and then remove the old link."
          ],
          [
            [{ op: 'Replace', path: 'displayName', value: 'platform' }],
            "Renaming a group isn't supported. Create a SAML group link named \"platform\", " \
              "provision the group again from your identity provider, and then remove the old link."
          ],
          [
            [{ op: 'Add', path: 'externalId', value: 'another-id' }],
            "Changing the externalId of a group isn't supported"
          ]
        ]
      end

      with_them do
        it 'returns a mutability error without scheduling the worker' do
          expect(Authn::SyncScimGroupMembersWorker).not_to receive(:perform_async)

          result = service.execute

          expect(result).to be_error
          expect(result.message).to eq(error_message)
          expect(result.payload[:scim_type]).to eq('mutability')
        end
      end
    end
  end
end
