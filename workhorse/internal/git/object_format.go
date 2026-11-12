package git

import (
	"bytes"
	"fmt"
	"io"
	"strconv"
	"strings"
)

const (
	maxPktLineSize = 65520
	// maxPreambleSize bounds what is buffered while looking for the first
	// command, since a shallow clone sends one shallow line per boundary commit.
	maxPreambleSize = 1 << 20
)

var shallowPrefix = []byte("shallow ")

// readObjectFormat finds the object format a git-receive-pack request uses by
// reading up to its first command. The client names the format in the
// capabilities of that line, after any shallow lines. The returned reader
// replays everything consumed, then the rest of body. A request without a
// command returns an empty format and no reader.
func readObjectFormat(body io.Reader) (string, io.Reader, error) {
	var consumed bytes.Buffer
	limited := &io.LimitedReader{R: body, N: maxPreambleSize}
	tee := io.TeeReader(limited, &consumed)

	for {
		payload, flush, err := readPktLine(tee)
		if err != nil {
			if limited.N == 0 {
				return "", nil, fmt.Errorf("no command within the first %d bytes of the receive-pack request", maxPreambleSize)
			}

			return "", nil, fmt.Errorf("reading receive-pack request: %w", err)
		}

		var format string
		switch {
		case flush:
			// A probe POST from git before a large push, or nothing to push.
			// Creating the repository now would fix its format to SHA-1.
			return "", nil, nil
		case bytes.HasPrefix(payload, shallowPrefix):
			continue
		default:
			if format, err = parseObjectFormat(payload); err != nil {
				return "", nil, err
			}
		}

		return format, io.MultiReader(bytes.NewReader(consumed.Bytes()), body), nil
	}
}

func readPktLine(r io.Reader) (payload []byte, flush bool, err error) {
	header := make([]byte, pktLinePrefixLen)
	if _, err = io.ReadFull(r, header); err != nil {
		return nil, false, fmt.Errorf("pkt-line length: %w", err)
	}

	size, err := strconv.ParseUint(string(header), 16, 16)
	if err != nil {
		return nil, false, fmt.Errorf("invalid pkt-line length %q", header)
	}

	switch {
	case size == 0:
		return nil, true, nil
	case size < pktLinePrefixLen || size > maxPktLineSize:
		return nil, false, fmt.Errorf("invalid pkt-line length %q", header)
	}

	payload = make([]byte, size-pktLinePrefixLen)
	if _, err = io.ReadFull(r, payload); err != nil {
		return nil, false, fmt.Errorf("pkt-line payload: %w", err)
	}

	return payload, false, nil
}

// parseObjectFormat reads the object-format capability of a command line of
// the form "<old-oid> <new-oid> <ref>\0<capabilities>". Clients omit it for SHA-1.
func parseObjectFormat(command []byte) (string, error) {
	_, capabilities, found := bytes.Cut(command, []byte{0})
	if !found {
		return objectFormatSHA1, nil
	}

	for _, capability := range strings.Fields(string(capabilities)) {
		format, ok := strings.CutPrefix(capability, "object-format=")
		if !ok {
			continue
		}

		if format != objectFormatSHA1 && format != objectFormatSHA256 {
			return "", fmt.Errorf("unsupported object format %q", format)
		}

		return format, nil
	}

	return objectFormatSHA1, nil
}
