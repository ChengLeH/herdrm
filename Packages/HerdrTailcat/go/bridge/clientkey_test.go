package bridge

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"tailscale.com/types/key"
)

// socketPath returns a socket path short enough for sockaddr_un (104 bytes on
// Darwin); t.TempDir embeds the test name and can exceed it.
func socketPath(t *testing.T) string {
	t.Helper()
	dir, err := os.MkdirTemp("", "hb")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	return filepath.Join(dir, "b.sock")
}

func TestGenerateClientKeyIsAFreshPrivkey(t *testing.T) {
	a, err := GenerateClientKey()
	if err != nil {
		t.Fatalf("GenerateClientKey: %v", err)
	}
	if !strings.HasPrefix(a, "privkey:") || len(a) != len("privkey:")+64 {
		t.Fatalf("GenerateClientKey = %q, want privkey: + 64 hex chars", a)
	}
	var k key.NodePrivate
	if err := k.UnmarshalText([]byte(a)); err != nil || k.IsZero() {
		t.Fatalf("generated key does not parse as a non-zero NodePrivate: %v", err)
	}
	b, err := GenerateClientKey()
	if err != nil {
		t.Fatalf("GenerateClientKey: %v", err)
	}
	if a == b {
		t.Fatal("two GenerateClientKey calls returned the same key")
	}
}

func TestClientPublicKeyMatchesTheKeyPackage(t *testing.T) {
	priv := key.NewNode()
	text, err := priv.MarshalText()
	if err != nil {
		t.Fatal(err)
	}
	got, err := ClientPublicKey(string(text))
	if err != nil {
		t.Fatalf("ClientPublicKey: %v", err)
	}
	if want := priv.Public().String(); got != want {
		t.Fatalf("ClientPublicKey = %q, want %q (the form allow.list and --allow take)", got, want)
	}
}

func TestClientPublicKeyRejectsInvalidKeys(t *testing.T) {
	pub := key.NewNode().Public().String()
	for name, in := range map[string]string{
		"empty":       "",
		"garbage":     "not-a-key",
		"public key":  pub,
		"zero key":    "privkey:" + strings.Repeat("0", 64),
		"short":       "privkey:abcd",
		"invalid hex": "privkey:" + strings.Repeat("z", 64),
	} {
		t.Run(name, func(t *testing.T) {
			got, err := ClientPublicKey(in)
			if err == nil {
				t.Fatalf("ClientPublicKey(%q) = %q, want an error", in, got)
			}
		})
	}
}

func TestStartUsesTheGivenClientKey(t *testing.T) {
	priv := key.NewNode()
	text, _ := priv.MarshalText()
	path := socketPath(t)
	b, err := Start("tcbogus", string(text), path)
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer Stop(path)
	if !b.client.Key.Equal(priv) {
		t.Fatal("bridge client does not use the given client key")
	}
}

func TestStartWithoutAClientKeyStaysEphemeral(t *testing.T) {
	path := socketPath(t)
	b, err := Start("tcbogus", "", path)
	if err != nil {
		t.Fatalf("Start: %v", err)
	}
	defer Stop(path)
	if !b.client.Key.IsZero() {
		t.Fatal("an empty client key must leave Client.Key unset (ephemeral)")
	}
}

func TestStartRejectsAnInvalidClientKey(t *testing.T) {
	for name, in := range map[string]string{
		"garbage":  "not-a-key",
		"zero key": "privkey:" + strings.Repeat("0", 64),
	} {
		t.Run(name, func(t *testing.T) {
			path := socketPath(t)
			b, err := Start("tcbogus", in, path)
			if err == nil {
				Stop(path)
				t.Fatalf("Start accepted client key %q", in)
			}
			if b != nil {
				t.Fatal("Start returned a bridge alongside an error")
			}
			if _, ok := registry.Load(path); ok {
				t.Fatal("a rejected Start left a bridge in the registry")
			}
			if _, err := os.Stat(path); !os.IsNotExist(err) {
				t.Fatal("a rejected Start left a socket file behind")
			}
		})
	}
}
