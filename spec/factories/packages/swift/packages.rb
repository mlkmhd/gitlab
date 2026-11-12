# frozen_string_literal: true

FactoryBot.define do
  factory :swift_package, class: 'Packages::Swift::Package', parent: :package do
    sequence(:name) { |n| "mona.LinkedList#{n}" }
    sequence(:version) { |n| "1.0.#{n}" }
    package_type { :swift }
  end
end
