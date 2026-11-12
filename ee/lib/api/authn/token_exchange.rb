# frozen_string_literal: true

module API
  module Authn
    # PoC token-exchange endpoint for modular services. Marked experimental --
    # the surface is expected to be superseded by GATE L2 later
    # (ADR-016 / ADR-019).
    class TokenExchange < ::API::Base
      include APIGuard

      feature_category :system_access

      MAX_EXPIRES_IN_SECONDS = ::Authn::TokenExchange::Audience.all.map(&:max_ttl).max

      # RFC 8693 token type URI for the JWT this endpoint issues.
      ISSUED_TOKEN_TYPE = 'urn:ietf:params:oauth:token-type:jwt'

      before do
        authenticate!
      end

      namespace 'token_exchange' do
        desc 'Issue a short-lived JWT for a single modular-service audience' do
          detail 'Issues a short-lived RS256 JWT scoped to one modular-service audience ' \
            '(such as the Artifact Registry). Claims include the requesting user id (sub), ' \
            'organization id, and deployment realm (saas / self-managed). Presented to the ' \
            'corresponding backend and verified against the instance JWKS. The response uses ' \
            'the RFC 8693 names. token and access_token have the same value, with ' \
            'access_token preferred where possible.'
          success code: 201, model: ::API::Entities::Authn::TokenExchange
          failure [
            { code: 400, message: 'Bad Request' },
            { code: 401, message: 'Unauthorized' },
            { code: 403, message: 'Forbidden' }
          ]
          tags %w[token_exchange]
        end
        route_setting :lifecycle, :experiment
        # Internal-only endpoint -- not exposed via the granular PAT system.
        # All existing PATs (legacy or granular) can call this endpoint without
        # needing to opt into a per-endpoint permission.
        # skip_job_token_policies: this endpoint does not act on a project
        # resource (no read_*/admin_* policy from ci_job_token_policies.json fits).
        # The job token is only the auth credential; the token we mint is
        # scoped via `audience`.
        route_setting :authorization,
          skip_granular_token_authorization: :modular_service_token_exchange,
          skip_job_token_policies: true
        # AR auth interface agreement R1: must accept CI job tokens.
        # The endpoint is not project-scoped, so any job token authenticates as
        # the per-build bot user (current_user becomes the bot User).
        #
        # Deploy tokens are deliberately NOT enabled here: DeployToken is not a
        # User, so our User-shaped payload (sub, gitlab_organization_id) doesn't
        # apply. R1 lists deploy tokens but R3 ("the principal's GitLab ID") has
        # no defined shape for non-User callers. Tracked as a follow-up.
        route_setting :authentication, job_token_allowed: true
        params do
          requires :audience, type: String,
            values: ::Authn::TokenExchange::Audience.names,
            desc: 'Target service audience.'
          optional :expires_in, type: Integer,
            values: 1..MAX_EXPIRES_IN_SECONDS,
            default: ::Authn::TokenExchange::TokenIssuer::DEFAULT_TTL_SECONDS,
            desc: 'Requested token lifetime in seconds. ' \
              'The granted lifetime may be shorter than requested depending on the ' \
              'authentication method used to call this endpoint or the audience.'
        end
        helpers do
          # Expected to stay at zero under the closed beta. If it moves, the
          # single-organization assumption the resolver rests on is wrong.
          def ambiguous_organization_counter
            ::Gitlab::Metrics.counter(
              :token_exchange_ambiguous_organization_total,
              'Token exchange requests refused because the audience could not pick one ' \
                'organization for the caller'
            )
          end

          # An audience that is off for this caller, or closed to job tokens, answers
          # as an unknown one, so a caller cannot tell it exists.
          def authorize_audience!(audience)
            return if audience.enabled?(current_user) && (audience.job_token_allowed? || !current_authenticated_job)

            error!('audience does not have a valid value', 400)
          end

          # A job token must not mint a credential that outlives its job. Past
          # the deadline the runner has already killed the script, so refuse
          # rather than grant a window the caller could keep renewing.
          def job_token_ttl_ceiling!(job)
            deadline = job.started_at && job.timeout_value && (job.started_at + job.timeout_value.seconds)
            # Deadline unknown: the default, not the endpoint cap.
            return ::Authn::TokenExchange::TokenIssuer::DEFAULT_TTL_SECONDS unless deadline

            remaining = (deadline - Time.current).to_i
            forbidden!(_('The job that requested this token has exceeded its timeout.')) unless remaining > 0

            remaining
          end
        end

        post do
          audience = ::Authn::TokenExchange::Audience.find(declared_params[:audience])
          authorize_audience!(audience)

          check_rate_limit!(:token_exchange, scope: { user: current_user })

          ttl = [declared_params[:expires_in], audience.max_ttl].min
          ttl = [ttl, job_token_ttl_ceiling!(current_authenticated_job)].min if current_authenticated_job

          # Never the X-GitLab-Organization-ID header. Nothing verifies it, and
          # package clients cannot send it at all.
          organization =
            begin
              ::Authn::TokenExchange::OrganizationResolver.new(current_user, audience: audience.name).execute
            rescue ::Authn::TokenExchange::OrganizationResolver::AmbiguousOrganizationError => e
              ambiguous_organization_counter.increment(audience: audience.name)
              conflict!(e.message)
            end

          token = ::Authn::TokenExchange::TokenIssuer.new(
            audiences: audience.audiences,
            user: current_user,
            organization: organization,
            ttl: ttl
          ).token

          # TODO (production): emit a `Gitlab::InternalEvents.track_event` for usage analytics
          # (event name e.g. `token_exchange_issued`, additional_properties carrying the
          # audience). Requires an event YAML in config/events/.

          present(
            {
              access_token: token,
              issued_token_type: ISSUED_TOKEN_TYPE,
              token_type: 'Bearer',
              expires_in: ttl,
              # Same value as access_token. Artifact Registry clients read it today, and Docker's token auth
              # flow expects it too: https://gitlab.com/gitlab-org/gitlab/-/issues/604870
              token: token
            },
            with: ::API::Entities::Authn::TokenExchange
          )
        end
      end
    end
  end
end
