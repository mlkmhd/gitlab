# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Duo::CodeReview::Availability::Project, feature_category: :dap_code_review do
  using RSpec::Parameterized::TableSyntax

  let(:project) { build_stubbed(:project) }

  describe '#available?' do
    subject(:available) { described_class.new(project).available? }

    where(:duo_features_enabled, :foundational_flows_enabled, :dap_available, :duo_enterprise, :expected) do
      false | true  | true  | true  | false
      true  | true  | true  | false | true
      true  | true  | false | true  | true
      true  | true  | false | false | false
      true  | false | false | true  | true
    end

    with_them do
      before do
        allow(project).to receive_messages(
          duo_features_enabled: duo_features_enabled,
          duo_foundational_flows_enabled: foundational_flows_enabled,
          duo_code_review_dap_available?: dap_available
        )
        allow(project.namespace).to receive(:has_active_add_on_purchase?)
          .with([:duo_enterprise]).and_return(duo_enterprise)
      end

      it { is_expected.to be(expected) }
    end
  end

  describe '#decisions_settings_available?' do
    subject(:decisions_available) { availability.decisions_settings_available? }

    let(:availability) do
      described_class.new(project).tap { |a| allow(a).to receive(:available?).and_return(available) }
    end

    let(:available) { true }

    context 'when the feature flag is enabled for one actor only' do
      let(:root_ancestor) { build_stubbed(:group) }

      before do
        allow(project).to receive_messages(
          root_ancestor: root_ancestor,
          duo_features_enabled: true,
          duo_foundational_flows_enabled: true
        )
        allow(root_ancestor).to receive(:duo_beta_flows_enabled?).and_return(true)
      end

      it 'is true when the flag is enabled for the project' do
        stub_feature_flags(duo_code_review_decisions: project)

        expect(decisions_available).to be(true)
      end

      it 'is false when the flag is enabled for the root ancestor only' do
        stub_feature_flags(duo_code_review_decisions: root_ancestor)

        expect(decisions_available).to be(false)
      end
    end

    it 'does not read the Duo settings when the feature flag is disabled' do
      stub_feature_flags(duo_code_review_decisions: false)

      expect(project).not_to receive(:duo_features_enabled)
      expect(decisions_available).to be(false)
    end

    where(:flag_enabled, :duo_features_enabled, :foundational_flows_enabled, :beta_enabled, :available, :expected) do
      true  | true  | true  | true  | true  | true
      false | true  | true  | true  | true  | false
      true  | false | true  | true  | true  | false
      true  | true  | false | true  | true  | false
      true  | true  | true  | false | true  | false
      true  | true  | true  | true  | false | false
    end

    with_them do
      before do
        stub_feature_flags(duo_code_review_decisions: flag_enabled ? project : false)
        allow(project).to receive_messages(
          duo_features_enabled: duo_features_enabled,
          duo_foundational_flows_enabled: foundational_flows_enabled
        )
        allow(project.root_ancestor).to receive(:duo_beta_flows_enabled?).and_return(beta_enabled)
      end

      it { is_expected.to be(expected) }
    end
  end

  describe '#automatic_review_available?' do
    let_it_be_with_refind(:namespace) { create(:group) }
    let_it_be(:project) { create(:project, group: namespace) }
    let_it_be(:duo_enterprise_add_on) { create(:gitlab_subscription_add_on, :duo_enterprise) }
    let_it_be(:duo_core_add_on) { create(:gitlab_subscription_add_on, :duo_core) }
    let_it_be(:self_hosted_dap_add_on) { create(:gitlab_subscription_add_on, :self_hosted_dap) }
    let_it_be(:code_review_foundational_flow) { create(:ai_catalog_item, :with_foundational_flow_reference) }

    subject(:available) { described_class.new(project).automatic_review_available? }

    context 'when duo_features_enabled is false' do
      before do
        allow(project).to receive(:duo_features_enabled).and_return(false)
      end

      it 'returns false' do
        expect(available).to be false
      end
    end

    context 'when duo_features_enabled is true' do
      before do
        allow(project).to receive(:duo_features_enabled).and_return(true)
      end

      context 'without any add-on' do
        it { is_expected.to be_falsey }
      end

      context 'on SaaS', :saas do
        before do
          stub_ee_application_setting(should_check_namespace_plan: true)
          allow(::Ai::Catalog::FoundationalFlow).to receive(:code_review_v1)
            .and_return(
              instance_double(::Ai::Catalog::FoundationalFlow, catalog_item: code_review_foundational_flow)
            )
        end

        context 'when duo_foundational_flows_enabled is false' do
          before do
            allow(project).to receive(:duo_foundational_flows_enabled).and_return(false)
            create(:gitlab_subscription_add_on_purchase, namespace: namespace, add_on: duo_core_add_on)
          end

          it 'returns false even with duo_core add-on' do
            expect(available).to be_falsey
          end
        end

        context 'when code_review workflow definition is nil' do
          before do
            allow(project).to receive(:duo_foundational_flows_enabled).and_return(true)
            allow(::Ai::Catalog::FoundationalFlow).to receive(:code_review_v1)
              .and_return(nil)
            create(:gitlab_subscription_add_on_purchase, namespace: namespace, add_on: duo_core_add_on)
          end

          it { is_expected.to be_falsey }
        end

        context 'when duo_foundational_flows_enabled is true' do
          before do
            allow(project).to receive(:duo_foundational_flows_enabled).and_return(true)
          end

          context 'when code_review flow is not enabled' do
            before do
              allow(::Gitlab::Llm::StageCheck).to receive(:available?)
                .with(project, :duo_workflow).and_return(true)
              create(:gitlab_subscription_add_on_purchase, namespace: namespace, add_on: duo_core_add_on)
            end

            it 'returns false with duo_core add-on' do
              expect(available).to be_falsey
            end
          end

          context 'when code_review flow is enabled' do
            before do
              create(:ai_catalog_enabled_foundational_flow, :for_namespace, namespace: namespace,
                catalog_item: code_review_foundational_flow)
            end

            context 'when StageCheck returns false' do
              before do
                allow(::Gitlab::Llm::StageCheck).to receive(:available?)
                  .with(project, :duo_workflow).and_return(false)
                create(:gitlab_subscription_add_on_purchase, namespace: namespace, add_on: duo_core_add_on)
              end

              it 'returns false with duo_core add-on' do
                expect(available).to be_falsey
              end
            end

            context 'when StageCheck returns true' do
              where(:add_on_type, :add_on) do
                [
                  ['duo_core',       ref(:duo_core_add_on)],
                  ['duo_pro',        lazy { create(:gitlab_subscription_add_on, :duo_pro) }],
                  ['duo_enterprise', ref(:duo_enterprise_add_on)]
                ]
              end

              with_them do
                before do
                  create(:gitlab_subscription_add_on_purchase, namespace: namespace, add_on: add_on)
                  allow(::Gitlab::Llm::StageCheck).to receive(:available?)
                    .with(project, :duo_workflow).and_return(true)
                end

                it "returns true for #{params[:add_on_type]}" do
                  expect(available).to be_truthy
                end
              end

              context 'when StageCheck returns true without any paid add-on' do
                before do
                  allow(::Gitlab::Llm::StageCheck).to receive(:available?)
                    .with(project, :duo_workflow).and_return(true)
                end

                it 'returns true for Free tier when DAP code review is available' do
                  expect(available).to be_truthy
                end
              end
            end

            context 'when duo_foundational_flows_enabled differs between namespace and project' do
              before do
                namespace.namespace_settings.update!(duo_foundational_flows_enabled: true)
                allow(project).to receive(:duo_foundational_flows_enabled).and_return(false)
                create(:gitlab_subscription_add_on_purchase, namespace: namespace, add_on: duo_core_add_on)
              end

              it 'returns false because project setting is used' do
                expect(available).to be_falsey
              end
            end
          end
        end
      end

      context 'on self-managed' do
        context 'when duo_foundational_flows_enabled is false' do
          where(:add_on_type) do
            [ref(:duo_core_add_on), ref(:self_hosted_dap_add_on)]
          end

          with_them do
            before do
              allow(project).to receive(:duo_foundational_flows_enabled).and_return(false)
              create(:gitlab_subscription_add_on_purchase, :self_managed, add_on: add_on_type)
            end

            it "returns false for #{params[:add_on_type]}" do
              expect(available).to be_falsey
            end
          end
        end

        context 'when code_review workflow definition is nil' do
          where(:add_on_type) do
            [ref(:duo_core_add_on), ref(:self_hosted_dap_add_on)]
          end

          with_them do
            before do
              allow(project).to receive(:duo_foundational_flows_enabled).and_return(true)
              allow(::Ai::Catalog::FoundationalFlow).to receive(:code_review_v1).and_return(nil)
              create(:gitlab_subscription_add_on_purchase, :self_managed, add_on: add_on_type)
            end

            it "returns false for #{params[:add_on_type]}" do
              expect(available).to be_falsey
            end
          end
        end

        context 'when duo_foundational_flows_enabled is true' do
          before do
            allow(project).to receive(:duo_foundational_flows_enabled).and_return(true)
          end

          context 'when code_review flow is not enabled' do
            where(:add_on_type) do
              [ref(:duo_core_add_on), ref(:self_hosted_dap_add_on)]
            end

            with_them do
              before do
                allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
              end

              it "returns false for #{params[:add_on_type]}" do
                expect(available).to be_falsey
              end
            end
          end

          context 'when code_review flow is enabled' do
            before do
              allow(::Ai::Catalog::FoundationalFlow).to receive(:code_review_v1)
                .and_return(
                  instance_double(::Ai::Catalog::FoundationalFlow, catalog_item: code_review_foundational_flow)
                )
              allow(project).to receive(:enabled_flow_catalog_item_ids).and_return([code_review_foundational_flow.id])
              allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
              create(:ai_catalog_enabled_foundational_flow, :for_project, project: project,
                catalog_item: code_review_foundational_flow)
            end

            where(:add_on_type) do
              [ref(:duo_core_add_on), ref(:self_hosted_dap_add_on)]
            end

            with_them do
              it "returns true for #{params[:add_on_type]}" do
                create(:gitlab_subscription_add_on_purchase, :self_managed, add_on: add_on_type)

                expect(available).to be_truthy
              end
            end

            context 'when instance has duo_enterprise add-on' do
              before do
                create(:gitlab_subscription_add_on_purchase, :self_managed, add_on: duo_enterprise_add_on)
              end

              it { is_expected.to be_truthy }
            end

            context 'when instance has expired duo_enterprise add-on' do
              before do
                # An expired add-on without gitlab_credits means StageCheck returns false;
                # override the parent stub that returns true for this context
                allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project,
                  :duo_workflow).and_return(false)
                create(:gitlab_subscription_add_on_purchase, :expired, :self_managed, add_on: duo_enterprise_add_on)
              end

              it { is_expected.to be_falsey }
            end

            context 'when StageCheck returns false' do
              where(:add_on_type) do
                [ref(:duo_core_add_on), ref(:self_hosted_dap_add_on)]
              end

              with_them do
                before do
                  allow(::Gitlab::Llm::StageCheck).to receive(:available?)
                    .with(project, :duo_workflow).and_return(false)
                  create(:gitlab_subscription_add_on_purchase, :self_managed, add_on: add_on_type)
                end

                it "returns false for #{params[:add_on_type]}" do
                  expect(available).to be_falsey
                end
              end
            end

            context 'when StageCheck returns true' do
              where(:add_on_type) do
                [ref(:duo_core_add_on), ref(:self_hosted_dap_add_on)]
              end

              with_them do
                before do
                  allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
                  create(:gitlab_subscription_add_on_purchase, :self_managed, add_on: add_on_type)
                end

                it "returns true for #{params[:add_on_type]}" do
                  expect(available).to be_truthy
                end
              end
            end
          end
        end
      end
    end
  end

  describe '#depth_settings_available?' do
    subject(:available) { described_class.new(project).depth_settings_available? }

    where(:flag_enabled, :duo_features_enabled, :foundational_flows_enabled, :beta_enabled, :expected) do
      true  | true  | true  | true  | true
      false | true  | true  | true  | false
      true  | false | true  | true  | false
      true  | true  | false | true  | false
      true  | true  | true  | false | false
    end

    with_them do
      before do
        stub_feature_flags(duo_code_review_deep_flow: flag_enabled ? project.root_ancestor : false)
        allow(project).to receive_messages(
          duo_features_enabled: duo_features_enabled,
          duo_foundational_flows_enabled: foundational_flows_enabled
        )
        allow(project.root_ancestor).to receive(:duo_beta_flows_enabled?).and_return(beta_enabled)
      end

      it { is_expected.to be(expected) }
    end
  end

  describe '#default_depth' do
    let(:availability) { described_class.new(project) }

    subject(:default_depth) { availability.default_depth }

    where(:available, :allowed, :selected_depth, :expected_depth) do
      true  | true  | 'deep'     | 'deep'
      true  | true  | 'standard' | 'standard'
      true  | false | 'deep'     | 'standard'
      false | true  | 'deep'     | 'standard'
    end

    with_them do
      before do
        allow(availability).to receive(:depth_settings_available?).and_return(available)
        allow(project).to receive_messages(
          duo_code_review_depth_allowed: allowed,
          duo_code_review_default_depth: selected_depth
        )
      end

      it { is_expected.to eq(expected_depth) }
    end
  end
end
