# frozen_string_literal: true

class Projects::GraphsController < Projects::ApplicationController
  include ExtractsPath
  include ProductAnalyticsTracking
  include HandlesGitalyErrors

  # Authorize
  before_action :require_non_empty_project
  before_action :assign_ref_vars
  before_action :validate_ref!
  before_action :authorize_read_repository_graphs!

  track_event :charts,
    name: 'p_analytics_repo',
    action: 'perform_analytics_usage_action',
    label: 'redis_hll_counters.analytics.analytics_total_unique_counts_monthly',
    destinations: %i[redis_hll snowplow]

  feature_category :source_code_management, [:show, :commits, :languages, :charts]
  urgency :low, [:show]

  feature_category :continuous_integration, [:ci]
  urgency :low, [:ci]

  MAX_COMMITS = 6000
  CONTRIBUTOR_GRAPH_CACHE_EXPIRY = 1.hour

  def show
    @ref_type = ref_type

    respond_to do |format|
      format.html
      format.json do
        render json: cached_contributor_graph_json
      end
    end
  end

  def commits
    redirect_to action: 'charts'
  end

  def languages
    redirect_to action: 'charts'
  end

  def charts
    get_commits
    get_languages
    get_daily_coverage_options
  end

  def ci
    redirect_to charts_project_pipelines_path(@project)
  end

  private

  # Percent-encoded characters (e.g. `%7E`) bypass the route's git_reference_regex
  # constraint, so a ref like `sha~1` reaches here and breaks URL generation in the view.
  def validate_ref!
    render_404 unless Gitlab::GitRefValidator.validate(@ref, skip_head_ref_check: true)
  end

  def ref
    @fully_qualified_ref || @ref
  end

  # The payload depends only on the resolved commit, so repeat views of the
  # same ref skip the 6000-commit Gitaly walk until the ref moves.
  def cached_contributor_graph_json
    include_stats = include_stats?
    cache_key = [
      'projects', @project.id, 'contributor_graph', @commit.sha, include_stats ? 'with_stats' : 'without_stats'
    ]

    Rails.cache.fetch(cache_key, expires_in: CONTRIBUTOR_GRAPH_CACHE_EXPIRY) do
      Gitlab::Json.dump(contributor_graph_log(include_stats))
    end
  end

  def contributor_graph_log(include_stats)
    commits = @project.repository.commits(
      ref,
      limit: MAX_COMMITS,
      skip_merges: true,
      include_shortstat: include_stats
    )

    commits.map { |commit| contributor_graph_commit_data(commit, include_stats: include_stats) }
  end

  def contributor_graph_commit_data(commit, include_stats:)
    data = {
      id: commit.id,
      author_name: commit.author_name,
      author_email: commit.author_email,
      date: commit.committed_date.to_date.iso8601
    }

    return data unless include_stats

    short_stats = commit.short_stats
    data.merge(additions: short_stats&.additions || 0, deletions: short_stats&.deletions || 0)
  end

  def include_stats?
    ActiveModel::Type::Boolean.new.cast(params.permit(:with_stats)[:with_stats])
  end

  def get_commits
    @commits_limit = 2000
    @commits = @project.repository.commits(ref, limit: @commits_limit, skip_merges: true)
    @commits_graph = Gitlab::Graphs::Commits.new(@commits)
    @commits_per_week_days = @commits_graph.commits_per_week_days
    @commits_per_time = @commits_graph.commits_per_time
    @commits_per_month = @commits_graph.commits_per_month
  end

  def get_languages
    @languages =
      ::Projects::RepositoryLanguagesService.new(@project, current_user).execute.map do |lang|
        { value: lang.share, label: lang.name, color: lang.color, highlight: lang.color }
      end
  end

  def get_daily_coverage_options
    return unless can?(current_user, :read_build_report_results, project)

    date_today = Date.current
    report_window = ::Ci::DailyBuildGroupReportResultsFinder::REPORT_WINDOW

    @daily_coverage_options = {
      base_params: {
        start_date: date_today - report_window,
        end_date: date_today,
        ref_path: @project.repository.expand_ref(ref),
        param_type: 'coverage'
      },
      download_path: namespace_project_ci_daily_build_group_report_results_path(
        namespace_id: @project.namespace,
        project_id: @project,
        format: :csv
      ),
      graph_api_path: namespace_project_ci_daily_build_group_report_results_path(
        namespace_id: @project.namespace,
        project_id: @project,
        format: :json
      )
    }
  end

  def tracking_namespace_source
    project.namespace
  end

  def tracking_project_source
    project
  end
end

Projects::GraphsController.prepend_mod
