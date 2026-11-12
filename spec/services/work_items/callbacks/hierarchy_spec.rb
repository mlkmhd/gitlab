# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::Callbacks::Hierarchy, feature_category: :portfolio_management do
  let_it_be(:user, freeze: false) { create(:user) }
  let_it_be(:project, freeze: false) { create(:project) }

  let_it_be(:work_item, freeze: false) { create(:work_item, project: project) }
  let_it_be(:parent_work_item, freeze: false) { create(:work_item, project: project) }
  let_it_be(:child_work_item, freeze: false) { create(:work_item, :task, project: project) }
  let_it_be(:existing_link, freeze: false) do
    create(:parent_link, work_item: child_work_item, work_item_parent: work_item)
  end

  let(:callback) { described_class.new(issuable: work_item, current_user: user, params: params) }
  let(:not_found_error) { 'No matching work item found. Make sure that you are adding a valid work item ID.' }

  before_all do
    # Ensure support bot user is created so creation doesn't count towards query limit
    # and we don't try to obtain an exclusive lease within a transaction.
    # See https://gitlab.com/gitlab-org/gitlab/-/issues/509629
    create(:support_bot)
  end

  shared_examples 'raises a callback error' do |message_arg|
    it { expect { subject }.to raise_error(::Issuable::Callbacks::Base::Error, message_arg || message) }
  end

  describe '#after_create' do
    subject { callback.after_create }

    context 'when invalid params are present' do
      let(:params) { { other_parent: 'parent_work_item' } }

      it_behaves_like 'raises a callback error', 'One or more arguments are invalid: other_parent.'
    end
  end

  describe '#after_update' do
    subject(:after_update_callback) { callback.after_update }

    context 'when invalid params are present' do
      let(:params) { { other_parent: 'parent_work_item' } }

      it_behaves_like 'raises a callback error', 'One or more arguments are invalid: other_parent.'
    end

    context 'when multiple params are present' do
      it_behaves_like 'raises a callback error', 'One and only one of children, parent or remove_child is required' do
        let(:params) { { parent: parent_work_item, children: [child_work_item] } }
      end

      it_behaves_like 'raises a callback error', 'One and only one of children, parent or remove_child is required' do
        let(:params) { { parent: parent_work_item, remove_child: child_work_item } }
      end

      it_behaves_like 'raises a callback error', 'One and only one of children, parent or remove_child is required' do
        let(:params) { { remove_child: child_work_item, children: [child_work_item] } }
      end
    end

    context 'when relative position params are incomplete' do
      context 'when only adjacent_work_item is present' do
        let(:params) do
          { parent: parent_work_item, adjacent_work_item: child_work_item }
        end

        it_behaves_like 'raises a callback error', described_class::INVALID_RELATIVE_POSITION_ERROR
      end

      context 'when only relative_position is present' do
        let(:params) do
          { parent: parent_work_item, relative_position: 'AFTER' }
        end

        it_behaves_like 'raises a callback error', described_class::INVALID_RELATIVE_POSITION_ERROR
      end
    end

    context 'when updating children' do
      let_it_be(:child_work_item2, freeze: false) { create(:work_item, :task, project: project) }
      let_it_be(:child_work_item3, freeze: false) { create(:work_item, :task, project: project) }
      let_it_be(:child_work_item4, freeze: false) { create(:work_item, :task, project: project) }

      context 'when user has insufficient permissions to link work items' do
        let(:params) { { children: [child_work_item4] } }

        it_behaves_like 'raises a callback error' do
          let(:message) { not_found_error }
        end
      end

      context 'when user has sufficient permissions to link work item' do
        before_all do
          project.add_developer(user)
        end

        context 'with valid children params' do
          let(:params) { { children: [child_work_item2, child_work_item3] } }

          it 'correctly sets work item parent' do
            after_update_callback

            expect(work_item.reload.work_item_children)
              .to contain_exactly(child_work_item, child_work_item2, child_work_item3)
          end

          context 'when relative_position and adjacent_work_item are given' do
            context 'with BEFORE value' do
              let(:params) do
                { children: [child_work_item3], relative_position: 'BEFORE', adjacent_work_item: child_work_item }
              end

              it_behaves_like 'raises a callback error', described_class::CHILDREN_REORDERING_ERROR
            end

            context 'with AFTER value' do
              let(:params) do
                { children: [child_work_item2], relative_position: 'AFTER', adjacent_work_item: child_work_item }
              end

              it_behaves_like 'raises a callback error', described_class::CHILDREN_REORDERING_ERROR
            end
          end
        end

        context 'with remove_child param' do
          let(:params) { { remove_child: [child_work_item] } }

          it 'correctly removes the work item child' do
            expect { after_update_callback }.to change { WorkItems::ParentLink.count }.by(-1)

            expect(work_item.reload.work_item_children).to be_empty
          end
        end

        context 'when child is already assigned' do
          let(:params) { { children: [child_work_item] } }

          it_behaves_like 'raises a callback error', 'Work item(s) already assigned'
        end

        context 'when child type is invalid' do
          let_it_be(:child_issue, freeze: false) { create(:work_item, project: project) }

          let(:params) { { children: [child_issue] } }

          it_behaves_like 'raises a callback error' do
            let(:message) do
              "#{child_issue.to_reference} cannot be added: it's not allowed to add this type of parent item"
            end
          end
        end

        context 'with the add children limits' do
          let(:params) { { children: [child_work_item2, child_work_item3] } }

          context 'when more children than the per request cap are given' do
            before do
              stub_const("#{described_class}::MAX_CHILDREN_PER_REQUEST", 1)
            end

            it_behaves_like 'raises a callback error', 'No more than 1 child items can be added at the same time.'

            it 'does not add any children' do
              expect { after_update_callback }.to raise_error(::Issuable::Callbacks::Base::Error)

              expect(work_item.reload.work_item_children).to contain_exactly(child_work_item)
            end
          end

          context 'when the user is rate limited', :clean_gitlab_redis_rate_limiting do
            before do
              allow(::Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
              allow(::Gitlab::ApplicationRateLimiter).to receive(:throttled?)
                .with(described_class::ADD_CHILDREN_RATE_LIMIT_KEY, scope: { user: user }, cost: 2)
                .and_return(true)
            end

            it 'raises a rate limited error and does not add any children' do
              expect { after_update_callback }.to raise_error(::RateLimitedService::RateLimitedError)

              expect(work_item.reload.work_item_children).to contain_exactly(child_work_item)
            end

            context 'when skip_add_children_limits is set' do
              let(:new_children) { create_list(:work_item, 2, :task, project: project) }
              let(:params) { { children: new_children, skip_add_children_limits: true } }

              it 'adds the children' do
                after_update_callback

                expect(work_item.reload.work_item_children).to contain_exactly(child_work_item, *new_children)
              end
            end
          end

          context 'when one request has more children than the per minute limit', :clean_gitlab_redis_rate_limiting do
            before do
              stub_application_setting(work_item_hierarchy_add_children_limit: 1)
            end

            it 'charges each child against the limit' do
              expect { after_update_callback }.to raise_error(::RateLimitedService::RateLimitedError)

              expect(work_item.reload.work_item_children).to contain_exactly(child_work_item)
            end
          end

          context 'when the work_item_hierarchy_add_children_limits feature flag is disabled' do
            let(:new_children) { create_list(:work_item, 2, :task, project: project) }
            let(:params) { { children: new_children } }

            before do
              stub_feature_flags(work_item_hierarchy_add_children_limits: false)
              stub_const("#{described_class}::MAX_CHILDREN_PER_REQUEST", 1)
            end

            it 'does not enforce the cap and counts the children in log mode' do
              allow(::Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
              expect(::Gitlab::ApplicationRateLimiter).to receive(:throttled?)
                .with(described_class::ADD_CHILDREN_RATE_LIMIT_KEY, scope: { user: user }, cost: 2).and_call_original

              after_update_callback

              expect(work_item.reload.work_item_children).to contain_exactly(child_work_item, *new_children)
            end

            context 'when the request is over the per minute limit', :clean_gitlab_redis_rate_limiting,
              :request_store do
              before do
                stub_application_setting(work_item_hierarchy_add_children_limit: 1)
              end

              it 'adds the children and records the log entry' do
                after_update_callback

                expect(work_item.reload.work_item_children).to contain_exactly(child_work_item, *new_children)
                expect(::Gitlab::Instrumentation::RateLimitState.payload).to eq(
                  rate_limit_state: %w[
                    applimiter_work_item_hierarchy_add_children:limit_work_item_hierarchy_add_children_by_user_log:log
                  ]
                )
              end
            end
          end
        end
      end
    end

    context 'when updating parent' do
      let_it_be(:work_item, freeze: false) { create(:work_item, :task, project: project) }

      let(:params) { { parent: parent_work_item } }

      context 'when user has insufficient permissions to link work items' do
        it_behaves_like 'raises a callback error' do
          let(:message) { not_found_error }
        end
      end

      context 'when user has sufficient permissions to link work item' do
        before_all do
          project.add_developer(user)
        end

        it 'correctly sets new parent' do
          after_update_callback

          expect(work_item.work_item_parent).to eq(parent_work_item)
        end

        context 'when parent is nil' do
          let(:params) { { parent: nil } }

          it 'removes the work item parent if present' do
            work_item.update!(work_item_parent: parent_work_item)

            expect do
              after_update_callback
              work_item.reload
            end.to change { work_item.work_item_parent }.from(parent_work_item).to(nil)
          end

          it 'does not raise an error if parent not present', :aggregate_failures do
            work_item.update!(work_item_parent: nil)

            expect { after_update_callback }.not_to raise_error

            expect(work_item.reload.work_item_parent).to be_nil
          end
        end

        context 'when type is invalid' do
          let_it_be(:parent_task, freeze: false) { create(:work_item, :task, project: project) }

          let(:params) { { parent: parent_task } }

          it_behaves_like 'raises a callback error' do
            let(:message) do
              "#{parent_task.to_reference} cannot be added: it's not allowed to add this type of parent item"
            end
          end
        end

        context 'with positioning arguments' do
          let_it_be_with_reload(:adjacent) { create(:work_item, :task, project: project) }

          let_it_be_with_reload(:adjacent_link) do
            create(:parent_link, work_item: adjacent, work_item_parent: parent_work_item)
          end

          let(:params) { { parent: parent_work_item, adjacent_work_item: adjacent, relative_position: 'AFTER' } }

          it 'correctly sets new parent and position' do
            after_update_callback

            expect(work_item.work_item_parent).to eq(parent_work_item)
            expect(work_item.parent_link.relative_position).to be > adjacent_link.relative_position
          end

          context 'when other hierarchy adjacent is provided' do
            let_it_be(:other_hierarchy_adjacent, freeze: false) { create(:parent_link).work_item }

            let(:params) do
              { parent: parent_work_item, adjacent_work_item: other_hierarchy_adjacent, relative_position: 'AFTER' }
            end

            it_behaves_like 'raises a callback error', described_class::UNRELATED_ADJACENT_HIERARCHY_ERROR
          end
        end
      end
    end
  end
end
