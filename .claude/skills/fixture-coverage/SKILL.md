---
name: fixture-coverage
description: "Write a development fixture for a table that has no seed data, or close the value-class gaps in one that does. Use when asked to add seed data for a table, to act on gitlab:seed:value_class_report output, or when run-dev-fixtures fails because a newly added table holds no rows."
---

# Development fixtures for empty and thinly-seeded tables

`db:migrate:multi-version-upgrade` restores a PG dump and runs every newer
migration against it. A table with no rows, or with rows that never vary,
lets a migration pass without touching anything. The failure then lands on a
customer during a real upgrade.

## 1. Ask what the table needs

```shell
bundle exec rake "gitlab:seed:value_class_report[table_a,table_b]"
```

Each column comes back as either a specification or a gap:

```
  ci_triggers
    description (string): needs null, empty, ascii, glyphs
    project_id (integer): needs present
```

A class a constraint puts out of reach is never asked for, so `project_id`
above wants a value but not a null: a `CHECK (project_id IS NOT NULL)`
rejects one.

`needs` means the table holds no rows and this is what to write. `missing`
means rows exist but never take that shape.

Run it with no arguments to sweep every table; that form reports only tables
that hold rows and still miss a class.

## 2. Write the fixture

Add `db/fixtures/development/NN_<area>.rb`, or `ee/db/fixtures/development/`
for EE-only tables. Read `db/fixtures/development/41_code_review_workflow.rb`
first for the shape of one of these files: the `Gitlab::Seeder` wrapper, the
section methods, the progress output. Take its structure only. It predates
the rules below and breaks several of them, `User.first` and a single early
return that skips every section among them.

An EE fixture is seeded by `run-dev-fixtures-ee` and, on an EE image, by the
upgrade-stop dump. Prefer the FOSS path when the table also exists in CE, so
`run-dev-fixtures` seeds it too. A new fixture only reaches the dump once the
upgrade stop ships a release containing it, since the generator seeds from
inside the released image.

Rules that reviewers enforce on these files:

- **`insert_all`, not model creates.** The point is row shapes a long-lived
  instance really contains: values the schema allows even where current model
  validations reject them, such as a null in a column that is nullable today
  and might not be after a future migration. Those rows are the legacy data a
  migration has to handle.
- **Order every lookup.** `limit(2)` without `order(:id)` picks different
  rows on a re-run, so the fixture stops being idempotent and grows the
  table on every seed.
- **Populate sharding keys with the value their sync trigger derives**, not
  whatever is nearest to hand. A `namespace_id` is often the parent's
  `project_namespace_id`, not its `namespace_id`.
- **Do not rescue**, even though the file above does. A few fixtures swallow
  errors and the rest let them surface, so a table that stops seeding fails
  `run-dev-fixtures-ee` instead of quietly losing coverage. Copy its
  structure, not its `rescue` blocks.
- **Guard tables with no unique index** so a second run inserts nothing.
- **Make each section independently idempotent.** Find each intended row by
  its own identifying columns, not by a marker chosen by hand. One row is not
  evidence that the whole fixture has run, and one section's missing
  dependency is no reason to skip the sections around it.
- **Read the model behind every column you write.** The schema gives the
  storage type, the model says what the application really stores: a hashed
  attribute, an encrypted column, an enum, a callback that derives a value.
  Use the model's own mapping for a coded value rather than a raw integer,
  and a builder it exposes rather than a literal.
- **Read the rows back and check what was stored.** `insert_all` skips
  validations and callbacks but still casts and serializes through
  `type_for_attribute`, so a wrong literal is stored encoded rather than
  rejected. Run `valid?` over the persisted records to tell a deliberate
  legacy shape from a mistake, and compare one value with a row the
  application wrote.
- **Derive related parents from one another.** A project and the namespace it
  sits under, a build and its pipeline: choosing each with its own `.first`
  builds a combination the application never creates, and no validation
  rejects it.
- **A partitioned table needs an explicit `unique_by`.** Its model often
  declares `self.primary_key = :id` while the real key is composite, so
  `insert_all` infers `id`, finds no unique index for it and raises. Read the
  live index rather than the model.
- **Re-query on the whole `unique_by` key.** With
  `unique_by: [:project_id, :name]`, read the row back on both: `project_id`
  alone returns whichever row in that project sorts first, which need not
  be yours.
- **`where.not(a: nil, b: nil)` is NAND**, not AND: it keeps every row with
  either column set. Chain `.where.not(a: nil).where.not(b: nil)` instead,
  and check the filter against a row that should qualify and one that should
  not: an unchanged count is also what you get when every row already
  qualifies.
- **Take shared dependencies through the helpers the current files use.**
  `Gitlab::DatabaseImporters::AdminOrganizationImporter.seeded_admin` for the
  seeded admin and `.seeded_admin_organization` for the organization it
  belongs to. The helper looks the admin up by username and falls back to any
  admin; `User.first` is the lowest-id user and is not scoped to admins at
  all. For any other organization, infer it from a record you already hold
  rather than silencing `Gitlab/PreventOrganizationFirst`, which only the EE
  tree enforces.

## 3. Make sure it seeds where it matters

A fixture that writes nothing still leaves the job green, so this is the most
common blocking review comment on these files.

- **`run-dev-fixtures` does not seed like a GDK.** Many parent fixtures scope
  their work with `not_mass_generated` (`lib/gitlab/seeder.rb`), so a parent
  that exists locally can be absent exactly where the fixture has to run.
- **Create the parent rather than skip it.** When a row you depend on may not
  be there, make a minimal one. A warn-and-skip is indistinguishable from a
  fixture that worked.
- **Print what each section did**: inserted rows, found them already there,
  or skipped, naming the dependency it skipped on. Skip only a dependency you
  cannot cheaply create; the rule above covers the rest. Then count those
  lines in the `run-dev-fixtures` log, because fewer than sections is a
  silent skip.
- **Check the order against both things that seed.** `run-dev-fixtures-ee`
  copies the EE fixtures in beside the FOSS ones and runs one sorted list, so
  a file that reads another file's rows must sort after it; equal number
  prefixes sort alphabetically. The dump generator instead walks the FOSS
  tree and then the EE tree, so every FOSS file runs before every EE file
  whatever the prefixes say. A FOSS fixture cannot read EE rows at all, and
  an EE fixture may read FOSS rows only if it also sorts after them.
- **The upgrade-stop dump seeds in production mode**, where
  `Gitlab.dev_or_test_env?` is false. A fixture gated on it runs in CI but
  leaves nothing in the dump the upgrade test restores.

## 4. Verify it before opening anything

```shell
bundle exec rake db:seed_fu FILTER=<your_file>
bundle exec rake db:seed_fu FILTER=<your_file>
bundle exec rake "gitlab:seed:value_class_report[<your_tables>]"
```

Two runs must leave row counts unchanged, and the report should come back
quieter than it started. Run RuboCop with `--force-exclusion` so it agrees
with CI: `db/fixtures/**/*` sits in `AllCops: Exclude`, so a FOSS fixture is
never linted and only the EE tree is. Without the flag RuboCop reports
offences on a file CI never checks, and the disables you add for them are
noise.

## 5. Open the merge request

Ask whether to open it as a draft or as ready for review, then create it
following `.ai/merge-requests.md`, which includes `/assign me` so the author
owns it.

Request no reviewers. The author chooses who reviews, and the owning group
is the one to ask: it is the `feature_categories` entry in the table's
`db/docs/<table>.yml`.

In the description, say which value classes the rows now cover.

## Known limits of the report

- A broken foreign key reference is not checked; only null against present.
- `negative` is still offered on an integer column with no check constraint
  bounding it, which an enum cannot satisfy.
- Column types without rules, such as `binary` and `uuid`, are skipped.
