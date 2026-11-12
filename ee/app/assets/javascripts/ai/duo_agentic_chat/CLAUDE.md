# Duo Agentic Chat: agent instructions

## Tracking

- Every new user-facing feature in this directory ships with internal event tracking. Instrumentation is part of the feature, not a follow-up.
- Internal events record user interactions with the UI. Errors go to Sentry, not internal events.
- Track only through the observability SDK: `observability/events_tracker.js`.
- Never import `~/tracking` or the `InternalEvents` mixin directly in this directory (the SDK itself is the only allowed import site). It silently drops the session context (`session_id`, `flow_type`, `trigger_source`, `model`). Older components that still do are being migrated in https://gitlab.com/gitlab-org/gitlab/-/work_items/628467.
- Clicks in the chat are tracked automatically as `click_element_in_duo_chat`, unless handling the click already tracked a named event through the SDK. Do not add a named event only to count clicks.
- Give every new interactive element a `data-track-id` in kebab-case `<area>-<element>`, for example `session-pill-open`. Keep it static: no ids or other interpolated values. Without one, the event falls back to the tag name; `data-testid` is never used. Elements whose click tracks a named event do not need one.
- Track a named event synchronously in the click handler, before any `await`. Otherwise the catch-all counts the click as well.

## Adding a named event

Only when the interaction needs its own properties or gets reported on by itself.

1. Add the action constant to `constants.js`.
1. Add the event YAML to `ee/config/events/`. The `gitlab_internal_events_cli` gem can generate it. The `internal-events-definitions-validation-ee` CI job validates it against the schema.
1. Add a thin method on the SDK, built on `track` / `trackOnce`.
1. Cover it with a jest spec using the `useMockInternalEventsTracking` helper.

## Boundaries

- `ee/frontend_islands/apps/duo_next` is an isolated app and cannot import this SDK. Its tracking goes through its communication layer and is out of scope here.
