package git

import (
	"bytes"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
	"google.golang.org/grpc"

	"gitlab.com/gitlab-org/gitaly/v19/proto/go/gitalypb"

	"gitlab.com/gitlab-org/gitlab/workhorse/internal/api"
)

func TestWritePendingReceivePackAdvertisement(t *testing.T) {
	var buf bytes.Buffer
	require.NoError(t, writePendingReceivePackAdvertisement(&buf))

	ref := "0000000000000000000000000000000000000000 capabilities^{}\x00" + receivePackCapabilities + "\n"
	want := "001f# service=git-receive-pack\n" + "0000" + pktLine(ref) + "0000"
	require.Equal(t, want, buf.String())

	// Pin the advertised order.
	require.Contains(t, receivePackCapabilities, "object-format=sha1 object-format=sha256")
}

func TestWritePendingReceivePackAdvertisement_WriteError(t *testing.T) {
	require.Error(t, writePendingReceivePackAdvertisement(failingWriter{}))
}

type failingWriter struct{}

func (failingWriter) Write([]byte) (int, error) { return 0, errors.New("write failed") }

func TestGetInfoRefsHandler_PendingRepositoryCreation(t *testing.T) {
	// A Gitaly that must not be called: the repository does not exist yet.
	addr := startGRPCServer(t, func(*grpc.Server) {})

	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodGet, "/?service=git-receive-pack", nil)
	a := &api.Response{
		PendingRepositoryCreation: true,
		GitalyServer:              api.GitalyServer{Address: addr},
	}

	handleGetInfoRefs(w, r, a)

	require.Equal(t, http.StatusOK, w.Code)
	require.Equal(t, "application/x-git-receive-pack-advertisement", w.Header().Get("Content-Type"))
	require.True(t, strings.HasPrefix(w.Body.String(), "001f# service=git-receive-pack\n0000"))
	require.Contains(t, w.Body.String(), "object-format=sha256")
}

func TestGetInfoRefsHandler_PendingRepositoryCreationUploadPack(t *testing.T) {
	called := false
	addr := startSmartHTTPServer(t, &smartHTTPServiceServerWithInfoRefs{
		InfoRefsUploadPackFunc: func(_ *gitalypb.InfoRefsRequest, _ gitalypb.SmartHTTPService_InfoRefsUploadPackServer) error {
			called = true
			return nil
		},
	})

	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodGet, "/?service=git-upload-pack", nil)
	a := &api.Response{
		PendingRepositoryCreation: true,
		GitalyServer:              api.GitalyServer{Address: addr},
	}

	handleGetInfoRefs(w, r, a)

	require.True(t, called, "upload-pack must still be served by Gitaly")
	require.NotContains(t, w.Body.String(), "object-format=sha256")
}
