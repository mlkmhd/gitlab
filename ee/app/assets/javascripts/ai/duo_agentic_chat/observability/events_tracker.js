import { InternalEvents } from '~/tracking';
import {
  TRIGGER_SOURCE_WEB_CHAT,
  TRACKING_EVENT_RECOMMEND_TOOL,
  TRACKING_EVENT_TOOL_SUCCEEDED,
  TRACKING_EVENT_TOOL_FAILED,
  TRACKING_EVENT_APPROVE_TOOL,
  TRACKING_EVENT_DENY_TOOL,
  TRACKING_EVENT_CLICK_THROUGH_FLOW_WIDGET,
  TRACKING_EVENT_CLICK_THROUGH_SESSION_PILL,
  TRACKING_EVENT_CANCEL_SESSION_FROM_SESSION_PILL,
  TRACKING_EVENT_RESIZE_PANEL,
  TRACKING_EVENT_MAXIMIZE_PANEL,
  TRACKING_EVENT_MINIMIZE_PANEL,
  TRACKING_EVENT_USER_CLICKED_RETRY,
  TRACKING_EVENT_RETRY_SUCCEEDED,
  TRACKING_EVENT_RETRY_FAILED,
  TRACKING_EVENT_NAVIGATE_RETRY_ALTERNATIVE,
  TRACKING_EVENT_CLICK_ELEMENT,
  TRACKING_EVENT_SUBMIT_SLASH_COMMAND,
  TRACKING_EVENT_ATTACH_FILE,
  TRACKING_EVENT_REJECT_FILE_ATTACHMENT,
  TRACKING_EVENT_SUBMIT_FILE_ATTACHMENTS,
} from '../constants';
import { MAX_ATTACHMENT_BYTES } from '../utils/attachment_utils';

const trackedDedupKeys = new Set();

// Lets the click catch-all tell whether a click already fired a named event.
let activeClick = null;

// Text fields are left out on purpose: typing into the prompt is never tracked.
const CLICKABLE_SELECTOR = [
  'a',
  'button',
  '[role="button"]',
  '[role="option"]',
  '[role="menuitem"]',
  'summary',
  'input[type="checkbox"]',
  'input[type="radio"]',
  '[data-track-id]',
].join(', ');

// Upper bounds in KB. The size is bucketed so no exact byte count is recorded,
// and the last bucket follows the per-file limit so the two cannot drift apart.
const ATTACHMENT_SIZE_BUCKETS_KB = [100, 500, 1024, MAX_ATTACHMENT_BYTES / 1024];

const attachmentSizeBucket = (byteSize) =>
  ATTACHMENT_SIZE_BUCKETS_KB.find((kb) => byteSize <= kb * 1024) ?? null;

const initialContext = () => ({
  sessionId: undefined,
  flowType: undefined,
  triggerSource: TRIGGER_SOURCE_WEB_CHAT,
  model: undefined,
});

let context = initialContext();

// The session context every chat event carries so it can be correlated back to
// the session it occurred in. Merged automatically by `track`; callers only
// pass what is specific to their event.
const contextProperties = () => ({
  session_id: context.sessionId,
  flow_type: context.flowType,
  trigger_source: context.triggerSource,
  model: context.model,
});

// A tool approval request and the tool message that resolves it arrive under
// one message_id, so the key needs the event and tool to tell them apart.
const toolDedupKey = (event, { messageId, toolName } = {}) =>
  messageId && `${event}:${messageId}:${toolName}`;

/**
 * The tracking SDK for Duo Agentic Chat. All internal events in this directory
 * go through it: calling `InternalEvents` directly drops the session context.
 */
export const EventsTracker = {
  reset() {
    trackedDedupKeys.clear();
    context = initialContext();
  },

  updateContext({ sessionId, flowType, triggerSource, model } = {}) {
    if (sessionId !== undefined) context.sessionId = sessionId;
    if (flowType !== undefined) context.flowType = flowType;
    if (triggerSource !== undefined) context.triggerSource = triggerSource;
    if (model !== undefined) context.model = model;
  },

  /**
   * Tracks `event` with the shared session context merged in automatically.
   * `properties` win over context on key collisions.
   */
  track(event, properties = {}) {
    // eventPhase drops to NONE once dispatch ends, so stream events and anything
    // tracked after an `await` never count as the click's named event.
    if (activeClick?.event.eventPhase) activeClick.tracked = true;
    InternalEvents.trackEvent(event, { ...contextProperties(), ...properties });
  },

  /**
   * Replay-safe `track`: streams replay messages on reconnect and thread reload,
   * so this fires once per `dedupKey`. Without a key nothing is tracked.
   */
  trackOnce(event, dedupKey, properties = {}) {
    if (!dedupKey || trackedDedupKeys.has(dedupKey)) return;
    trackedDedupKeys.add(dedupKey);
    this.track(event, properties);
  },

  /**
   * Tracks every click on an interactive element inside `root` as
   * `click_element_in_duo_chat`, unless handling the click already tracked a
   * named event. Returns a function that stops observing.
   */
  observeClicks(root) {
    const onClick = (event) => {
      const element = event.target?.closest?.(CLICKABLE_SELECTOR);
      if (!element || !root.contains(element)) return;

      const click = { event, tracked: false };
      activeClick = click;
      // Capture runs before the click's own handlers, which may track a named
      // event. Decide once they have all run.
      setTimeout(() => {
        if (activeClick === click) activeClick = null;
        if (click.tracked) return;
        // Not `data-testid`: test ids get renamed in spec refactors and some are
        // dynamic, which would silently break dashboards.
        this.track(TRACKING_EVENT_CLICK_ELEMENT, {
          property: element.dataset.trackId || element.tagName.toLowerCase(),
        });
      });
    };

    // Capture, so a stopPropagation() inside the chat cannot hide the click.
    root.addEventListener('click', onClick, true);
    return () => root.removeEventListener('click', onClick, true);
  },

  trackToolRecommended({ messageId, toolName } = {}) {
    this.trackOnce(
      TRACKING_EVENT_RECOMMEND_TOOL,
      toolDedupKey(TRACKING_EVENT_RECOMMEND_TOOL, { messageId, toolName }),
      { tool_name: toolName },
    );
  },

  trackToolSucceeded({ messageId, toolName } = {}) {
    this.trackOnce(
      TRACKING_EVENT_TOOL_SUCCEEDED,
      toolDedupKey(TRACKING_EVENT_TOOL_SUCCEEDED, { messageId, toolName }),
      { tool_name: toolName },
    );
  },

  trackToolFailed({ messageId, toolName } = {}) {
    this.trackOnce(
      TRACKING_EVENT_TOOL_FAILED,
      toolDedupKey(TRACKING_EVENT_TOOL_FAILED, { messageId, toolName }),
      { tool_name: toolName },
    );
  },

  trackApproveTool({ toolName } = {}) {
    this.track(TRACKING_EVENT_APPROVE_TOOL, { tool_name: toolName });
  },

  trackDenyTool({ toolName } = {}) {
    this.track(TRACKING_EVENT_DENY_TOOL, { tool_name: toolName });
  },

  trackClickThroughFlowWidget({ toolName } = {}) {
    this.track(TRACKING_EVENT_CLICK_THROUGH_FLOW_WIDGET, { tool_name: toolName });
  },

  // `label` rather than a custom property: the command name lands in a dedicated
  // Snowflake column, so a per-command metric needs no Data team work.
  trackSlashCommand({ commandName } = {}) {
    this.track(TRACKING_EVENT_SUBMIT_SLASH_COMMAND, { label: commandName });
  },

  trackAttachFile({ method, mimeType, byteSize } = {}) {
    this.track(TRACKING_EVENT_ATTACH_FILE, {
      label: method,
      property: mimeType,
      value: attachmentSizeBucket(byteSize),
    });
  },

  trackRejectFileAttachment({ method, reason, count } = {}) {
    this.track(TRACKING_EVENT_REJECT_FILE_ATTACHMENT, {
      label: method,
      property: reason,
      value: count,
    });
  },

  trackSubmitFileAttachments({ count } = {}) {
    this.track(TRACKING_EVENT_SUBMIT_FILE_ATTACHMENTS, { value: count });
  },

  trackClickThroughSessionPill({ workflowId } = {}) {
    this.track(TRACKING_EVENT_CLICK_THROUGH_SESSION_PILL, { workflow_id: workflowId });
  },

  trackCancelSessionFromSessionPill({ workflowId } = {}) {
    this.track(TRACKING_EVENT_CANCEL_SESSION_FROM_SESSION_PILL, { workflow_id: workflowId });
  },

  trackPanelResized({ value } = {}) {
    this.track(TRACKING_EVENT_RESIZE_PANEL, { value });
  },

  trackPanelMaximized({ value } = {}) {
    this.track(TRACKING_EVENT_MAXIMIZE_PANEL, { value });
  },

  trackPanelMinimized({ value } = {}) {
    this.track(TRACKING_EVENT_MINIMIZE_PANEL, { value });
  },

  // attemptNumber and index below map to the built-in numeric `value` property,
  // which lands in a dedicated Snowflake column and is queryable without Data team work.
  trackRetryMessage({ attemptNumber } = {}) {
    this.track(TRACKING_EVENT_USER_CLICKED_RETRY, { value: attemptNumber });
  },

  trackRetrySucceeded({ attemptNumber } = {}) {
    this.track(TRACKING_EVENT_RETRY_SUCCEEDED, { value: attemptNumber });
  },

  trackRetryFailed({ attemptNumber } = {}) {
    this.track(TRACKING_EVENT_RETRY_FAILED, { value: attemptNumber });
  },

  trackNavigateRetryAlternative({ index } = {}) {
    this.track(TRACKING_EVENT_NAVIGATE_RETRY_ALTERNATIVE, { value: index });
  },
};
