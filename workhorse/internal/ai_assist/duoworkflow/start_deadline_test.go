package duoworkflow

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"github.com/stretchr/testify/require"

	pb "gitlab.com/gitlab-org/modelops/applied-ml/code-suggestions/ai-assist/clients/gopb/contract"

	"gitlab.com/gitlab-org/gitlab/workhorse/internal/testhelper"
)

const startDeadlineCloseError = "websocket: close 1001 (going away): start deadline exceeded"

// dialWithStartDeadline connects a WebSocket client to a handler whose start
// deadline is shortened to deadline.
func dialWithStartDeadline(t *testing.T, grpcServer *testServer, deadline time.Duration) *websocket.Conn {
	t.Helper()

	testhelper.ConfigureSecret()

	apiServer, apiClient := setupAPIServer(t, `{
		"DuoWorkflow": {
			"Service": {
				"URI": "`+grpcServer.Addr+`",
				"Headers": {"Authorization": "Bearer test"},
				"Secure": false
			}
		}
	}`)
	t.Cleanup(apiServer.Close)

	handler := NewHandler(apiClient, initRdb(t), http.HandlerFunc(func(_ http.ResponseWriter, _ *http.Request) {}), "")
	handler.startDeadline = deadline

	httpServer := httptest.NewServer(handler.Build())
	t.Cleanup(httpServer.Close)

	wsConn, resp, err := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(httpServer.URL, "http")+"/duo", nil)
	if resp != nil {
		_ = resp.Body.Close()
	}
	require.NoError(t, err)
	t.Cleanup(func() { _ = wsConn.Close() })

	return wsConn
}

// drainUntilClosed stands in for a Duo Workflow Service that never answers:
// it reads client events until workhorse ends the stream.
func drainUntilClosed(stream pb.DuoWorkflow_ExecuteWorkflowServer) error {
	for {
		if _, err := stream.Recv(); err != nil {
			return nil
		}
	}
}

func TestHandler_StartDeadline_ClosesConnectionWithoutStartRequest(t *testing.T) {
	grpcServer := setupTestServer(t)
	grpcServer.execWorkflowHandler = drainUntilClosed

	wsConn := dialWithStartDeadline(t, grpcServer, 50*time.Millisecond)

	_, _, err := wsConn.ReadMessage()
	require.EqualError(t, err, startDeadlineCloseError)
}

func TestHandler_StartDeadline_HeartbeatDoesNotCountAsStart(t *testing.T) {
	grpcServer := setupTestServer(t)
	grpcServer.execWorkflowHandler = drainUntilClosed

	wsConn := dialWithStartDeadline(t, grpcServer, 100*time.Millisecond)

	require.NoError(t, wsConn.WriteMessage(websocket.BinaryMessage, []byte(`{"heartbeat": {"timestamp": 1}}`)))

	_, _, err := wsConn.ReadMessage()
	require.EqualError(t, err, startDeadlineCloseError)
}

func TestHandler_StartDeadline_StartRequestKeepsConnectionOpen(t *testing.T) {
	const deadline = 50 * time.Millisecond

	grpcServer := setupTestServer(t)
	grpcServer.execWorkflowHandler = func(stream pb.DuoWorkflow_ExecuteWorkflowServer) error {
		if _, err := stream.Recv(); err != nil {
			return err
		}

		// Answer only once the deadline is long past.
		time.Sleep(4 * deadline)

		return stream.Send(&pb.Action{
			Action: &pb.Action_RunCommand{RunCommand: &pb.RunCommandAction{Program: "ls"}},
		})
	}

	wsConn := dialWithStartDeadline(t, grpcServer, deadline)

	require.NoError(t, wsConn.WriteMessage(websocket.BinaryMessage, []byte(`{"startRequest": {"workflowID": "id-123", "goal": "create workflow"}}`)))

	_, response, err := wsConn.ReadMessage()
	require.NoError(t, err)
	require.Contains(t, string(response), `"runCommand"`)
}

func TestRunner_WatchStartDeadline(t *testing.T) {
	t.Run("ends the run and records the teardown reason when no start request arrived", func(t *testing.T) {
		r, _ := newValidationRunner(t, false)
		r.startDeadline = 10 * time.Millisecond
		errCh := make(chan error, 1)

		go r.watchStartDeadline(context.Background(), errCh)

		select {
		case err := <-errCh:
			require.ErrorIs(t, err, errStartDeadline)
		case <-time.After(5 * time.Second):
			t.Fatal("timed out waiting for the start deadline")
		}
		require.Equal(t, teardownStartDeadline, r.teardown.load())
	})

	t.Run("does nothing once the start request arrived", func(t *testing.T) {
		r, _ := newValidationRunner(t, false)
		r.startDeadline = 10 * time.Millisecond
		errCh := make(chan error, 1)

		require.NoError(t, r.handleClientEvent(testStartRequestEvent()))

		r.watchStartDeadline(context.Background(), errCh)

		require.Empty(t, errCh)
		require.Equal(t, teardownUnsolicited, r.teardown.load())
	})

	t.Run("stops waiting when the run ends first", func(t *testing.T) {
		r, _ := newValidationRunner(t, false)
		r.startDeadline = time.Hour
		errCh := make(chan error, 1)

		ctx, cancel := context.WithCancel(context.Background())
		cancel()

		r.watchStartDeadline(ctx, errCh)

		require.Empty(t, errCh)
		require.Equal(t, teardownUnsolicited, r.teardown.load())
	})
}

func TestTeardownReason_StartDeadline(t *testing.T) {
	require.Equal(t, "start_deadline", teardownStartDeadline.String())
}
