package git

import (
	"bytes"
	"io"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

const (
	sha1Zero   = "0000000000000000000000000000000000000000"
	sha1Oid    = "570e7b2abdd848b95f2f578043fc23bd6f6fd24d"
	sha256Zero = "0000000000000000000000000000000000000000000000000000000000000000"
	sha256Oid  = "b6a1c0f2d1a0a3c3b86f1d9f0d2d4c7d2e0a6f3b9a5e1c4d7f8a9b0c1d2e3f40"
	packData   = "PACK\x00\x00\x00\x02\x00\x00\x00\x00"
)

func command(oldOid, newOid, capabilities string) string {
	line := oldOid + " " + newOid + " refs/heads/main"
	if capabilities != "" {
		line += "\x00" + capabilities
	}

	return pktLine(line)
}

func TestReadObjectFormat(t *testing.T) {
	tests := []struct {
		name    string
		request string
		want    string
		wantErr string
	}{
		{
			name:    "sha1 without capabilities",
			request: command(sha1Zero, sha1Oid, "") + "0000" + packData,
			want:    objectFormatSHA1,
		},
		{
			name:    "sha1 with capabilities but no object-format",
			request: command(sha1Zero, sha1Oid, "report-status side-band-64k") + "0000" + packData,
			want:    objectFormatSHA1,
		},
		{
			name:    "sha1 explicit",
			request: command(sha1Zero, sha1Oid, "report-status object-format=sha1") + "0000" + packData,
			want:    objectFormatSHA1,
		},
		{
			name:    "sha256",
			request: command(sha256Zero, sha256Oid, "report-status object-format=sha256 agent=git/2.50") + "0000" + packData,
			want:    objectFormatSHA256,
		},
		{
			name: "sha256 after shallow lines",
			request: pktLine("shallow "+sha256Oid+"\n") + pktLine("shallow "+sha256Oid+"\n") +
				command(sha256Zero, sha256Oid, "report-status object-format=sha256") + "0000" + packData,
			want: objectFormatSHA256,
		},
		{
			name:    "sha1 after shallow lines",
			request: pktLine("shallow "+sha1Oid+"\n") + command(sha1Zero, sha1Oid, "report-status") + "0000" + packData,
			want:    objectFormatSHA1,
		},
		{
			name:    "push certificate carries the capabilities",
			request: pktLine("push-cert\x00report-status object-format=sha256\n") + "0000" + packData,
			want:    objectFormatSHA256,
		},
		{
			name:    "flush only, a probe or nothing to push",
			request: "0000",
			want:    "",
		},
		{
			name:    "shallow lines then flush, nothing to push",
			request: pktLine("shallow "+sha256Oid+"\n") + "0000",
			want:    "",
		},
		{
			name:    "unsupported format",
			request: command(sha1Zero, sha1Oid, "object-format=sha512"),
			wantErr: `unsupported object format "sha512"`,
		},
		{
			name:    "non-hex length",
			request: "zzzz" + sha1Zero,
			wantErr: "invalid pkt-line length",
		},
		{
			name:    "length below the header size",
			request: "0003",
			wantErr: "invalid pkt-line length",
		},
		{
			name:    "delimiter packet",
			request: "0001",
			wantErr: "invalid pkt-line length",
		},
		{
			name:    "length above the maximum",
			request: "fff1",
			wantErr: "invalid pkt-line length",
		},
		{
			name:    "truncated payload",
			request: "0100" + sha1Zero,
			wantErr: "pkt-line payload",
		},
		{
			name:    "truncated length",
			request: "00",
			wantErr: "pkt-line length",
		},
		{
			name:    "empty body",
			request: "",
			wantErr: "pkt-line length",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			format, replay, err := readObjectFormat(strings.NewReader(tt.request))

			if tt.wantErr != "" {
				require.ErrorContains(t, err, tt.wantErr)
				return
			}

			require.NoError(t, err)
			require.Equal(t, tt.want, format)

			if tt.want == "" {
				require.Nil(t, replay, "there is no command to replay")
				return
			}

			got, err := io.ReadAll(replay)
			require.NoError(t, err)
			require.Equal(t, tt.request, string(got), "the request must be replayed unchanged")
		})
	}
}

func TestReadObjectFormat_PreambleLimit(t *testing.T) {
	shallow := pktLine("shallow " + sha1Oid + "\n")
	request := strings.Repeat(shallow, maxPreambleSize/len(shallow)+2) + command(sha1Zero, sha1Oid, "")

	body := strings.NewReader(request)

	_, _, err := readObjectFormat(body)

	require.ErrorContains(t, err, "no command within the first")
	require.Equal(t, int64(maxPreambleSize), body.Size()-int64(body.Len()), "must not read past the limit")
}

func TestReadObjectFormat_ReplaysLargeBody(t *testing.T) {
	rest := bytes.Repeat([]byte("x"), 4*maxPreambleSize)
	request := io.MultiReader(strings.NewReader(command(sha1Zero, sha1Oid, "")+"0000"), bytes.NewReader(rest))

	format, replay, err := readObjectFormat(request)
	require.NoError(t, err)
	require.Equal(t, objectFormatSHA1, format)

	got, err := io.ReadAll(replay)
	require.NoError(t, err)
	require.Len(t, got, len(command(sha1Zero, sha1Oid, ""))+len("0000")+len(rest))
}
