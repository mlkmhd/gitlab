# frozen_string_literal: true

require 'gitlab-glfm-markdown'

module Banzai
  module Filter
    module MarkdownEngines
      # Stands in for the monolith's engine of the same name, which reads feature
      # flags and the project from the context. It renders with the parser options
      # that the filters specced here depend on.
      class GlfmMarkdown < Base
        OPTIONS = {
          footnotes: true,
          inapplicable_tasks: true,
          relaxed_tasklist_character: true,
          sourcepos: true,
          table: true,
          tasklist: true,
          tasklist_classes: true,
          tasklist_in_table: true,
          unsafe: true
        }.freeze

        def render(text)
          ::GLFMMarkdown.to_html(text, options: OPTIONS)
        end
      end
    end
  end
end
