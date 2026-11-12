# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::PipelineSchedulesController, feature_category: :continuous_integration do
  include AccessMatchersForController
  using RSpec::Parameterized::TableSyntax

  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:project) { create(:project, :public, :small_repo, developers: user) }
  let_it_be_with_reload(:pipeline_schedule) { create(:ci_pipeline_schedule, project: project) }

  before do
    project.update!(ci_pipeline_variables_minimum_override_role: :developer)
  end

  shared_examples 'access update schedule' do
    describe 'security' do
      it 'is allowed for admin when admin mode enabled', :enable_admin_mode do
        expect { go }.to be_allowed_for(:admin)
      end

      it 'is denied for admin when admin mode disabled' do
        expect { go }.to be_denied_for(:admin)
      end

      it { expect { go }.to be_denied_for(:owner).of(project) }
      it { expect { go }.to be_denied_for(:maintainer).of(project) }
      it { expect { go }.to be_denied_for(:developer).of(project) }
      it { expect { go }.to be_denied_for(:reporter).of(project) }
      it { expect { go }.to be_denied_for(:guest).of(project) }
      it { expect { go }.to be_denied_for(:user) }
      it { expect { go }.to be_denied_for(:external) }
      it { expect { go }.to be_denied_for(:visitor) }

      context 'when user is schedule owner' do
        it { expect { go }.to be_allowed_for(:owner).of(project).own(pipeline_schedule) }
        it { expect { go }.to be_allowed_for(:maintainer).of(project).own(pipeline_schedule) }
        it { expect { go }.to be_allowed_for(:developer).of(project).own(pipeline_schedule) }
        it { expect { go }.to be_denied_for(:reporter).of(project).own(pipeline_schedule) }
        it { expect { go }.to be_denied_for(:guest).of(project).own(pipeline_schedule) }
        it { expect { go }.to be_denied_for(:user).own(pipeline_schedule) }
        it { expect { go }.to be_denied_for(:external).own(pipeline_schedule) }
        it { expect { go }.to be_denied_for(:visitor).own(pipeline_schedule) }
      end
    end
  end

  shared_examples 'protecting ref' do
    where(:branch_access_levels, :tag_access_level, :maintainer_accessible, :developer_accessible) do
      [:no_one_can_push, :no_one_can_merge] | :no_one_can_create | \
        :be_denied_for | :be_denied_for
      [:maintainers_can_push, :maintainers_can_merge] | :maintainers_can_create | \
        :be_allowed_for | :be_denied_for
      [:developers_can_push, :developers_can_merge] | :developers_can_create | \
        :be_allowed_for | :be_allowed_for
    end

    with_them do
      context 'when branch is protected' do
        let(:ref_prefix) { 'heads' }
        let(:ref_name) { 'master' }

        before do
          create(:protected_branch, *branch_access_levels, name: ref_name, project: project)
        end

        after do
          ProtectedBranches::CacheService.new(project).refresh
        end

        it { expect { go }.to try(maintainer_accessible, :maintainer).of(project) }
        it { expect { go }.to try(developer_accessible, :developer).of(project) }
      end

      context 'when tag is protected' do
        let(:ref_prefix) { 'tags' }
        let(:ref_name) { 'v1.0.0' }

        before do
          create(:protected_tag, tag_access_level, name: ref_name, project: project)
        end

        it { expect { go }.to try(maintainer_accessible, :maintainer).of(project) }
        it { expect { go }.to try(developer_accessible, :developer).of(project) }
      end
    end
  end

  describe 'GET #index' do
    render_views

    let(:scope) { nil }

    let!(:inactive_pipeline_schedule) do
      create(:ci_pipeline_schedule, :inactive, project: project)
    end

    before do
      sign_in(user)
    end

    it 'renders the index view' do
      visit_pipelines_schedules

      expect(response).to have_gitlab_http_status(:ok)
      expect(response).to render_template(:index)
    end

    it 'avoids N + 1 queries', :request_store do
      control = ActiveRecord::QueryRecorder.new { visit_pipelines_schedules }

      create_list(:ci_pipeline_schedule, 2, project: project)

      expect { visit_pipelines_schedules }.not_to exceed_query_limit(control)
    end

    context 'when the scope is set to active' do
      let(:scope) { 'active' }

      before do
        visit_pipelines_schedules
      end

      it 'only shows active pipeline schedules' do
        expect(response).to have_gitlab_http_status(:ok)
        expect(assigns(:schedules)).to include(pipeline_schedule)
        expect(assigns(:schedules)).not_to include(inactive_pipeline_schedule)
      end
    end

    def visit_pipelines_schedules
      get :index, params: { namespace_id: project.namespace.to_param, project_id: project, scope: scope }
    end
  end

  describe 'GET #new' do
    before_all { project.add_developer(user) }

    before do
      sign_in(user)
    end

    it 'initializes a pipeline schedule model' do
      get :new, params: { namespace_id: project.namespace.to_param, project_id: project }

      expect(response).to have_gitlab_http_status(:ok)
      expect(assigns(:schedule)).to be_a_new(Ci::PipelineSchedule)
    end
  end

  describe 'POST #create' do
    describe 'functionality' do
      before_all { project.add_developer(user) }

      before do
        sign_in(user)
      end

      let(:basic_param) do
        attributes_for(:ci_pipeline_schedule)
      end

      context 'when the pipeline schedule management rate limit is exceeded', :clean_gitlab_redis_rate_limiting,
        :freeze_time do
        let(:schedule) { basic_param }

        before do
          stub_application_setting(pipeline_schedule_management_limit_per_user: 1)
          go
        end

        it 'does not create a schedule and shows the limit message', :aggregate_failures do
          expect { go }.not_to change { Ci::PipelineSchedule.count }

          expect(response).to have_gitlab_http_status(:ok)
          expect(flash[:alert]).to eq(_('This endpoint has been requested too many times. Try again later.'))
        end
      end

      context 'when variables_attributes has one variable' do
        let(:schedule) do
          basic_param.merge({
            variables_attributes: [{ key: 'AAA', value: 'AAA123', variable_type: 'file' }]
          })
        end

        it 'creates a new schedule' do
          expect { go }
            .to change { Ci::PipelineSchedule.count }.by(1)
            .and change { Ci::PipelineScheduleVariable.count }.by(1)

          expect(response).to have_gitlab_http_status(:found)

          Ci::PipelineScheduleVariable.last.tap do |v|
            expect(v.key).to eq("AAA")
            expect(v.value).to eq("AAA123")
            expect(v.variable_type).to eq("file")
          end
        end

        context 'when the user is not allowed to create a pipeline schedule with variables' do
          before do
            project.update!(ci_pipeline_variables_minimum_override_role: :maintainer)
          end

          it 'does not create a new schedule' do
            expect { go }
              .to not_change { Ci::PipelineSchedule.count }
              .and not_change { Ci::PipelineScheduleVariable.count }

            expect(response).to have_gitlab_http_status(:ok)
          end
        end
      end

      context 'when variables_attributes has two variables and duplicated' do
        let(:schedule) do
          basic_param.merge({
            variables_attributes: [{ key: 'AAA', value: 'AAA123' },
              { key: 'AAA', value: 'BBB123' }]
          })
        end

        it 'returns an error that the keys of variable are duplicated' do
          expect { go }
            .to not_change { Ci::PipelineSchedule.count }
            .and not_change { Ci::PipelineScheduleVariable.count }

          expect(assigns(:schedule).errors['variables']).not_to be_empty
        end
      end
    end

    describe 'security' do
      let(:schedule) { attributes_for(:ci_pipeline_schedule, ref: "refs/#{ref_prefix}/#{ref_name}") }
      let(:ref_prefix) { 'heads' }
      let(:ref_name) { "master" }

      it 'is allowed for admin when admin mode enabled', :enable_admin_mode do
        expect { go }.to be_allowed_for(:admin)
      end

      it 'is denied for admin when admin mode disabled' do
        expect { go }.to be_denied_for(:admin)
      end

      it { expect { go }.to be_allowed_for(:owner).of(project) }
      it { expect { go }.to be_allowed_for(:maintainer).of(project) }
      it { expect { go }.to be_allowed_for(:developer).of(project) }

      it { expect { go }.to be_denied_for(:reporter).of(project) }
      it { expect { go }.to be_denied_for(:guest).of(project) }
      it { expect { go }.to be_denied_for(:user) }
      it { expect { go }.to be_denied_for(:external) }
      it { expect { go }.to be_denied_for(:visitor) }

      it_behaves_like 'protecting ref'
    end

    def go
      post :create, params: { namespace_id: project.namespace.to_param, project_id: project, schedule: schedule }
    end
  end

  describe 'PUT #update' do
    describe 'functionality' do
      let!(:pipeline_schedule) { create(:ci_pipeline_schedule, project: project, owner: user) }

      before_all { project.add_developer(user) }

      before do
        sign_in(user)
      end

      context 'when the pipeline schedule management rate limit is exceeded', :clean_gitlab_redis_rate_limiting,
        :freeze_time do
        let(:schedule) { { description: 'updated_desc' } }

        before do
          stub_application_setting(pipeline_schedule_management_limit_per_user: 1)
          put :update,
            params: {
              namespace_id: project.namespace.to_param,
              project_id: project,
              id: pipeline_schedule,
              schedule: { description: 'first_desc' }
            },
            as: :html
        end

        it 'keeps the schedule unchanged and shows the limit message', :aggregate_failures do
          expect { go }.not_to change { pipeline_schedule.reload.description }.from('first_desc')

          expect(response).to have_gitlab_http_status(:ok)
          expect(flash[:alert]).to eq(_('This endpoint has been requested too many times. Try again later.'))
        end
      end

      context 'when a pipeline schedule has no variables' do
        let(:basic_param) do
          { description: 'updated_desc', cron: '0 1 * * *', cron_timezone: 'UTC', ref: 'master', active: true }
        end

        context 'when params include one variable' do
          let(:schedule) do
            basic_param.merge({
              variables_attributes: [{ key: 'AAA', value: 'AAA123' }]
            })
          end

          it 'inserts new variable to the pipeline schedule' do
            expect { go }.to change { Ci::PipelineScheduleVariable.count }.by(1)

            pipeline_schedule.reload
            expect(response).to have_gitlab_http_status(:found)
            expect(pipeline_schedule.variables.last.key).to eq('AAA')
            expect(pipeline_schedule.variables.last.value).to eq('AAA123')
          end

          context 'when the user is not allowed to update pipeline schedule variables' do
            before do
              project.update!(ci_pipeline_variables_minimum_override_role: :maintainer)
            end

            it 'does not update the schedule' do
              expect { go }
                .to not_change { Ci::PipelineScheduleVariable.count }

              expect(response).to have_gitlab_http_status(:ok)

              pipeline_schedule.reload
              expect(pipeline_schedule.variables).to be_empty
            end
          end
        end

        context 'when params include two duplicated variables' do
          let(:schedule) do
            basic_param.merge({
              variables_attributes: [{ key: 'AAA', value: 'AAA123' },
                { key: 'AAA', value: 'BBB123' }]
            })
          end

          it 'returns an error that variables are duplciated' do
            go

            expect(assigns(:schedule).errors['variables']).not_to be_empty
          end
        end
      end

      context 'when a pipeline schedule has one variable' do
        let(:basic_param) do
          { description: 'updated_desc', cron: '0 1 * * *', cron_timezone: 'UTC', ref: 'master', active: true }
        end

        let!(:pipeline_schedule_variable) do
          create(:ci_pipeline_schedule_variable,
            key: 'CCC', pipeline_schedule: pipeline_schedule)
        end

        context 'when adds a new variable' do
          let(:schedule) do
            basic_param.merge({
              variables_attributes: [{ key: 'AAA', value: 'AAA123' }]
            })
          end

          it 'adds the new variable' do
            expect { go }.to change { Ci::PipelineScheduleVariable.count }.by(1)

            pipeline_schedule.reload
            expect(pipeline_schedule.variables.last.key).to eq('AAA')
          end
        end

        context 'when adds a new duplicated variable' do
          let(:schedule) do
            basic_param.merge({
              variables_attributes: [{ key: 'dup_key', value: 'value_one' }, { key: 'dup_key', value: 'value_two' }]
            })
          end

          it 'returns an error' do
            expect { go }.not_to change { Ci::PipelineScheduleVariable.count }

            pipeline_schedule.reload
            expect(assigns(:schedule).errors['variables']).not_to be_empty
          end
        end

        context 'when updates a variable' do
          let(:schedule) do
            basic_param.merge({
              variables_attributes: [{ id: pipeline_schedule_variable.id, value: 'new_value' }]
            })
          end

          it 'updates the variable' do
            expect { go }.not_to change { Ci::PipelineScheduleVariable.count }

            pipeline_schedule_variable.reload
            expect(pipeline_schedule_variable.value).to eq('new_value')
          end
        end

        context 'when deletes a variable' do
          let(:schedule) do
            basic_param.merge({
              variables_attributes: [{ id: pipeline_schedule_variable.id, _destroy: true }]
            })
          end

          it 'delete the existsed variable' do
            expect { go }.to change { Ci::PipelineScheduleVariable.count }.by(-1)
          end
        end

        context 'when deletes and creates a same key simultaneously' do
          let(:schedule) do
            basic_param.merge({
              variables_attributes: [{ id: pipeline_schedule_variable.id, _destroy: true },
                { key: 'AAA', value: 'AAA123' }]
            })
          end

          it 'updates the variable' do
            expect { go }.not_to change { Ci::PipelineScheduleVariable.count }

            pipeline_schedule.reload
            expect(pipeline_schedule.variables.last.key).to eq('AAA')
            expect(pipeline_schedule.variables.last.value).to eq('AAA123')
          end
        end
      end
    end

    describe 'security' do
      let(:schedule) { { description: 'updated_desc' } }

      it_behaves_like 'access update schedule'

      context 'when a developer created a pipeline schedule' do
        let_it_be(:developer_1) { create(:user) }
        let!(:pipeline_schedule) { create(:ci_pipeline_schedule, project: project, owner: developer_1) }

        before_all { project.add_developer(developer_1) }

        it { expect { go }.to be_allowed_for(developer_1) }

        it { expect { go }.to be_denied_for(:owner).of(project) }
        it { expect { go }.to be_denied_for(:maintainer).of(project) }
        it { expect { go }.to be_denied_for(:developer).of(project) }
      end

      context 'when a maintainer created a pipeline schedule' do
        let_it_be(:maintainer_1) { create(:user) }
        let!(:pipeline_schedule) { create(:ci_pipeline_schedule, project: project, owner: maintainer_1) }

        before_all { project.add_maintainer(maintainer_1) }

        it { expect { go }.to be_allowed_for(maintainer_1) }

        it { expect { go }.to be_denied_for(:owner).of(project) }
        it { expect { go }.to be_denied_for(:maintainer).of(project) }
        it { expect { go }.to be_denied_for(:developer).of(project) }
      end
    end

    def go
      put :update,
        params: {
          namespace_id: project.namespace.to_param,
          project_id: project,
          id: pipeline_schedule,
          schedule: schedule
        },
        as: :html
    end
  end

  describe 'GET #edit' do
    describe 'functionality' do
      let_it_be(:user) { create(:user) }

      before_all do
        project.add_maintainer(user)
        pipeline_schedule.update!(owner: user)
      end

      before do
        sign_in(user)
      end

      it 'loads the pipeline schedule' do
        get :edit, params: { namespace_id: project.namespace.to_param, project_id: project, id: pipeline_schedule.id }

        expect(response).to have_gitlab_http_status(:ok)
        expect(assigns(:schedule)).to eq(pipeline_schedule)
      end
    end

    it_behaves_like 'access update schedule'

    def go
      get :edit, params: { namespace_id: project.namespace.to_param, project_id: project, id: pipeline_schedule.id }
    end
  end

  describe 'GET #take_ownership' do
    describe 'security' do
      it 'is allowed for admin when admin mode enabled', :enable_admin_mode do
        expect { go }.to be_allowed_for(:admin)
      end

      it 'is denied for admin when admin mode disabled' do
        expect { go }.to be_denied_for(:admin)
      end

      it { expect { go }.to be_allowed_for(:owner).of(project) }
      it { expect { go }.to be_allowed_for(:maintainer).of(project) }
      it { expect { go }.to be_denied_for(:developer).of(project) }
      it { expect { go }.to be_denied_for(:reporter).of(project) }
      it { expect { go }.to be_denied_for(:guest).of(project) }
      it { expect { go }.to be_denied_for(:user) }
      it { expect { go }.to be_denied_for(:external) }
      it { expect { go }.to be_denied_for(:visitor) }

      context 'when user is schedule owner' do
        it { expect { go }.to be_allowed_for(:owner).of(project).own(pipeline_schedule) }
        it { expect { go }.to be_allowed_for(:maintainer).of(project).own(pipeline_schedule) }
        it { expect { go }.to be_allowed_for(:developer).of(project).own(pipeline_schedule) }
        it { expect { go }.to be_denied_for(:reporter).of(project).own(pipeline_schedule) }
        it { expect { go }.to be_denied_for(:guest).of(project).own(pipeline_schedule) }
        it { expect { go }.to be_denied_for(:user).own(pipeline_schedule) }
        it { expect { go }.to be_denied_for(:external).own(pipeline_schedule) }
        it { expect { go }.to be_denied_for(:visitor).own(pipeline_schedule) }
      end
    end

    context 'when the pipeline schedule management rate limit is exceeded', :clean_gitlab_redis_rate_limiting,
      :freeze_time do
      let(:other_pipeline_schedule) { create(:ci_pipeline_schedule, project: project) }

      before_all do
        project.add_maintainer(user)
      end

      before do
        sign_in(user)
        stub_application_setting(pipeline_schedule_management_limit_per_user: 1)
        post :take_ownership,
          params: { namespace_id: project.namespace.to_param, project_id: project, id: other_pipeline_schedule.id }
      end

      it 'keeps the owner and shows the limit message', :aggregate_failures do
        expect { go }.not_to change { pipeline_schedule.reload.owner }

        expect(response).to have_gitlab_http_status(:found)
        expect(flash[:alert]).to eq(_('This endpoint has been requested too many times. Try again later.'))
      end
    end

    context 'when the owner cannot be changed' do
      before_all do
        project.add_maintainer(user)
      end

      before do
        sign_in(user)
        allow_next_instance_of(Ci::PipelineSchedules::TakeOwnershipService) do |service|
          allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'failed'))
        end
        go
      end

      it 'shows the generic failure message', :aggregate_failures do
        expect(response).to have_gitlab_http_status(:found)
        expect(flash[:alert]).to eq(_('Failed to change the owner'))
      end
    end

    def go
      post :take_ownership, params: { namespace_id: project.namespace.to_param, project_id: project, id: pipeline_schedule.id }
    end
  end

  describe 'POST #play', :clean_gitlab_redis_rate_limiting, :clean_gitlab_redis_queues do
    let(:ref_name) { 'master' }

    before_all { project.add_developer(user) }

    before do
      sign_in(user)
    end

    context 'when an anonymous user makes the request' do
      before do
        sign_out(user)
      end

      it 'does not allow pipeline to be executed' do
        expect(Ci::PipelineSchedules::PlayService).not_to receive(:new)

        go

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when a developer makes the request' do
      it 'executes a new pipeline' do
        expect(Ci::PipelineSchedules::PlayService).to receive_message_chain(:new, :execute).with(pipeline_schedule)
          .and_return(ServiceResponse.success(payload: { job_id: 'job-123' }))

        go

        expect(flash[:notice]).to start_with 'Successfully scheduled a pipeline to run'
        expect(response).to have_gitlab_http_status(:found)
      end

      context 'when the schedule cannot be played' do
        it 'shows an alert' do
          expect(Ci::PipelineSchedules::PlayService).to receive_message_chain(:new, :execute).with(pipeline_schedule)
            .and_return(ServiceResponse.error(message: 'Failed to schedule pipeline.'))

          go

          expect(flash[:alert]).to eq _('Unable to schedule a pipeline to run immediately')
          expect(response).to have_gitlab_http_status(:found)
        end
      end

      context 'when rate limited', :freeze_time do
        it 'prevents users from scheduling the same pipeline repeatedly', :aggregate_failures do
          go
          expect(flash[:notice]).to start_with 'Successfully scheduled a pipeline to run'

          go

          expect(flash[:alert]).to eq _('You cannot play this scheduled pipeline at the moment. Please wait a minute.')
          expect(response).to have_gitlab_http_status(:found)
        end
      end
    end

    describe 'security' do
      let!(:pipeline_schedule) { create(:ci_pipeline_schedule, project: project, ref: "refs/#{ref_prefix}/#{ref_name}") }

      it_behaves_like 'protecting ref'
    end

    def go
      post :play, params: { namespace_id: project.namespace.to_param, project_id: project, id: pipeline_schedule.id }
    end
  end

  describe 'DELETE #destroy' do
    context 'when a developer makes the request' do
      before_all { project.add_developer(user) }

      before do
        sign_in(user)

        delete :destroy, params: { namespace_id: project.namespace.to_param, project_id: project, id: pipeline_schedule.id }
      end

      it 'does not delete the pipeline schedule' do
        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when a maintainer makes the request' do
      before_all { project.add_maintainer(user) }

      before do
        sign_in(user)
      end

      it 'destroys the pipeline schedule' do
        expect do
          delete :destroy, params: { namespace_id: project.namespace.to_param, project_id: project, id: pipeline_schedule.id }
        end.to change { project.pipeline_schedules.count }.by(-1)

        expect(response).to have_gitlab_http_status(:found)
      end

      it 'redirects with an alert when the schedule cannot be destroyed' do
        allow_next_found_instance_of(Ci::PipelineSchedule) do |schedule|
          allow(schedule).to receive(:destroy).and_return(false)
        end

        delete :destroy, params: { namespace_id: project.namespace.to_param, project_id: project, id: pipeline_schedule.id }

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(flash[:alert]).to eq(_('Failed to remove the pipeline schedule'))
      end

      context 'when the pipeline schedule management rate limit is exceeded', :clean_gitlab_redis_rate_limiting,
        :freeze_time do
        let(:other_pipeline_schedule) { create(:ci_pipeline_schedule, project: project) }

        before do
          stub_application_setting(pipeline_schedule_management_limit_per_user: 1)
          delete :destroy,
            params: { namespace_id: project.namespace.to_param, project_id: project, id: other_pipeline_schedule.id }
        end

        it 'keeps the schedule and shows the limit message', :aggregate_failures do
          expect do
            delete :destroy,
              params: { namespace_id: project.namespace.to_param, project_id: project, id: pipeline_schedule.id }
          end.not_to change { Ci::PipelineSchedule.count }

          expect(response).to have_gitlab_http_status(:forbidden)
          expect(flash[:alert]).to eq(_('This endpoint has been requested too many times. Try again later.'))
        end
      end
    end
  end
end
