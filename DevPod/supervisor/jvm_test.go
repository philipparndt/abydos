package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// A jar is a zip, and that is how a pod restarting on its own knows to run one
// with the JVM rather than execute it and report "exec format error".
func TestIsJarReadsTheFile(t *testing.T) {
	directory := t.TempDir()

	jar := filepath.Join(directory, "app.jar")
	if err := os.WriteFile(jar, append([]byte("PK\x03\x04"), make([]byte, 64)...), 0o644); err != nil {
		t.Fatal(err)
	}
	binary := filepath.Join(directory, "app")
	if err := os.WriteFile(binary, []byte("\x7fELF and the rest"), 0o755); err != nil {
		t.Fatal(err)
	}

	if !isJar(jar) {
		t.Error("a zip header is a jar")
	}
	if isJar(binary) {
		t.Error("an ELF binary is not a jar")
	}
	if isJar(filepath.Join(directory, "nothing")) {
		t.Error("a file that is not there is not a jar")
	}
	// A file too short to hold the header is not one either, and must not
	// panic on the way to saying so.
	short := filepath.Join(directory, "short")
	if err := os.WriteFile(short, []byte("PK"), 0o644); err != nil {
		t.Fatal(err)
	}
	if isJar(short) {
		t.Error("two bytes are not a jar")
	}
}

// A pod without a JVM says so, rather than failing with "no such file", which
// reads as a missing jar rather than the wrong image.
func TestJVMModeWithoutAJava(t *testing.T) {
	supervisor, path := newSupervisor(t)
	supervisor.options.JavaPath = filepath.Join(t.TempDir(), "java")
	// The machine running these tests usually has a JVM, and the pod being
	// described here does not — so it is taken off the path for the test, the
	// same as it is absent from every image but the jvm one.
	t.Setenv("PATH", "")
	if err := os.WriteFile(path, []byte("PK\x03\x04"), 0o644); err != nil {
		t.Fatal(err)
	}

	err := supervisor.Start(ModeJVM)
	if err == nil {
		t.Fatal("expected a JVM-less pod to refuse")
	}
	if !strings.Contains(err.Error(), "-jvm image") {
		t.Errorf("the error should say which image is needed, got: %v", err)
	}
}

// What the JVM is actually told: the jar, the program's own arguments, and —
// only when debugging — an agent listening on the pod's debug port.
func TestJVMModeRunsTheJar(t *testing.T) {
	supervisor, path := newSupervisor(t)
	if err := os.WriteFile(path, []byte("PK\x03\x04"), 0o644); err != nil {
		t.Fatal(err)
	}
	supervisor.options.Args = []string{"--stage", "dev"}
	supervisor.options.DebugAddr = ":2345"
	supervisor.options.JavaPath = fakeJava(t)

	for _, test := range []struct {
		mode     Mode
		expected []string
		absent   []string
	}{
		{
			mode:     ModeJVM,
			expected: []string{"-jar", path, "--stage", "dev"},
			absent:   []string{"agentlib"},
		},
		{
			mode: ModeJVMDebug,
			expected: []string{
				"-agentlib:jdwp=transport=dt_socket,server=y,suspend=y,address=*:2345",
				"-jar", path,
			},
		},
	} {
		// The tail belongs to the run being examined: without this the second
		// mode reads the first one's line and passes for the wrong reason.
		supervisor.logs.reset()
		if err := supervisor.Start(test.mode); err != nil {
			t.Fatalf("%s: %v", test.mode, err)
		}

		line := waitForLog(t, supervisor, "argv:")
		for _, want := range test.expected {
			if !strings.Contains(line, want) {
				t.Errorf("%s: expected %q in %q", test.mode, want, line)
			}
		}
		for _, unwanted := range test.absent {
			if strings.Contains(line, unwanted) {
				t.Errorf("%s: did not expect %q in %q", test.mode, unwanted, line)
			}
		}

		if state := status(t, supervisor); test.mode == ModeJVMDebug && state.DebugAddr != ":2345" {
			t.Errorf("a debugging pod should publish its debug address, got %q", state.DebugAddr)
		}
		supervisor.Stop()
	}
}

// A `java` that prints what it was given and waits, so the arguments can be
// read without a JVM being installed on whatever is running these tests.
func fakeJava(t *testing.T) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "java")
	script := "#!/bin/sh\necho \"argv: $@\"\nsleep 30\n"
	if err := os.WriteFile(path, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	return path
}

func waitForLog(t *testing.T, supervisor *Supervisor, prefix string) string {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		for _, line := range supervisor.logs.tail(50) {
			if strings.Contains(line, prefix) {
				return line
			}
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("no log line containing %q", prefix)
	return ""
}
