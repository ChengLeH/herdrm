// Package tailcatmobile is the gomobile-bound face of the tailcat bridge.
// gomobile compiles it into Tailcat.xcframework and generates the Swift API,
// so every exported symbol must use bindable types only: string and error.
// The work all lives in the sibling bridge package; these are thin wrappers
// keyed by the local listen path, letting the app host one bridge per device.
package tailcatmobile

import (
	"github.com/missuo/herdrm/tailcat/bridge"
)

// StartBridge holds one tailcat session for token and serves the herdr API
// socket on listenPath (plus the derived "-client" socket for attach). It
// returns once the listeners are bound; the bridge runs until StopBridge.
// Calling it again for the same listenPath is a no-op. clientKey is the
// "privkey:" client identity the host can allowlist, or "" for an ephemeral
// key. The token and key pass as plain arguments here — unlike a CLI they
// never enter a process list.
func StartBridge(token, clientKey, listenPath string) error {
	_, err := bridge.Start(token, clientKey, listenPath)
	return err
}

// StopBridge tears down the bridge serving listenPath, if any.
func StopBridge(listenPath string) {
	bridge.Stop(listenPath)
}

// GenerateClientKey returns a fresh "privkey:" client key for StartBridge.
func GenerateClientKey() (string, error) {
	return bridge.GenerateClientKey()
}

// ClientPublicKey returns the "nodekey:" public key of a "privkey:" client
// key — the line the host adds to its allow list.
func ClientPublicKey(clientKey string) (string, error) {
	return bridge.ClientPublicKey(clientKey)
}

// BridgeError reports the most recent asynchronous error (failed warm-up,
// refused tunnel dial) for the bridge on listenPath, or "".
func BridgeError(listenPath string) string {
	return bridge.LastError(listenPath)
}
