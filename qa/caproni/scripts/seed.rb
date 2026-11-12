#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs the programs of the given seeders on the primary in one `gitlab-rails runner`.
# Each runner boots Rails in the toolbox pod, which takes about a minute, so a job
# that needs several seeders lists them all in one call:
#
#   scripts/seed.rb admin_token oidc_application
#
# CI starts it alongside `caproni up`, so Rails boots while the migrations run:
# it waits for the toolbox pod, and the runner waits for the migrations to seed root.
#
# Shim: Caproni has no post-deploy hook, so seed here
# https://gitlab.com/gitlab-org/caproni/-/issues/192

require 'open3'

module Seed
  module_function

  WAIT_TIMEOUT = 1200

  # Array form throughout: no shell, so nothing here needs quoting or escaping.
  def caproni(config, namespace, *args, **opts)
    Open3.capture3('caproni', '-c', config, 'kubectl', '-n', namespace, *args, **opts)
  end

  # deadline: shared with the seeding retries, so the whole run stays within WAIT_TIMEOUT
  def toolbox_pod(config, namespace, deadline)
    puts 'Waiting for the toolbox pod'
    last_error = 'no toolbox pod yet'

    # Until the gitlab release is installed there's no pod yet, and a deploy retry replaces it
    loop do
      out, err, status = caproni(config, namespace, 'get', 'pods', '--selector=app=toolbox',
        '-o', 'jsonpath={.items[0].metadata.name}')
      pod = status.success? ? out.strip : ''
      last_error = failure_line(out, err) unless status.success?

      unless pod.empty?
        out, err, status = caproni(config, namespace, 'wait', '--for=condition=Ready', "pod/#{pod}", '--timeout=60s')
        return pod if status.success?

        last_error = failure_line(out, err)
      end

      abort("The toolbox pod wasn't ready within #{WAIT_TIMEOUT}s: #{last_error}") if monotonic_now > deadline

      sleep 5
    end
  end

  # Prepended to the seeders' programs: the runner can boot before the migrations job has
  # loaded the schema and seeded root, which every seeder needs
  def wait_for_database_program
    <<~RUBY
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + #{WAIT_TIMEOUT}
      until (User.exists?(username: 'root') rescue false)
        abort('The root user was not seeded within #{WAIT_TIMEOUT}s') if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        sleep 2
      end
    RUBY
  end

  # One line only: no reason to widen what a failure prints. Prefer Ruby's exception line,
  # then the last line that isn't kubectl's own "command terminated with exit code".
  def failure_line(out, err)
    lines = (err.lines + out.lines).map(&:strip).reject { |line| line.empty? || line.start_with?('command terminated') }
    lines.find { |line| line.match?(/\([A-Z][\w:]*\)\z/) } || lines.last || 'no output'
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def program(seeders)
    seeders.map(&:program_from_env).join
  end

  def run(seeders)
    # Built first, so a missing variable aborts before waiting for the pod
    stdin = program(seeders)
    description = seeders.map(&:description).join(' and ')
    # The primary's namespace: everything seeded here lives on the instance under test
    namespace = ENV.fetch('NAMESPACE', 'gitlab')
    # From this script's location, so cwd does not matter
    config = ENV.fetch('CAPRONI_CONFIG') { File.expand_path('../caproni.yaml', __dir__) }

    out = err = status = nil
    deadline = monotonic_now + WAIT_TIMEOUT
    attempt = 0

    # A runner that boots before the migrations job has loaded the schema fails, and so does
    # one whose pod a deploy retry replaced, so keep trying until the deadline
    loop do
      attempt += 1
      pod = toolbox_pod(config, namespace, deadline)

      puts "#{Time.now.utc.strftime('%H:%M:%S')} seeding #{description} via #{pod}"
      # stdin, not argv: keeps tokens and secrets out of the process list
      out, err, status = caproni(config, namespace, 'exec', '-i', pod, '-c', 'toolbox', '--',
        'gitlab-rails', 'runner', '-', stdin_data: wait_for_database_program + stdin)
      break if status.success? || monotonic_now > deadline

      puts "#{Time.now.utc.strftime('%H:%M:%S')} attempt #{attempt} failed: #{failure_line(out, err)}"
      sleep 10
    end

    unless status.success?
      warn "Failed to seed #{description}"
      warn failure_line(out, err)
      exit 1
    end

    puts out.strip unless out.strip.empty?
  end
end

if __FILE__ == $PROGRAM_NAME
  require_relative 'seed_admin_token'
  require_relative 'seed_oidc_application'
  require_relative 'seed_gitlab_duo'

  seeders = {
    'admin_token' => SeedAdminToken,
    'oidc_application' => SeedOidcApplication,
    'gitlab_duo' => SeedGitlabDuo
  }
  usage = "Usage: #{$PROGRAM_NAME} #{seeders.keys.join('|')}..."
  abort(usage) if ARGV.empty?

  Seed.run(ARGV.map { |name| seeders.fetch(name) { abort("Unknown seeder #{name}. #{usage}") } })
end
