# frozen_string_literal: true

module API
  module Entities
    class UserActivity < Grape::Entity
      expose :username, documentation: { type: 'String', example: 'johndoe' }
      expose :last_activity_on, documentation: { type: 'Date', example: '2015-12-24' }
      # Back-compat
      expose :last_activity_on, as: :last_activity_at,
        documentation: { type: 'Date', example: '2015-12-24' }
    end
  end
end
