import { useMockInternalEventsTracking } from 'helpers/tracking_internal_events_helper';
import { EventsTracker } from 'ee/ai/duo_agentic_chat/observability/events_tracker';
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
  TRACKING_EVENT_SUBMIT_SLASH_COMMAND,
  TRACKING_EVENT_CLICK_ELEMENT,
  TRACKING_EVENT_ATTACH_FILE,
  TRACKING_EVENT_REJECT_FILE_ATTACHMENT,
  TRACKING_EVENT_SUBMIT_FILE_ATTACHMENTS,
} from 'ee/ai/duo_agentic_chat/constants';

describe('duo_agentic_chat/observability/events_tracker', () => {
  const { bindInternalEventDocument } = useMockInternalEventsTracking();

  const sessionId = '42';
  const flowType = 'my_agent';
  const model = 'claude-3-5-sonnet';
  const messageId = 'msg-1';
  const toolName = 'create_commit';

  let trackEventSpy;

  beforeEach(() => {
    EventsTracker.reset();
    ({ trackEventSpy } = bindInternalEventDocument());
  });

  const sharedProperties = () => ({
    session_id: sessionId,
    flow_type: flowType,
    trigger_source: TRIGGER_SOURCE_WEB_CHAT,
    model,
  });

  describe.each`
    method                    | trackingEvent
    ${'trackToolRecommended'} | ${TRACKING_EVENT_RECOMMEND_TOOL}
    ${'trackToolSucceeded'}   | ${TRACKING_EVENT_TOOL_SUCCEEDED}
    ${'trackToolFailed'}      | ${TRACKING_EVENT_TOOL_FAILED}
  `('$method', ({ method, trackingEvent }) => {
    beforeEach(() => EventsTracker.updateContext({ sessionId, flowType, model }));

    it('tracks with tool name and context', () => {
      EventsTracker[method]({ messageId, toolName });

      expect(trackEventSpy).toHaveBeenCalledWith(trackingEvent, {
        tool_name: toolName,
        ...sharedProperties(),
      });
    });

    it('does not track the same messageId twice', () => {
      EventsTracker[method]({ messageId, toolName });
      EventsTracker[method]({ messageId, toolName });

      expect(trackEventSpy).toHaveBeenCalledTimes(1);
    });

    it('does not track when messageId is missing', () => {
      EventsTracker.trackToolRecommended({ toolName });

      expect(trackEventSpy).not.toHaveBeenCalled();
    });
  });

  describe('when messages share a message ID', () => {
    beforeEach(() => EventsTracker.updateContext({ sessionId, flowType, model }));

    it('tracks the tool request and its result separately', () => {
      EventsTracker.trackToolRecommended({ messageId, toolName });
      EventsTracker.trackToolSucceeded({ messageId, toolName });

      expect(trackEventSpy).toHaveBeenCalledTimes(2);
      expect(trackEventSpy).toHaveBeenCalledWith(TRACKING_EVENT_RECOMMEND_TOOL, {
        tool_name: toolName,
        ...sharedProperties(),
      });
      expect(trackEventSpy).toHaveBeenCalledWith(TRACKING_EVENT_TOOL_SUCCEEDED, {
        tool_name: toolName,
        ...sharedProperties(),
      });
    });

    it('tracks calls to different tools separately', () => {
      EventsTracker.trackToolRecommended({ messageId, toolName });
      EventsTracker.trackToolRecommended({ messageId, toolName: 'read_repository_file' });

      expect(trackEventSpy).toHaveBeenCalledTimes(2);
      expect(trackEventSpy).toHaveBeenCalledWith(TRACKING_EVENT_RECOMMEND_TOOL, {
        tool_name: toolName,
        ...sharedProperties(),
      });
      expect(trackEventSpy).toHaveBeenCalledWith(TRACKING_EVENT_RECOMMEND_TOOL, {
        tool_name: 'read_repository_file',
        ...sharedProperties(),
      });
    });
  });

  describe.each`
    method                           | trackingEvent
    ${'trackApproveTool'}            | ${TRACKING_EVENT_APPROVE_TOOL}
    ${'trackDenyTool'}               | ${TRACKING_EVENT_DENY_TOOL}
    ${'trackClickThroughFlowWidget'} | ${TRACKING_EVENT_CLICK_THROUGH_FLOW_WIDGET}
  `('$method', ({ method, trackingEvent }) => {
    it('tracks with tool name and context', () => {
      EventsTracker.updateContext({ sessionId, flowType, model });
      EventsTracker[method]({ toolName });

      expect(trackEventSpy).toHaveBeenCalledWith(trackingEvent, {
        tool_name: toolName,
        ...sharedProperties(),
      });
    });
  });

  describe('trackSlashCommand', () => {
    beforeEach(() => EventsTracker.updateContext({ sessionId, flowType, model }));

    it('tracks with the command name and context', () => {
      EventsTracker.trackSlashCommand({ commandName: '/goal' });

      expect(trackEventSpy).toHaveBeenCalledWith(TRACKING_EVENT_SUBMIT_SLASH_COMMAND, {
        label: '/goal',
        ...sharedProperties(),
      });
    });

    it('tracks no label when no command name is given', () => {
      EventsTracker.trackSlashCommand();

      expect(trackEventSpy).toHaveBeenCalledWith(TRACKING_EVENT_SUBMIT_SLASH_COMMAND, {
        label: undefined,
        ...sharedProperties(),
      });
    });
  });

  describe('trackAttachFile', () => {
    beforeEach(() => EventsTracker.updateContext({ sessionId, flowType, model }));

    it('tracks with the method, MIME type and context', () => {
      EventsTracker.trackAttachFile({ method: 'paste', mimeType: 'image/png', byteSize: 1 });

      expect(trackEventSpy).toHaveBeenCalledWith(TRACKING_EVENT_ATTACH_FILE, {
        label: 'paste',
        property: 'image/png',
        value: 100,
        ...sharedProperties(),
      });
    });

    it.each`
      byteSize           | bucket
      ${100 * 1024}      | ${100}
      ${100 * 1024 + 1}  | ${500}
      ${1024 * 1024}     | ${1024}
      ${2 * 1024 * 1024} | ${2048}
      ${3 * 1024 * 1024} | ${null}
    `('buckets $byteSize bytes as $bucket KB', ({ byteSize, bucket }) => {
      EventsTracker.trackAttachFile({ byteSize });

      expect(trackEventSpy).toHaveBeenCalledWith(
        TRACKING_EVENT_ATTACH_FILE,
        expect.objectContaining({ value: bucket }),
      );
    });
  });

  describe('trackRejectFileAttachment', () => {
    it('tracks with the method, reason, count and context', () => {
      EventsTracker.updateContext({ sessionId, flowType, model });
      EventsTracker.trackRejectFileAttachment({
        method: 'drag_and_drop',
        reason: 'too_many',
        count: 3,
      });

      expect(trackEventSpy).toHaveBeenCalledWith(TRACKING_EVENT_REJECT_FILE_ATTACHMENT, {
        label: 'drag_and_drop',
        property: 'too_many',
        value: 3,
        ...sharedProperties(),
      });
    });
  });

  describe('trackSubmitFileAttachments', () => {
    it('tracks with the attachment count and context', () => {
      EventsTracker.updateContext({ sessionId, flowType, model });
      EventsTracker.trackSubmitFileAttachments({ count: 3 });

      expect(trackEventSpy).toHaveBeenCalledWith(TRACKING_EVENT_SUBMIT_FILE_ATTACHMENTS, {
        value: 3,
        ...sharedProperties(),
      });
    });
  });

  describe.each`
    method                                 | trackingEvent
    ${'trackClickThroughSessionPill'}      | ${TRACKING_EVENT_CLICK_THROUGH_SESSION_PILL}
    ${'trackCancelSessionFromSessionPill'} | ${TRACKING_EVENT_CANCEL_SESSION_FROM_SESSION_PILL}
  `('$method', ({ method, trackingEvent }) => {
    it('tracks with workflow id and context', () => {
      EventsTracker.updateContext({ sessionId, flowType, model });
      EventsTracker[method]({ workflowId: 326 });

      expect(trackEventSpy).toHaveBeenCalledWith(trackingEvent, {
        workflow_id: 326,
        ...sharedProperties(),
      });
    });
  });

  describe.each`
    method                   | trackingEvent
    ${'trackPanelResized'}   | ${TRACKING_EVENT_RESIZE_PANEL}
    ${'trackPanelMaximized'} | ${TRACKING_EVENT_MAXIMIZE_PANEL}
    ${'trackPanelMinimized'} | ${TRACKING_EVENT_MINIMIZE_PANEL}
  `('$method', ({ method, trackingEvent }) => {
    it('tracks with panel width and context', () => {
      EventsTracker.updateContext({ sessionId, flowType, model });
      EventsTracker[method]({ value: 720 });

      expect(trackEventSpy).toHaveBeenCalledWith(trackingEvent, {
        value: 720,
        ...sharedProperties(),
      });
    });
  });

  describe.each`
    method                   | trackingEvent
    ${'trackRetryMessage'}   | ${TRACKING_EVENT_USER_CLICKED_RETRY}
    ${'trackRetrySucceeded'} | ${TRACKING_EVENT_RETRY_SUCCEEDED}
    ${'trackRetryFailed'}    | ${TRACKING_EVENT_RETRY_FAILED}
  `('$method', ({ method, trackingEvent }) => {
    it('tracks with attempt number and context', () => {
      EventsTracker.updateContext({ sessionId, flowType, model });
      EventsTracker[method]({ attemptNumber: 2 });

      expect(trackEventSpy).toHaveBeenCalledWith(trackingEvent, {
        value: 2,
        ...sharedProperties(),
      });
    });
  });

  describe('trackNavigateRetryAlternative', () => {
    it('tracks with alternative index and context', () => {
      EventsTracker.updateContext({ sessionId, flowType, model });
      EventsTracker.trackNavigateRetryAlternative({ index: 1 });

      expect(trackEventSpy).toHaveBeenCalledWith(TRACKING_EVENT_NAVIGATE_RETRY_ALTERNATIVE, {
        value: 1,
        ...sharedProperties(),
      });
    });
  });

  // The tracking helper validates event names against the definitions in
  // config/events, so the generic-API tests reuse real chat events.
  describe('track', () => {
    it('merges the session context into the properties', () => {
      EventsTracker.updateContext({ sessionId, flowType, model });
      EventsTracker.track(TRACKING_EVENT_APPROVE_TOOL, { tool_name: toolName });

      expect(trackEventSpy).toHaveBeenCalledWith(TRACKING_EVENT_APPROVE_TOOL, {
        tool_name: toolName,
        ...sharedProperties(),
      });
    });

    it('lets explicit properties win over the context', () => {
      EventsTracker.updateContext({ sessionId, flowType, model });
      EventsTracker.track(TRACKING_EVENT_APPROVE_TOOL, { trigger_source: 'web_ui' });

      expect(trackEventSpy).toHaveBeenCalledWith(TRACKING_EVENT_APPROVE_TOOL, {
        ...sharedProperties(),
        trigger_source: 'web_ui',
      });
    });
  });

  describe('trackOnce', () => {
    it('tracks once per dedup key', () => {
      EventsTracker.trackOnce(TRACKING_EVENT_RECOMMEND_TOOL, 'key-1');
      EventsTracker.trackOnce(TRACKING_EVENT_RECOMMEND_TOOL, 'key-1');
      EventsTracker.trackOnce(TRACKING_EVENT_RECOMMEND_TOOL, 'key-2');

      expect(trackEventSpy).toHaveBeenCalledTimes(2);
    });

    it('does not track without a dedup key', () => {
      EventsTracker.trackOnce(TRACKING_EVENT_RECOMMEND_TOOL, undefined);

      expect(trackEventSpy).not.toHaveBeenCalled();
    });

    it('tracks a previously seen key again after a reset', () => {
      EventsTracker.trackOnce(TRACKING_EVENT_RECOMMEND_TOOL, 'key-1');
      EventsTracker.reset();
      EventsTracker.trackOnce(TRACKING_EVENT_RECOMMEND_TOOL, 'key-1');

      expect(trackEventSpy).toHaveBeenCalledTimes(2);
    });
  });

  describe('observeClicks', () => {
    let root;
    let stopObserving;

    const click = (selector) => {
      root.querySelector(selector).click();
      jest.runOnlyPendingTimers();
    };

    beforeEach(() => {
      EventsTracker.updateContext({ sessionId, flowType, model });
      root = document.createElement('div');
      root.innerHTML = `
        <button data-track-id="send-prompt" data-testid="send-button"><span>Send</span></button>
        <a href="#" data-testid="docs-link">Docs</a>
        <button class="untagged">Plain</button>
        <textarea></textarea>
        <p>Text</p>
      `;
      document.body.appendChild(root);
      stopObserving = EventsTracker.observeClicks(root);
    });

    afterEach(() => {
      stopObserving();
      root.remove();
    });

    it.each`
      selector             | property
      ${'[data-track-id]'} | ${'send-prompt'}
      ${'span'}            | ${'send-prompt'}
      ${'a'}               | ${'a'}
      ${'.untagged'}       | ${'button'}
    `('tracks a click on $selector as $property', ({ selector, property }) => {
      click(selector);

      expect(trackEventSpy).toHaveBeenCalledWith(TRACKING_EVENT_CLICK_ELEMENT, {
        property,
        ...sharedProperties(),
      });
    });

    it.each(['textarea', 'p'])('does not track a click on %s', (selector) => {
      click(selector);

      expect(trackEventSpy).not.toHaveBeenCalled();
    });

    it('does not track a click that already tracked a named event', () => {
      root
        .querySelector('a')
        .addEventListener('click', () => EventsTracker.trackApproveTool({ toolName }));
      click('a');

      expect(trackEventSpy).toHaveBeenCalledTimes(1);
      expect(trackEventSpy).not.toHaveBeenCalledWith(
        TRACKING_EVENT_CLICK_ELEMENT,
        expect.anything(),
      );
    });

    it('tracks a click when a stream event is tracked before the click is decided', () => {
      root.querySelector('a').click();
      EventsTracker.trackToolSucceeded({ messageId: 'message-1', toolName });
      jest.runOnlyPendingTimers();

      expect(trackEventSpy).toHaveBeenCalledWith(TRACKING_EVENT_CLICK_ELEMENT, expect.anything());
    });

    it('tracks a click when a named event is tracked after an await', async () => {
      root.querySelector('a').addEventListener('click', async () => {
        await Promise.resolve();
        EventsTracker.trackApproveTool({ toolName });
      });
      root.querySelector('a').click();
      await Promise.resolve();
      jest.runOnlyPendingTimers();

      expect(trackEventSpy).toHaveBeenCalledWith(TRACKING_EVENT_CLICK_ELEMENT, expect.anything());
    });

    it('tracks a click whose handler stops propagation', () => {
      root.querySelector('a').addEventListener('click', (event) => event.stopPropagation());
      click('a');

      expect(trackEventSpy).toHaveBeenCalledWith(TRACKING_EVENT_CLICK_ELEMENT, expect.anything());
    });

    it('stops tracking once observation stops', () => {
      stopObserving();
      click('a');

      expect(trackEventSpy).not.toHaveBeenCalled();
    });
  });
});
