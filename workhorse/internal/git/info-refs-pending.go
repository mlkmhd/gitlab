package git

import (
	"fmt"
	"io"
	"strings"
)

const (
	objectFormatSHA1   = "sha1"
	objectFormatSHA256 = "sha256"
)

// receivePackCapabilities is what Gitaly advertises for an empty repository,
// except that object-format lists both formats so the client picks its own.
const receivePackCapabilities = "report-status report-status-v2 delete-refs side-band-64k quiet atomic ofs-delta push-options " +
	"object-format=" + objectFormatSHA1 + " object-format=" + objectFormatSHA256

// writePendingReceivePackAdvertisement answers info/refs for git-receive-pack
// on a repository that is created on the following POST. It mimics an empty
// repository, since there are no refs to advertise.
func writePendingReceivePackAdvertisement(w io.Writer) error {
	header := "# service=git-receive-pack\n"
	ref := fmt.Sprintf("%s capabilities^{}\x00%s\n", strings.Repeat("0", 40), receivePackCapabilities)

	for _, pkt := range []string{pktLine(header), "0000", pktLine(ref), "0000"} {
		if _, err := io.WriteString(w, pkt); err != nil {
			return err
		}
	}

	return nil
}

func pktLine(payload string) string {
	return fmt.Sprintf("%04x%s", len(payload)+4, payload)
}
