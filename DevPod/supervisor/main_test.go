package main

import (
	"bytes"
	"compress/gzip"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// A program that says something and stays up until it is stopped.
func buildFixture(t *testing.T, source string) string {
	t.Helper()
	directory := t.TempDir()
	if err := os.WriteFile(filepath.Join(directory, "main.go"), []byte(source), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(directory, "go.mod"), []byte("module fixture\n\ngo 1.22\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	binary := filepath.Join(directory, "fixture")
	build(t, directory, binary)
	return binary
}

func newSupervisor(t *testing.T) (*Supervisor, string) {
	t.Helper()
	directory := t.TempDir()
	path := filepath.Join(directory, "current")
	return &Supervisor{
		options: Options{BinaryPath: path, WorkDir: directory, DebugAddr: ":0"},
		logs:    newRing(100),
	}, path
}

func post(t *testing.T, supervisor *Supervisor, target string, body []byte, encoding string) *httptest.ResponseRecorder {
	t.Helper()
	request := httptest.NewRequest(http.MethodPost, target, bytes.NewReader(body))
	if encoding != "" {
		request.Header.Set("Content-Encoding", encoding)
	}
	recorder := httptest.NewRecorder()
	supervisor.routes().ServeHTTP(recorder, request)
	return recorder
}

func status(t *testing.T, supervisor *Supervisor) Status {
	t.Helper()
	recorder := httptest.NewRecorder()
	supervisor.routes().ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/status", nil))

	var value Status
	if err := json.NewDecoder(recorder.Body).Decode(&value); err != nil {
		t.Fatalf("status: %v", err)
	}
	return value
}

func waitFor(t *testing.T, what string, condition func() bool) {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		if condition() {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %s", what)
}

// A pod with nothing in it is healthy and idle: the deployment exists before
// anybody has pushed anything, and that has to be a normal state rather than a
// failure.
func TestEmptyPodIsHealthy(t *testing.T) {
	supervisor, _ := newSupervisor(t)

	recorder := httptest.NewRecorder()
	supervisor.routes().ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if recorder.Code != http.StatusOK {
		t.Fatalf("health said %d", recorder.Code)
	}

	if state := status(t, supervisor); state.State != "idle" || state.HasBinary {
		t.Fatalf("expected an empty idle pod, got %+v", state)
	}
}

func TestPushRunsTheProgram(t *testing.T) {
	binary := buildFixture(t, `package main

import (
	"fmt"
	"os"
	"time"
)

func main() {
	fmt.Println("hello from", os.Getenv("WHO"))
	time.Sleep(time.Minute)
}
`)
	content, err := os.ReadFile(binary)
	if err != nil {
		t.Fatal(err)
	}

	supervisor, path := newSupervisor(t)
	t.Setenv("WHO", "the fixture")
	defer supervisor.Stop()

	if recorder := post(t, supervisor, "/binary", content, ""); recorder.Code != http.StatusOK {
		t.Fatalf("push said %d: %s", recorder.Code, recorder.Body)
	}

	if info, err := os.Stat(path); err != nil {
		t.Fatalf("nothing written: %v", err)
	} else if info.Mode()&0o111 == 0 {
		t.Fatalf("written but not executable: %v", info.Mode())
	}

	waitFor(t, "the program to run", func() bool { return status(t, supervisor).State == "running" })
	waitFor(t, "its output", func() bool {
		for _, line := range supervisor.logs.tail(0) {
			if line == "hello from the fixture" {
				return true
			}
		}
		return false
	})
}

// The whole point of the loop: a second push replaces the first program while
// the pod stays up.
func TestSecondPushReplacesTheFirst(t *testing.T) {
	supervisor, _ := newSupervisor(t)
	defer supervisor.Stop()

	for _, word := range []string{"first", "second"} {
		source := fmt.Sprintf(`package main

import (
	"fmt"
	"time"
)

func main() {
	fmt.Println("I am %s")
	time.Sleep(time.Minute)
}
`, word)
		content, err := os.ReadFile(buildFixture(t, source))
		if err != nil {
			t.Fatal(err)
		}
		if recorder := post(t, supervisor, "/binary", content, ""); recorder.Code != http.StatusOK {
			t.Fatalf("push said %d: %s", recorder.Code, recorder.Body)
		}
		waitFor(t, "the "+word+" program", func() bool {
			for _, line := range supervisor.logs.tail(0) {
				if line == "I am "+word {
					return true
				}
			}
			return false
		})
	}
}

// A binary going over a slow link is worth compressing, and the pod has to
// accept it either way.
func TestAcceptsAGzippedBinary(t *testing.T) {
	content, err := os.ReadFile(buildFixture(t, `package main

import "fmt"

func main() { fmt.Println("compressed") }
`))
	if err != nil {
		t.Fatal(err)
	}

	var packed bytes.Buffer
	writer := gzip.NewWriter(&packed)
	if _, err := writer.Write(content); err != nil {
		t.Fatal(err)
	}
	writer.Close()

	supervisor, path := newSupervisor(t)
	defer supervisor.Stop()

	if recorder := post(t, supervisor, "/binary", packed.Bytes(), "gzip"); recorder.Code != http.StatusOK {
		t.Fatalf("push said %d: %s", recorder.Code, recorder.Body)
	}
	written, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(written, content) {
		t.Fatalf("unpacked to %d bytes, wanted %d", len(written), len(content))
	}
}

func TestRejectsSomethingThatIsNotGzip(t *testing.T) {
	supervisor, _ := newSupervisor(t)
	if recorder := post(t, supervisor, "/binary", []byte("plain text"), "gzip"); recorder.Code != http.StatusBadRequest {
		t.Fatalf("expected a complaint, got %d", recorder.Code)
	}
}

// A program that exits is reported with its code rather than silently gone:
// the editor shows it, and the pod stays up for the next push.
func TestReportsAnExit(t *testing.T) {
	content, err := os.ReadFile(buildFixture(t, `package main

import "os"

func main() { os.Exit(3) }
`))
	if err != nil {
		t.Fatal(err)
	}

	supervisor, _ := newSupervisor(t)
	defer supervisor.Stop()
	post(t, supervisor, "/binary", content, "")

	waitFor(t, "the exit to be noticed", func() bool {
		state := status(t, supervisor)
		return state.State == "exited" && state.ExitCode != nil && *state.ExitCode == 3
	})
}

func TestStopEndsTheProgram(t *testing.T) {
	content, err := os.ReadFile(buildFixture(t, `package main

import "time"

func main() { time.Sleep(time.Minute) }
`))
	if err != nil {
		t.Fatal(err)
	}

	supervisor, _ := newSupervisor(t)
	defer supervisor.Stop()
	post(t, supervisor, "/binary", content, "")
	waitFor(t, "it to run", func() bool { return status(t, supervisor).State == "running" })

	post(t, supervisor, "/stop", nil, "")
	if state := status(t, supervisor); state.State == "running" {
		t.Fatalf("still running: %+v", state)
	}
}

// Pushing without starting is how a pod is prepared before anybody wants it.
func TestPushCanSkipStarting(t *testing.T) {
	content, err := os.ReadFile(buildFixture(t, `package main

import "time"

func main() { time.Sleep(time.Minute) }
`))
	if err != nil {
		t.Fatal(err)
	}

	supervisor, _ := newSupervisor(t)
	defer supervisor.Stop()

	post(t, supervisor, "/binary?start=false", content, "")
	state := status(t, supervisor)
	if state.State == "running" {
		t.Fatalf("started when it was told not to: %+v", state)
	}
	if !state.HasBinary {
		t.Fatalf("did not keep the binary: %+v", state)
	}
}

func TestStartingNothingSaysSo(t *testing.T) {
	supervisor, _ := newSupervisor(t)
	if recorder := post(t, supervisor, "/start", nil, ""); recorder.Code == http.StatusOK {
		t.Fatalf("started a program that does not exist")
	}
}
