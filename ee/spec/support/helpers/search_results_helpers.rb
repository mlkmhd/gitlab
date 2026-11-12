# frozen_string_literal: true

module SearchResultHelpers
  # @param users [User, nil, Array<User, nil>] users to search as; pass nil inside an array for an anonymous user
  # @param target [String, Symbol] search target, e.g. "merge_requests", "blobs"
  # @param expected_count [Integer, nil] expected value of the target's count method
  # @param expected_objects [Array, nil] objects the target must return, in any order
  # @param context [String, nil] prefix for the expected count failure message
  # @yieldparam user [User, nil] user to search as
  # @yieldreturn [Object] search results that respond to #objects(target)
  def expect_search_results(users, target, expected_count: nil, expected_objects: nil, context: nil)
    users = Array(users)
    target = target.to_s

    users.each do |user|
      user_name = user&.name || 'anonymous user'
      results = yield(user)
      objects = results.objects(target)

      if expected_count
        actual_count = results.public_send("#{target}_count")

        prefix = context ? "[#{context}] " : ""
        expect(actual_count).to eq(expected_count), "#{prefix}#{target} expected count to be #{expected_count} for #{user_name}, got #{actual_count}: #{objects}"
      end

      if expected_objects
        expect(objects).to match_array(expected_objects)
      end
    end
  end
end
