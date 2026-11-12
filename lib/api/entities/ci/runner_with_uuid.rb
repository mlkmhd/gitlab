# frozen_string_literal: true

module API
  module Entities
    module Ci
      class RunnerWithUuid < Runner
        expose :uuid, documentation: { type: 'String', example: '01966aa0-f383-7a6b-b694-cd4f2f96cca1' }
      end
    end
  end
end
