package bridge

import (
	"bufio"
	"errors"
	"net"
	"os"
	"strings"
	"testing"
	"time"
)

// TestE2EAllowListAdmitsOnlyTheClientKey runs the bridge against a live
// tailcat server that allowlists one client key and forwards port 6464 to a
// herdr API socket:
//
//	tailcat serve --allow=<nodekey of HERDRM_E2E_TAILCAT_ALLOWED_KEY> 6464
//
// The allowed key must get a herdr ping reply through the bridge; a fresh key
// must not. Needs HERDRM_E2E_TAILCAT_ALLOW_TOKEN (that server's address) and
// HERDRM_E2E_TAILCAT_ALLOWED_KEY (the "privkey:" it allowlists).
func TestE2EAllowListAdmitsOnlyTheClientKey(t *testing.T) {
	token := os.Getenv("HERDRM_E2E_TAILCAT_ALLOW_TOKEN")
	allowed := os.Getenv("HERDRM_E2E_TAILCAT_ALLOWED_KEY")
	if token == "" || allowed == "" {
		t.Skip("set HERDRM_E2E_TAILCAT_ALLOW_TOKEN and HERDRM_E2E_TAILCAT_ALLOWED_KEY to run the live allow-list E2E")
	}

	t.Run("allowed key", func(t *testing.T) {
		if reply, err := pingThroughBridge(t, token, allowed); err != nil {
			t.Fatalf("allowlisted key got no ping reply: %v (last bridge error: %q)", err, reply)
		}
	})
	t.Run("other key", func(t *testing.T) {
		other, err := GenerateClientKey()
		if err != nil {
			t.Fatal(err)
		}
		if reply, err := pingThroughBridge(t, token, other); err == nil {
			t.Fatalf("a key missing from the allow list got a reply: %q", reply)
		}
	})
}

// pingThroughBridge starts a bridge with clientKey, sends one herdr ping over
// its local API socket, and returns the reply line (or, on failure, the
// bridge's last asynchronous error).
func pingThroughBridge(t *testing.T, token, clientKey string) (string, error) {
	t.Helper()
	path := socketPath(t)
	b, err := Start(token, clientKey, path)
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer Stop(path)

	conn, err := net.Dial("unix", path)
	if err != nil {
		t.Fatalf("dial bridge socket: %v", err)
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(20 * time.Second))
	if _, err := conn.Write([]byte(`{"id":"1","method":"ping","params":{}}` + "\n")); err != nil {
		return b.LastError(), err
	}
	line, err := bufio.NewReader(conn).ReadString('\n')
	if err != nil {
		return b.LastError(), err
	}
	if !strings.Contains(line, `"result"`) {
		return line, errUnexpectedReply
	}
	return line, nil
}

var errUnexpectedReply = errors.New("reply carries no result")
