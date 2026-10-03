package bridge

import (
	"errors"
	"fmt"

	"tailscale.com/types/key"
)

// A client key is the tailcat client's node identity: the host's tailcat
// server can allowlist its public half (`--allow` / the plugin's allow.list).
// Without one the client generates an ephemeral key per session, which an
// allowlisting server always rejects. Keys cross the gomobile boundary as the
// key package's own text forms ("privkey:<hex>" / "nodekey:<hex>"), the same
// forms `tailcat genkey --client` and `tailcat printpub` use.

// GenerateClientKey returns a fresh client node key in its "privkey:" text form.
func GenerateClientKey() (string, error) {
	text, err := key.NewNode().MarshalText()
	if err != nil {
		return "", err
	}
	return string(text), nil
}

// ClientPublicKey returns the "nodekey:" public key for a "privkey:" client
// key — the line to add to a server's allow list.
func ClientPublicKey(clientKey string) (string, error) {
	k, err := parseClientKey(clientKey)
	if err != nil {
		return "", err
	}
	return k.Public().String(), nil
}

// parseClientKey decodes a "privkey:" client key. A zero key is rejected:
// tailcat would treat it as "no key" and silently go ephemeral, and
// NodePrivate.Public panics on it.
func parseClientKey(clientKey string) (key.NodePrivate, error) {
	var k key.NodePrivate
	if err := k.UnmarshalText([]byte(clientKey)); err != nil {
		return key.NodePrivate{}, fmt.Errorf("invalid tailcat client key: %w", err)
	}
	if k.IsZero() {
		return key.NodePrivate{}, errors.New("invalid tailcat client key: key is zero")
	}
	return k, nil
}
