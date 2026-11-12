# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Ci::DestroyPipelineService, feature_category: :continuous_integration do
  let(:project) { create(:project) }
  let!(:pipeline) { create(:ci_pipeline, project: project) }
  let(:user) { project.first_owner }

  subject(:service) { described_class.new(project, user) }

  describe '#execute' do
    subject(:operation) { service.execute(pipeline) }

    context 'with job artifacts' do
      let(:build) { create(:ci_build, pipeline: pipeline) }

      before do
        create(:ci_job_artifact, :zip, job: build)
      end

      it 'does not publish Ci::JobArtifactsDeletedEvent' do
        expect { operation }.not_to publish_event(Ci::JobArtifactsDeletedEvent)
      end

      context 'when the skip_job_artifacts_deleted_event_on_destroy feature flag is disabled' do
        before do
          stub_feature_flags(skip_job_artifacts_deleted_event_on_destroy: false)
        end

        it 'publishes Ci::JobArtifactsDeletedEvent' do
          expect { operation }.to publish_event(Ci::JobArtifactsDeletedEvent).with(job_ids: [build.id])
        end
      end
    end

    context 'for audit events', :enable_admin_mode do
      let(:audit_event_name) { "destroy_pipeline" }
      let(:event_type) { "destroy_pipeline" }

      include_examples 'audit event logging' do
        let(:operation) { service.execute(pipeline) }

        let(:fail_condition!) do
          allow(service).to receive(:destroy_all_records).and_return(nil)
        end

        let(:attributes) do
          {
            author_id: user.id,
            entity_id: project.id,
            entity_type: 'Project',
            details: {
              author_class: 'User',
              author_name: user.name,
              custom_message: "Deleted pipeline in #{pipeline.ref} with status " \
                "#{pipeline.status} and SHA #{pipeline.sha}",
              event_name: "destroy_pipeline",
              target_details: pipeline.id.to_s,
              target_id: pipeline.id,
              target_type: 'Ci::Pipeline'
            }
          }
        end
      end
    end
  end
end
