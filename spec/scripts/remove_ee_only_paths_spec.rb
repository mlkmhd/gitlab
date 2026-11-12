# frozen_string_literal: true

require 'fast_spec_helper'
require 'fileutils'
require 'open3'
require 'rspec-parameterized'
require 'tmpdir'

RSpec.describe 'scripts/remove-ee-only-paths.sh', feature_category: :tooling do
  root = File.expand_path('../..', __dir__)
  script = File.join(root, 'scripts/remove-ee-only-paths.sh')

  # Jobs run it with the image's /bin/sh: Dash on Debian, BusyBox on Alpine.
  shells = { 'sh' => %w[sh] }
  path_dirs = ENV.fetch('PATH', '').split(File::PATH_SEPARATOR)
  shells['dash'] = %w[dash] if path_dirs.any? { |dir| File.executable?(File.join(dir, 'dash')) }
  shells['busybox sh'] = %w[busybox sh] if path_dirs.any? { |dir| File.executable?(File.join(dir, 'busybox')) }

  let(:tmp_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  def create_files(*paths)
    paths.each do |path|
      full_path = File.join(tmp_dir, path)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, '')
    end
  end

  def write_list(content)
    create_files('.gitlab/ee-only-paths.txt')
    File.write(File.join(tmp_dir, '.gitlab/ee-only-paths.txt'), content)
  end

  def exist?(path)
    File.exist?(File.join(tmp_dir, path)) || File.symlink?(File.join(tmp_dir, path))
  end

  shells.each do |shell_name, shell_command|
    context "with #{shell_name}" do
      define_method(:run_script) do
        Open3.capture3(*shell_command, script, chdir: tmp_dir)
      end

      context 'with the list in this repository' do
        let(:ee_only_paths) do
          %w[
            ee/app/models/ee/user.rb
            domains/foo/ee/lib/foo.rb
            qa/spec/ee/foo_spec.rb
            qa/qa/specs/features/ee/foo_spec.rb
            qa/qa/ee/page.rb
            qa/qa/ee.rb
            CHANGELOG-EE.md
            changelogs/archive-ee.md
            changelogs/archive-12-ee.md
          ]
        end

        let(:foss_paths) do
          %w[
            app/models/user.rb
            domains/foo/lib/foo.rb
            qa/spec/foo_spec.rb
            qa/qa/specs/features/browser_ui/foo_spec.rb
            qa/qa.rb
            CHANGELOG.md
            changelogs/archive-12.md
            changelogs/README.md
          ]
        end

        before do
          create_files(*ee_only_paths, *foss_paths)
          write_list(File.read(File.join(root, '.gitlab/ee-only-paths.txt')))
        end

        it 'removes the EE-only paths and keeps the rest, including the list' do
          _, stderr, status = run_script

          expect(stderr).to be_empty
          expect(status).to be_success
          expect(ee_only_paths.select { |path| exist?(path) }).to be_empty
          expect(foss_paths + ['.gitlab/ee-only-paths.txt']).to all(satisfy { |path| exist?(path) })
          expect(exist?('ee')).to be(false)
          expect(exist?('domains/foo/ee')).to be(false)
        end
      end

      it 'ignores comments and blank lines, and strips surrounding whitespace' do
        create_files('ee/a.rb', 'jh/a.rb', 'keep.rb')
        write_list("# jh\n\n   \n  # keep.rb\n \t ee \t\r\nno-such-path\n")

        stdout, stderr, status = run_script

        expect(stderr).to be_empty
        expect(status).to be_success
        expect(stdout).to eq("Removing ee\n")
        expect(exist?('jh/a.rb')).to be(true)
        expect(exist?('keep.rb')).to be(true)
      end

      it 'reads a last entry without a trailing newline' do
        create_files('ee/a.rb')
        write_list('ee')

        _, _, status = run_script

        expect(status).to be_success
        expect(exist?('ee')).to be(false)
      end

      it 'expands globs without splitting on whitespace' do
        create_files('docs/a b-ee.md', 'docs/c-ee.md', 'docs/c.md')
        write_list("docs/* *-ee.md\ndocs/?-ee.md\n")

        _, _, status = run_script

        expect(status).to be_success
        expect(exist?('docs/a b-ee.md')).to be(false)
        expect(exist?('docs/c-ee.md')).to be(false)
        expect(exist?('docs/c.md')).to be(true)
      end

      it 'allows entries under .gitlab' do
        create_files('.gitlab/ee-thing.yml')
        write_list(".gitlab/ee-thing.yml\n")

        _, _, status = run_script

        expect(status).to be_success
        expect(exist?('.gitlab/ee-thing.yml')).to be(false)
      end

      context 'with an invalid entry' do
        where(:entry, :problem) do
          [
            ['/ee', 'leading /'],
            ['ee/', 'trailing /'],
            ['ee//jh', 'empty path segment'],
            ['.', '. path segment'],
            ['./ee', '. path segment'],
            ['ee/./jh', '. path segment'],
            ['ee/.', '. path segment'],
            ['..', '.. path segment'],
            ['../ee', '.. path segment'],
            ['ee/../jh', '.. path segment'],
            ['ee/..', '.. path segment'],
            ['.git', 'first path segment is .git'],
            ['.git/hooks', 'first path segment is .git'],
            ['ee # comment', '# is only allowed at the start of a comment line'],
            ['ee#', '# is only allowed at the start of a comment line']
          ]
        end

        with_them do
          it 'fails naming the line and the problem, and removes nothing' do
            create_files('ee/a.rb')
            write_list("# comment\nee\n  #{entry}  \n")

            stdout, stderr, status = run_script

            expect(status).not_to be_success
            expect(stdout).to be_empty
            expect(stderr).to eq("ERROR: .gitlab/ee-only-paths.txt:3: invalid entry '#{entry}': #{problem}\n")
            expect(exist?('ee/a.rb')).to be(true)
          end
        end
      end

      context 'with an entry matching .git or a dot segment' do
        where(:entry) do
          %w[.g?t .[g]it .*]
        end

        with_them do
          it 'fails naming the line, the match and the problem, and removes nothing' do
            create_files('ee/a.rb', '.git/HEAD')
            write_list("ee\n#{entry}\n")

            stdout, stderr, status = run_script

            expect(status).not_to be_success
            expect(stdout).to be_empty
            # `.*` matches `.` first in Dash, but `.git` in Bash, which skips `.` and `..`.
            prefix = "ERROR: .gitlab/ee-only-paths.txt:2: entry '#{entry}' matches"
            expect(stderr).to eq("#{prefix} '.git': first path segment is .git\n")
              .or eq("#{prefix} '.': . path segment\n")
            expect(exist?('ee/a.rb')).to be(true)
            expect(exist?('.git/HEAD')).to be(true)
          end
        end
      end

      it 'fails when the list has no entries' do
        create_files('ee/a.rb')
        write_list("# comment\n\n")

        _, stderr, status = run_script

        expect(status).not_to be_success
        expect(stderr).to eq("ERROR: .gitlab/ee-only-paths.txt has no entries\n")
        expect(exist?('ee/a.rb')).to be(true)
      end

      it 'fails when the list is missing' do
        create_files('ee/a.rb')

        _, stderr, status = run_script

        expect(status).not_to be_success
        expect(stderr).to eq("ERROR: .gitlab/ee-only-paths.txt not found\n")
        expect(exist?('ee/a.rb')).to be(true)
      end

      context 'when the list is not a regular file' do
        where(:kind) { %i[directory dangling_symlink] }

        with_them do
          it 'fails' do
            create_files('ee/a.rb')
            list = File.join(tmp_dir, '.gitlab/ee-only-paths.txt')
            FileUtils.mkdir_p(kind == :directory ? list : File.dirname(list))
            File.symlink(File.join(tmp_dir, 'missing'), list) if kind == :dangling_symlink

            _, stderr, status = run_script

            expect(status).not_to be_success
            expect(stderr).to eq("ERROR: .gitlab/ee-only-paths.txt is not a readable regular file\n")
            expect(exist?('ee/a.rb')).to be(true)
          end
        end
      end
    end
  end
end
