# frozen_string_literal: true

module API
  module Entities
    class UserPreferences < Grape::Entity
      expose :id, :user_id, :view_diffs_file_by_file,
        :show_whitespace_in_diffs, :pass_user_identities_to_ci_jwt, :policy_advanced_editor, :emoji_skin_tone

      # The mobile push working hours. Always present on a server with this
      # code; an older server returns none of them, which is how the mobile
      # app learns the instance cannot do this.
      expose :mobile_push_working_hours_enabled, documentation: { type: 'Boolean', example: true }
      expose :mobile_push_working_hours_start, documentation: { type: 'Integer', example: 540 }
      expose :mobile_push_working_hours_end, documentation: { type: 'Integer', example: 1020 }
      expose :mobile_push_working_days,
        documentation: { type: 'String', is_array: true, example: %w[monday tuesday wednesday thursday friday] }
      expose :mobile_push_working_hours_time_zone, documentation: { type: 'String', example: 'Europe/Berlin' }
    end
  end
end
