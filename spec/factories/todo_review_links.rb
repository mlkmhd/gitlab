# frozen_string_literal: true

FactoryBot.define do
  factory :todo_review_link, class: 'Todos::ReviewLink' do
    todo { association(:todo, :review_submitted) }
    project { todo.project }
    review { association(:review, project: todo.project, author: todo.author) }
  end
end
