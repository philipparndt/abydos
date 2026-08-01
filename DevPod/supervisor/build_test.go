package main

import (
	"os/exec"
	"testing"
)

// Compiles a fixture with the toolchain the tests are running under.
func build(t *testing.T, directory, output string) {
	t.Helper()
	command := exec.Command("go", "build", "-o", output, ".")
	command.Dir = directory
	if out, err := command.CombinedOutput(); err != nil {
		t.Fatalf("building the fixture failed: %v\n%s", err, out)
	}
}
