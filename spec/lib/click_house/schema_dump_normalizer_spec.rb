# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ClickHouse::SchemaDumpNormalizer, feature_category: :database do
  describe '.normalize' do
    using RSpec::Parameterized::TableSyntax

    where(:input, :expected) do
      "ENGINE = `Null`;"                                        | "ENGINE = Null;"
      "`Null`"                                                  | "Null"
      "ENGINE = Null"                                           | "ENGINE = Null"
      "PRIMARY KEY (id)\nORDER BY (id)\nSETTINGS a = 1"         | "PRIMARY KEY id\nORDER BY id\nSETTINGS a = 1"
      "PRIMARY KEY (`id`)\nORDER BY (`id`);"                    | "PRIMARY KEY `id`\nORDER BY `id`;"
      "MergeTree PRIMARY KEY (id) ORDER BY (id) SETTINGS a = 1" | "MergeTree PRIMARY KEY id ORDER BY id SETTINGS a = 1"
      "ORDER BY (id)"                                           | "ORDER BY id"
      "OVER (PARTITION BY a ORDER BY (b))"                      | "OVER (PARTITION BY a ORDER BY b)"
      "PRIMARY KEY id\nORDER BY id"                             | "PRIMARY KEY id\nORDER BY id"
      "PRIMARY KEY (a, b)\nORDER BY (a, b)"                     | "PRIMARY KEY (a, b)\nORDER BY (a, b)"
      "PRIMARY KEY (toDate(a))\nORDER BY (toDate(a))"           | "PRIMARY KEY (toDate(a))\nORDER BY (toDate(a))"
      "ORDER BY tuple(id)"                                      | "ORDER BY tuple(id)"
      "ORDER BY tuple()"                                        | "ORDER BY tuple()"
      ")\nAS WITH base AS\n    (\n        SELECT 1"               | ")\nAS WITH\n    base AS\n    (\n        SELECT 1"
      ")\nAS WITH\n    base AS\n    (\n        SELECT 1"          | ")\nAS WITH\n    base AS\n    (\n        SELECT 1"
      "    WITH base AS\n    (\n        SELECT 1"                 | "    WITH base AS\n    (\n        SELECT 1"
      ""                                                        | ""
      nil                                                       | nil
    end

    with_them do
      it { expect(described_class.normalize(input)).to eq(expected) }
    end
  end

  describe '.normalize_key' do
    using RSpec::Parameterized::TableSyntax

    where(:input, :expected) do
      '(id)'                 | 'id'
      'id'                   | 'id'
      '(a, b)'               | '(a, b)'
      'a, b'                 | 'a, b'
      '(toDate(created_at))' | '(toDate(created_at))'
      'tuple()'              | 'tuple()'
      ''                     | ''
      nil                    | nil
    end

    with_them do
      it { expect(described_class.normalize_key(input)).to eq(expected) }
    end
  end
end
