package main

import (
	"compress/gzip"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"sync"
)

// decodeBody unwraps a pushed binary.
//
// Compression is the caller's choice because it is the caller who knows the
// link: a binary going to a cluster on the same machine is faster uncompressed,
// and one going over a VPN is not. A Go binary gzips to about half its size in
// a sixth of a second, which is worth it over anything slower than a LAN.
func decodeBody(r *http.Request) (io.ReadCloser, error) {
	switch r.Header.Get("Content-Encoding") {
	case "", "identity":
		return r.Body, nil
	case "gzip":
		reader, err := gzip.NewReader(r.Body)
		if err != nil {
			return nil, fmt.Errorf("the body is not gzip: %w", err)
		}
		return readCloser{reader, r.Body}, nil
	default:
		return nil, fmt.Errorf("unknown Content-Encoding %q", r.Header.Get("Content-Encoding"))
	}
}

type readCloser struct {
	io.Reader
	underlying io.Closer
}

func (r readCloser) Close() error { return r.underlying.Close() }

// writeAtomic replaces a file without anybody seeing it half written.
//
// Beside the target rather than in a temporary directory, so the rename stays
// on one filesystem — across two it is a copy, which is exactly the thing
// being avoided.
func writeAtomic(path string, source io.Reader) (int64, error) {
	directory := filepath.Dir(path)
	temporary, err := os.CreateTemp(directory, ".incoming-*")
	if err != nil {
		return 0, fmt.Errorf("cannot write in %s: %w", directory, err)
	}
	defer os.Remove(temporary.Name())

	written, err := io.Copy(temporary, source)
	if err != nil {
		temporary.Close()
		return written, fmt.Errorf("transfer failed after %d bytes: %w", written, err)
	}
	if err := temporary.Sync(); err != nil {
		temporary.Close()
		return written, err
	}
	if err := temporary.Close(); err != nil {
		return written, err
	}
	if err := os.Chmod(temporary.Name(), 0o755); err != nil {
		return written, err
	}
	if err := os.Rename(temporary.Name(), path); err != nil {
		return written, fmt.Errorf("cannot replace %s: %w", path, err)
	}
	return written, nil
}

func query(r *http.Request, name, fallback string) string {
	if value := r.URL.Query().Get(name); value != "" {
		return value
	}
	return fallback
}

func writeJSON(w http.ResponseWriter, value any) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(value); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}

// archName is what the pod runs, so the editor can say plainly when a binary
// was built for something else — an `exec format error` explains nothing.
func archName() string { return runtime.GOARCH }

// ring keeps the last lines of output for the editor to show without
// streaming.
type ring struct {
	mutex sync.Mutex
	lines []string
	limit int
}

func newRing(limit int) *ring { return &ring{limit: limit} }

func (r *ring) add(line string) {
	r.mutex.Lock()
	defer r.mutex.Unlock()
	r.lines = append(r.lines, line)
	if len(r.lines) > r.limit {
		r.lines = r.lines[len(r.lines)-r.limit:]
	}
}

// reset drops everything, for a new program.
func (r *ring) reset() {
	r.mutex.Lock()
	defer r.mutex.Unlock()
	r.lines = nil
}

func (r *ring) tail(count int) []string {
	r.mutex.Lock()
	defer r.mutex.Unlock()
	if count <= 0 || count > len(r.lines) {
		count = len(r.lines)
	}
	out := make([]string, count)
	copy(out, r.lines[len(r.lines)-count:])
	return out
}
