package git

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"time"

	grpccodes "google.golang.org/grpc/codes"
	grpcstatus "google.golang.org/grpc/status"

	"gitlab.com/gitlab-org/gitaly/v19/proto/go/gitalypb"

	"gitlab.com/gitlab-org/gitlab/workhorse/internal/api"
	"gitlab.com/gitlab-org/gitlab/workhorse/internal/gitaly"
	"gitlab.com/gitlab-org/gitlab/workhorse/internal/log"
)

const createAttempts = 5

// createRetryDelay is the first wait between CreateRepository attempts, doubled after each.
var createRetryDelay = 100 * time.Millisecond

// createTimeout bounds creating the repository, matching Rails' fast_timeout
// for the same RPC. It does not apply to the push that follows.
var createTimeout = 10 * time.Second

// Will not return a non-nil error after the response body has been
// written to.
// and `git push` doesn't provide `gitalypb.PackfileNegotiationStatistics`.
func handleReceivePack(w *HTTPResponseWriter, r *http.Request, a *api.Response) (*gitalypb.PackfileNegotiationStatistics, error) {
	action := getService(r)
	writePostRPCHeader(w, action)

	gitProtocol := r.Header.Get("Git-Protocol")

	// Extract correlation ID from X-Gitaly-Correlation-Id header and store in context
	ctx := r.Context()
	if correlationID := r.Header.Get(XGitalyCorrelationID); correlationID != "" {
		ctx = context.WithValue(ctx, gitaly.GitalyCorrelationIDKey, correlationID)
	}

	body := io.Reader(r.Body)
	if a.PendingRepositoryCreation {
		var err error
		if body, err = createPendingRepository(ctx, a, r.Body); err != nil {
			return nil, err
		}

		if body == nil {
			// git receive-pack answers a request without commands with an empty body
			return nil, nil
		}
	}

	cr, cw := newWriteAfterReader(body, newFlushWriter(w))
	defer func() {
		if err := cw.Flush(); err != nil {
			log.WithError(err).Error("Could not flush receive-pack response")
		}
	}()

	ctx, smarthttp, err := gitaly.NewSmartHTTPClient(ctx, a.GitalyServer)
	if err != nil {
		return nil, fmt.Errorf("smarthttp.ReceivePack: %v", err)
	}

	if err := smarthttp.ReceivePack(ctx, &a.Repository, a.GL_ID, a.GL_USERNAME, a.GL_REPOSITORY, a.GitConfigOptions, a.GlScopedUserID, a.GLBuildID, cr, cw, gitProtocol); err != nil {
		return nil, fmt.Errorf("smarthttp.ReceivePack: %w", err)
	}

	return nil, nil
}

// createPendingRepository creates the repository of a pending push-to-create
// with the object format the client pushes. It returns the request body to
// pass on to Gitaly, or nil when the request has no command to push.
func createPendingRepository(ctx context.Context, a *api.Response, body io.Reader) (io.Reader, error) {
	format, replay, err := readObjectFormat(body)
	if err != nil {
		return nil, fmt.Errorf("createPendingRepository: reading object format: %w", err)
	}

	if format == "" {
		return nil, nil
	}

	ctx, cancel := context.WithTimeout(ctx, createTimeout)
	defer cancel()

	ctx, repositoryClient, err := gitaly.NewRepositoryClient(ctx, a.GitalyServer)
	if err != nil {
		return nil, fmt.Errorf("createPendingRepository: connecting to Gitaly: %w", err)
	}

	request := &gitalypb.CreateRepositoryRequest{
		Repository:    &a.Repository,
		DefaultBranch: []byte(a.PendingRepositoryDefaultBranch),
		ObjectFormat:  gitalyObjectFormat(format),
	}

	if err := createRepository(ctx, repositoryClient, request); err != nil {
		return nil, fmt.Errorf("createPendingRepository: creating repository: %w", err)
	}

	return replay, nil
}

// createRepository tolerates a concurrent first push creating the repository.
// Gitaly answers AlreadyExists once the winner is done, but Internal ("file
// already locked") while it still holds the creation lock. That Internal can't
// be told apart from a real failure, so it retries every Internal briefly.
func createRepository(ctx context.Context, client *gitaly.RepositoryClient, request *gitalypb.CreateRepositoryRequest) error {
	delay := createRetryDelay

	for attempt := 1; ; attempt++ {
		_, err := client.CreateRepository(ctx, request)

		switch grpcstatus.Code(err) {
		case grpccodes.OK, grpccodes.AlreadyExists:
			return nil
		case grpccodes.Internal:
		default:
			return err
		}

		if exists, existsErr := client.RepositoryExists(ctx, &gitalypb.RepositoryExistsRequest{Repository: request.Repository}); existsErr == nil && exists.GetExists() {
			return nil
		}

		if attempt == createAttempts {
			return err
		}

		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(delay):
			delay *= 2
		}
	}
}

func gitalyObjectFormat(format string) gitalypb.ObjectFormat {
	if format == objectFormatSHA256 {
		return gitalypb.ObjectFormat_OBJECT_FORMAT_SHA256
	}

	return gitalypb.ObjectFormat_OBJECT_FORMAT_SHA1
}
