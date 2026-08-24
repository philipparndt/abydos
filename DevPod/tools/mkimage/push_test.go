package main

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

// A registry that remembers what it was given, which is all this needs to
// answer the question the push has to get right: two architectures, one index.
type fakeRegistry struct {
	mutex     sync.Mutex
	blobs     map[string][]byte
	manifests map[string][]byte
	types     map[string]string
}

func (f *fakeRegistry) handler(t *testing.T) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.mutex.Lock()
		defer f.mutex.Unlock()

		switch {
		case r.URL.Path == "/v2/":
			w.WriteHeader(http.StatusOK)

		case strings.HasSuffix(r.URL.Path, "/blobs/uploads/"):
			w.Header().Set("Location", "/upload/1")
			w.WriteHeader(http.StatusAccepted)

		case r.URL.Path == "/upload/1":
			body, _ := io.ReadAll(r.Body)
			f.blobs[r.URL.Query().Get("digest")] = body
			w.WriteHeader(http.StatusCreated)

		case strings.Contains(r.URL.Path, "/blobs/") && r.Method == http.MethodHead:
			_, known := f.blobs[strings.TrimPrefix(r.URL.Path, "/v2/me/image/blobs/")]
			if !known {
				w.WriteHeader(http.StatusNotFound)
			}

		case strings.Contains(r.URL.Path, "/manifests/"):
			body, _ := io.ReadAll(r.Body)
			name := strings.TrimPrefix(r.URL.Path, "/v2/me/image/manifests/")
			f.manifests[name] = body
			f.types[name] = r.Header.Get("Content-Type")
			w.WriteHeader(http.StatusCreated)

		default:
			t.Errorf("unexpected request %s %s", r.Method, r.URL.Path)
			w.WriteHeader(http.StatusNotFound)
		}
	})
}

func TestPublishSendsOneManifestPerArchitectureAndAnIndex(t *testing.T) {
	fake := &fakeRegistry{
		blobs:     map[string][]byte{},
		manifests: map[string][]byte{},
		types:     map[string]string{},
	}
	server := httptest.NewServer(fake.handler(t))
	defer server.Close()

	root := t.TempDir()
	for _, arch := range []string{"amd64", "arm64"} {
		dir := filepath.Join(root, arch, "usr", "local", "bin")
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, "abydos-supervisor"), []byte("binary for "+arch), 0o755); err != nil {
			t.Fatal(err)
		}
	}

	host := strings.TrimPrefix(server.URL, "http://")
	err := publish(
		host+"/me/image:test",
		[]variant{{arch: "amd64", dir: filepath.Join(root, "amd64")}, {arch: "arm64", dir: filepath.Join(root, "arm64")}},
		"/usr/local/bin/abydos-supervisor",
		[]string{"ABYDOS_BINARY=/app/current"},
		[]string{"7999/tcp"},
	)
	if err != nil {
		t.Fatal(err)
	}

	// Four blobs: a layer and a config for each architecture, and no two the
	// same — an image that ships one architecture's binary under both names is
	// the failure this is here to catch.
	if len(fake.blobs) != 4 {
		t.Fatalf("want 4 blobs, got %d", len(fake.blobs))
	}

	var list index
	if err := json.Unmarshal(fake.manifests["test"], &list); err != nil {
		t.Fatal(err)
	}
	if list.MediaType != mediaIndex || len(list.Manifests) != 2 {
		t.Fatalf("want an index of 2, got %s of %d", list.MediaType, len(list.Manifests))
	}

	seen := map[string]bool{}
	for _, entry := range list.Manifests {
		if entry.Platform == nil || entry.Platform.OS != "linux" {
			t.Fatalf("manifest without a platform: %+v", entry)
		}
		seen[entry.Platform.Architecture] = true

		body, ok := fake.manifests[entry.Digest]
		if !ok {
			t.Fatalf("index names %s, which was never pushed", entry.Digest)
		}
		var single manifest
		if err := json.Unmarshal(body, &single); err != nil {
			t.Fatal(err)
		}
		if _, ok := fake.blobs[single.Config.Digest]; !ok {
			t.Fatal("manifest names a config that was never uploaded")
		}
		if _, ok := fake.blobs[single.Layers[0].Digest]; !ok {
			t.Fatal("manifest names a layer that was never uploaded")
		}
	}
	if !seen["amd64"] || !seen["arm64"] {
		t.Fatalf("want both architectures, got %v", seen)
	}
}

// The architecture in the config is what a cluster matches against; getting it
// from the flag rather than from the machine doing the push is the whole point
// of publishing this way.
func TestImageConfigCarriesItsArchitecture(t *testing.T) {
	config := imageConfig("amd64", "abc", "/bin/app", nil, nil)
	if config["architecture"] != "amd64" || config["os"] != "linux" {
		t.Fatalf("got %v/%v", config["architecture"], config["os"])
	}
}

func TestReferenceParsing(t *testing.T) {
	for reference, want := range map[string][3]string{
		"pharndt/abydos-devpod:v1":     {"https://registry-1.docker.io", "pharndt/abydos-devpod", "v1"},
		"pharndt/abydos-devpod":        {"https://registry-1.docker.io", "pharndt/abydos-devpod", "latest"},
		"ghcr.io/philipp/thing:1.2.3": {"https://ghcr.io", "philipp/thing", "1.2.3"},
		"localhost:5000/thing:dev":    {"http://localhost:5000", "thing", "dev"},
	} {
		target, err := newRegistry(reference)
		if err != nil {
			t.Fatal(err)
		}
		got := [3]string{target.base, target.name, target.tag}
		if got != want {
			t.Errorf("%s → %v, want %v", reference, got, want)
		}
	}
}
