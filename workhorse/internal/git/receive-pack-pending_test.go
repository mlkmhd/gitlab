package git

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"gitlab.com/gitlab-org/gitaly/v19/proto/go/gitalypb"
)

type mockCreateRepositoryServer struct {
	gitalypb.UnimplementedRepositoryServiceServer
	createErr error
	// createErrs, when set, are returned in order, one per call; later calls succeed.
	createErrs []error
	exists     bool
	requests   []*gitalypb.CreateRepositoryRequest
	// withDeadline records whether each CreateRepository call carried a deadline.
	withDeadline []bool
}

func (s *mockCreateRepositoryServer) CreateRepository(ctx context.Context, req *gitalypb.CreateRepositoryRequest) (*gitalypb.CreateRepositoryResponse, error) {
	s.requests = append(s.requests, req)

	_, ok := ctx.Deadline()
	s.withDeadline = append(s.withDeadline, ok)

	if len(s.createErrs) > 0 {
		err := s.createErrs[0]
		s.createErrs = s.createErrs[1:]

		return &gitalypb.CreateRepositoryResponse{}, err
	}

	return &gitalypb.CreateRepositoryResponse{}, s.createErr
}

func (s *mockCreateRepositoryServer) RepositoryExists(context.Context, *gitalypb.RepositoryExistsRequest) (*gitalypb.RepositoryExistsResponse, error) {
	return &gitalypb.RepositoryExistsResponse{Exists: s.exists}, nil
}

// startPendingRepositoryServer serves receive-pack and repository creation, and
// returns the bytes Gitaly receives from receive-pack.
func startPendingRepositoryServer(t *testing.T, repositories *mockCreateRepositoryServer) (string, *mockReceivePackServer, *bytes.Buffer) {
	t.Helper()

	received := &bytes.Buffer{}
	receivePack := &mockReceivePackServer{
		receivePackFunc: func(stream gitalypb.SmartHTTPService_PostReceivePackServer) error {
			for {
				req, err := stream.Recv()
				if err == io.EOF {
					break
				}
				if err != nil {
					return err
				}
				received.Write(req.GetData())
			}

			return stream.Send(&gitalypb.PostReceivePackResponse{Data: []byte("ok")})
		},
	}

	addr := startGRPCServer(t, func(srv *grpc.Server) {
		gitalypb.RegisterSmartHTTPServiceServer(srv, receivePack)
		gitalypb.RegisterRepositoryServiceServer(srv, repositories)
	})

	return addr, receivePack, received
}

func TestHandleReceivePack_PendingRepositoryCreation(t *testing.T) {
	sha256Push := pktLine("shallow "+sha256Oid+"\n") +
		command(sha256Zero, sha256Oid, "report-status object-format=sha256") + "0000" + packData
	sha1Push := command(sha1Zero, sha1Oid, "report-status") + "0000" + packData

	tests := []struct {
		name          string
		request       string
		defaultBranch string
		wantFormat    gitalypb.ObjectFormat
		wantBranch    []byte
	}{
		{
			name:          "sha256 push after a shallow line",
			request:       sha256Push,
			defaultBranch: "trunk",
			wantFormat:    gitalypb.ObjectFormat_OBJECT_FORMAT_SHA256,
			wantBranch:    []byte("trunk"),
		},
		{
			name:       "sha1 push without a default branch",
			request:    sha1Push,
			wantFormat: gitalypb.ObjectFormat_OBJECT_FORMAT_SHA1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repositories := &mockCreateRepositoryServer{}
			addr, _, received := startPendingRepositoryServer(t, repositories)

			a := apiResponseFixture(addr)
			a.PendingRepositoryCreation = true
			a.PendingRepositoryDefaultBranch = tt.defaultBranch

			w := httptest.NewRecorder()
			r := httptest.NewRequest(http.MethodPost, "/test-repo.git/git-receive-pack", strings.NewReader(tt.request))

			_, err := handleReceivePack(NewHTTPResponseWriter(w), r, a)
			require.NoError(t, err)

			require.Len(t, repositories.requests, 1)
			require.Equal(t, []bool{true}, repositories.withDeadline, "creating must be bounded by a deadline")
			require.Equal(t, tt.wantFormat, repositories.requests[0].ObjectFormat)
			require.Equal(t, tt.wantBranch, repositories.requests[0].DefaultBranch)
			require.Equal(t, "default", repositories.requests[0].Repository.StorageName)
			require.Equal(t, "test-repo.git", repositories.requests[0].Repository.RelativePath)

			require.Equal(t, tt.request, received.String(), "Gitaly must receive the whole request")
			require.Equal(t, "ok", w.Body.String())
		})
	}
}

func TestHandleReceivePack_PendingRepositoryCreationAlreadyExists(t *testing.T) {
	repositories := &mockCreateRepositoryServer{createErr: status.Error(codes.AlreadyExists, "repository exists")}
	addr, _, received := startPendingRepositoryServer(t, repositories)

	a := apiResponseFixture(addr)
	a.PendingRepositoryCreation = true

	request := command(sha1Zero, sha1Oid, "report-status") + "0000" + packData
	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodPost, "/test-repo.git/git-receive-pack", strings.NewReader(request))

	_, err := handleReceivePack(NewHTTPResponseWriter(w), r, a)
	require.NoError(t, err)

	require.Len(t, repositories.requests, 1)
	require.Equal(t, request, received.String())
	require.Equal(t, "ok", w.Body.String())
}

func TestHandleReceivePack_PendingRepositoryCreationWithoutCommand(t *testing.T) {
	tests := []struct {
		name    string
		request string
	}{
		{name: "probe POST before a large push", request: "0000"},
		{name: "shallow lines and nothing to push", request: pktLine("shallow "+sha256Oid+"\n") + "0000"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repositories := &mockCreateRepositoryServer{}
			addr, receivePack, _ := startPendingRepositoryServer(t, repositories)

			a := apiResponseFixture(addr)
			a.PendingRepositoryCreation = true

			w := httptest.NewRecorder()
			r := httptest.NewRequest(http.MethodPost, "/test-repo.git/git-receive-pack", strings.NewReader(tt.request))

			_, err := handleReceivePack(NewHTTPResponseWriter(w), r, a)
			require.NoError(t, err)

			require.Empty(t, repositories.requests, "creating the repository now would fix its format to SHA-1")
			require.Nil(t, receivePack.captured, "there is nothing to receive")
			require.Equal(t, http.StatusOK, w.Code)
			require.Empty(t, w.Body.String())
		})
	}
}

func TestHandleReceivePack_PendingRepositoryCreationLockContention(t *testing.T) {
	locked := status.Error(codes.Internal, "creating repository: locking repository: file already locked")

	t.Run("the winner finishes and Gitaly answers AlreadyExists", func(t *testing.T) {
		repositories := &mockCreateRepositoryServer{
			createErrs: []error{locked, locked, status.Error(codes.AlreadyExists, "repository exists")},
		}

		received, err := pushToPendingRepository(t, repositories)
		require.NoError(t, err)

		require.Len(t, repositories.requests, 3)
		require.NotEmpty(t, received)
	})

	t.Run("the repository exists by the time the lock error returns", func(t *testing.T) {
		repositories := &mockCreateRepositoryServer{createErrs: []error{locked}, exists: true}

		received, err := pushToPendingRepository(t, repositories)
		require.NoError(t, err)

		require.Len(t, repositories.requests, 1)
		require.NotEmpty(t, received)
	})

	t.Run("the lock is never released", func(t *testing.T) {
		repositories := &mockCreateRepositoryServer{createErr: locked}

		_, err := pushToPendingRepository(t, repositories)
		require.ErrorContains(t, err, "file already locked")

		require.Len(t, repositories.requests, createAttempts)
	})

	t.Run("other Gitaly errors are not retried", func(t *testing.T) {
		repositories := &mockCreateRepositoryServer{createErr: status.Error(codes.Unavailable, "gitaly down")}

		_, err := pushToPendingRepository(t, repositories)
		require.ErrorContains(t, err, "gitaly down")

		require.Len(t, repositories.requests, 1)
	})
}

// pushToPendingRepository pushes a SHA-1 first push with no wait between create
// attempts, and returns what Gitaly received.
func pushToPendingRepository(t *testing.T, repositories *mockCreateRepositoryServer) (string, error) {
	t.Helper()

	previous := createRetryDelay
	createRetryDelay = 0
	t.Cleanup(func() { createRetryDelay = previous })

	addr, _, received := startPendingRepositoryServer(t, repositories)

	a := apiResponseFixture(addr)
	a.PendingRepositoryCreation = true

	request := command(sha1Zero, sha1Oid, "report-status") + "0000" + packData
	r := httptest.NewRequest(http.MethodPost, "/test-repo.git/git-receive-pack", strings.NewReader(request))

	_, err := handleReceivePack(NewHTTPResponseWriter(httptest.NewRecorder()), r, a)

	return received.String(), err
}

func TestHandleReceivePack_PendingRepositoryCreationFailure(t *testing.T) {
	tests := []struct {
		name      string
		request   string
		createErr error
		wantErr   string
		wantCalls int
	}{
		{
			name:      "Gitaly fails to create the repository",
			request:   command(sha1Zero, sha1Oid, "") + "0000" + packData,
			createErr: status.Error(codes.Unavailable, "gitaly down"),
			wantErr:   "createPendingRepository: creating repository:",
			wantCalls: 1,
		},
		{
			name:    "malformed request",
			request: "zzzz",
			wantErr: "createPendingRepository: reading object format: reading receive-pack request: invalid pkt-line length",
		},
		{
			name:    "unsupported object format",
			request: command(sha1Zero, sha1Oid, "object-format=sha512"),
			wantErr: "createPendingRepository: reading object format: unsupported object format",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repositories := &mockCreateRepositoryServer{createErr: tt.createErr}
			addr, receivePack, _ := startPendingRepositoryServer(t, repositories)

			a := apiResponseFixture(addr)
			a.PendingRepositoryCreation = true

			w := httptest.NewRecorder()
			r := httptest.NewRequest(http.MethodPost, "/test-repo.git/git-receive-pack", strings.NewReader(tt.request))

			_, err := handleReceivePack(NewHTTPResponseWriter(w), r, a)

			require.ErrorContains(t, err, tt.wantErr)
			require.Len(t, repositories.requests, tt.wantCalls)
			require.Nil(t, receivePack.captured, "receive-pack must not run without a repository")
		})
	}
}

func TestHandleReceivePack_NotPendingDoesNotCreateRepository(t *testing.T) {
	repositories := &mockCreateRepositoryServer{}
	addr, _, received := startPendingRepositoryServer(t, repositories)

	// Not a pkt-line stream: it must reach Gitaly untouched.
	const request = "opaque request body"
	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodPost, "/test-repo.git/git-receive-pack", strings.NewReader(request))

	_, err := handleReceivePack(NewHTTPResponseWriter(w), r, apiResponseFixture(addr))
	require.NoError(t, err)

	require.Empty(t, repositories.requests)
	require.Equal(t, request, received.String())
}
