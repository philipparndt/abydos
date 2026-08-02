// Command ideai-supervisor is PID 1 in a development pod.
//
// It holds a pod open with the real chart's config, secrets, service account
// and sidecars, and waits for a binary to be pushed into it. The point is the
// loop it removes: building an image, pushing it to a registry and upgrading a
// release takes minutes, and copying a freshly built binary into a pod that is
// already running takes about a second.
//
// It never runs anything on its own. A pod with no binary yet is a healthy pod
// doing nothing, which is what lets the deployment exist before the first push
// and survive a program that crashes on startup — a crash loop would otherwise
// take the pod away in the middle of a debugging session.
package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

func main() {
	options := readOptions()
	log.SetFlags(0)
	log.SetPrefix("[supervisor] ")

	supervisor := &Supervisor{options: options, logs: newRing(2000)}
	if err := os.MkdirAll(filepath.Dir(options.BinaryPath), 0o777); err != nil {
		log.Fatalf("cannot create %s: %v", filepath.Dir(options.BinaryPath), err)
	}

	// A binary left by a previous pod — an emptyDir survives a container
	// restart but not a rescheduled pod — is started again, so a crash does
	// not need another push.
	if _, err := os.Stat(options.BinaryPath); err == nil && options.AutoStart {
		if err := supervisor.Start(ModeRun); err != nil {
			log.Printf("could not start the binary that was already here: %v", err)
		}
	}

	stopping := make(chan os.Signal, 1)
	signal.Notify(stopping, syscall.SIGTERM, syscall.SIGINT)
	go func() {
		<-stopping
		log.Printf("shutting down")
		supervisor.Stop()
		os.Exit(0)
	}()

	log.Printf("listening on %s, binary at %s", options.ControlAddr, options.BinaryPath)
	server := &http.Server{Addr: options.ControlAddr, Handler: supervisor.routes()}
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
}

// Options are everything the chart decides.
type Options struct {
	ControlAddr string
	// Where a pushed binary lands. An emptyDir, or a host mount when the
	// cluster runs on the same machine as the editor.
	BinaryPath string
	WorkDir    string
	// Arguments for the program, as the chart's `args` would give them.
	Args []string
	// Where dlv listens when debugging. The editor reaches it through a
	// port-forward.
	DebugAddr string
	DelvePath string
	AutoStart bool
}

func readOptions() Options {
	options := Options{
		ControlAddr: env("IDEAI_CONTROL_ADDR", ":7999"),
		BinaryPath:  env("IDEAI_BINARY", "/app/current"),
		WorkDir:     env("IDEAI_WORKDIR", "/app"),
		DebugAddr:   env("IDEAI_DEBUG_ADDR", ":2345"),
		DelvePath:   env("IDEAI_DLV", "/usr/local/bin/dlv"),
		AutoStart:   env("IDEAI_AUTOSTART", "true") == "true",
	}
	if raw := os.Getenv("IDEAI_ARGS"); raw != "" {
		options.Args = strings.Fields(raw)
	}
	flag.StringVar(&options.ControlAddr, "control", options.ControlAddr, "address for the control API")
	flag.StringVar(&options.BinaryPath, "binary", options.BinaryPath, "where the program lives")
	flag.Parse()
	return options
}

func env(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

// Mode is how the program runs.
type Mode string

const (
	// ModeRun executes the program directly.
	ModeRun Mode = "run"
	// ModeDebug runs `dlv dap`, which waits for the editor to say what to
	// launch. The program starts when the debugger connects, so a session can
	// be prepared before anybody is ready to use it.
	ModeDebug Mode = "debug"
)

// Supervisor owns the child process.
type Supervisor struct {
	options Options
	logs    *ring

	mutex     sync.Mutex
	command   *exec.Cmd
	mode      Mode
	startedAt time.Time
	exitCode  *int
	// Set while a push is replacing the binary, so a child that dies because
	// we killed it is not reported as a crash.
	replacing bool
	// `KEY=VALUE` from the last push, on top of what the chart set.
	extraEnvironment []string
}

func (s *Supervisor) setArguments(arguments []string) {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	s.options.Args = arguments
}

func (s *Supervisor) setEnvironment(environment []string) {
	s.mutex.Lock()
	defer s.mutex.Unlock()
	s.extraEnvironment = environment
}

func (s *Supervisor) routes() http.Handler {
	mux := http.NewServeMux()

	// Answered by the supervisor rather than the program: a pod whose
	// readiness depends on a program somebody is single-stepping through gets
	// restarted in the middle of the session.
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "ok")
	})
	mux.HandleFunc("/status", s.handleStatus)
	mux.HandleFunc("/binary", s.handleBinary)
	mux.HandleFunc("/file", s.handleFile)
	mux.HandleFunc("/start", s.handleStart)
	mux.HandleFunc("/stop", s.handleStop)
	mux.HandleFunc("/logs", s.handleLogs)
	return mux
}

// Status is what the editor shows about a pod.
type Status struct {
	State      string `json:"state"`
	Mode       string `json:"mode,omitempty"`
	PID        int    `json:"pid,omitempty"`
	ExitCode   *int   `json:"exitCode,omitempty"`
	UptimeSecs int    `json:"uptimeSeconds,omitempty"`
	HasBinary  bool   `json:"hasBinary"`
	BinarySize int64  `json:"binarySize,omitempty"`
	BinaryTime string `json:"binaryModified,omitempty"`
	DebugAddr  string `json:"debugAddress,omitempty"`
	Arch       string `json:"arch"`
}

func (s *Supervisor) handleStatus(w http.ResponseWriter, r *http.Request) {
	s.mutex.Lock()
	defer s.mutex.Unlock()

	status := Status{State: "idle", Arch: archName()}
	if info, err := os.Stat(s.options.BinaryPath); err == nil {
		status.HasBinary = true
		status.BinarySize = info.Size()
		status.BinaryTime = info.ModTime().UTC().Format(time.RFC3339)
	}
	if s.command != nil && s.command.Process != nil {
		status.State = "running"
		status.Mode = string(s.mode)
		status.PID = s.command.Process.Pid
		status.UptimeSecs = int(time.Since(s.startedAt).Seconds())
		if s.mode == ModeDebug {
			status.DebugAddr = s.options.DebugAddr
		}
	} else if s.exitCode != nil {
		status.State = "exited"
		status.ExitCode = s.exitCode
	}
	writeJSON(w, status)
}

// handleBinary receives a program and starts it.
//
// The write is atomic — a temporary file beside the target, then a rename —
// because a half-written binary that gets executed produces an error message
// about the file format, which reads like a bug in the program rather than a
// transfer that was still going on.
func (s *Supervisor) handleBinary(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost && r.Method != http.MethodPut {
		http.Error(w, "post a binary", http.StatusMethodNotAllowed)
		return
	}

	mode := Mode(query(r, "mode", string(ModeRun)))
	// What to run it with. The chart's values are the default, but a launch
	// configuration knows the arguments the developer is actually working with
	// — the config file they just sent, the flag they are testing — and those
	// have to reach the program.
	if arguments, ok := r.URL.Query()["arg"]; ok {
		s.setArguments(arguments)
	}
	if environment, ok := r.URL.Query()["env"]; ok {
		s.setEnvironment(environment)
	}

	body, err := decodeBody(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	defer body.Close()

	s.setReplacing(true)
	s.Stop()

	// The tail belongs to the program that produced it. Kept across a push, a
	// log pane shows the previous program's output beside the new one's, and
	// the two are impossible to tell apart.
	s.logs.reset()

	written, err := writeAtomic(s.options.BinaryPath, body)
	s.setReplacing(false)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	log.Printf("received %d bytes, mode %s", written, mode)
	s.logs.add(fmt.Sprintf("[supervisor] received %d bytes, mode %s", written, mode))

	if query(r, "start", "true") == "true" {
		if err := s.Start(mode); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
	}
	s.handleStatus(w, r)
}

// handleFile receives something the program needs to read.
//
// A configuration file, a certificate, a fixture: the program under
// development expects them beside it, and a pod that only ever received a
// binary makes it exit with "no such file" — which is a poor way to learn that
// a config was never sent.
func (s *Supervisor) handleFile(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost && r.Method != http.MethodPut {
		http.Error(w, "post a file", http.StatusMethodNotAllowed)
		return
	}

	path := query(r, "path", "")
	if path == "" {
		http.Error(w, "say where with ?path=", http.StatusBadRequest)
		return
	}
	// Under the working directory or /tmp, and nowhere else: this endpoint is
	// reachable by anybody who can forward a port, and writing over the
	// supervisor or a mounted secret is not something it should be able to do.
	clean := filepath.Clean(path)
	if !within(clean, s.options.WorkDir) && !within(clean, "/tmp") {
		http.Error(w, "files go under "+s.options.WorkDir+" or /tmp", http.StatusForbidden)
		return
	}

	body, err := decodeBody(r)
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	defer body.Close()

	if err := os.MkdirAll(filepath.Dir(clean), 0o777); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	written, err := writeAtomic(clean, body)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	// Not executable: what arrives here is read, and a config file with the
	// execute bit on is a small lie about what it is.
	if err := os.Chmod(clean, 0o644); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	log.Printf("received %s (%d bytes)", clean, written)
	s.logs.add(fmt.Sprintf("[supervisor] received %s (%d bytes)", clean, written))
	writeJSON(w, map[string]any{"path": clean, "size": written})
}

// within reports whether a path is inside a directory.
func within(path, directory string) bool {
	directory = filepath.Clean(directory)
	return path == directory || strings.HasPrefix(path, directory+string(filepath.Separator))
}

func (s *Supervisor) handleStart(w http.ResponseWriter, r *http.Request) {
	if err := s.Start(Mode(query(r, "mode", string(ModeRun)))); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	s.handleStatus(w, r)
}

func (s *Supervisor) handleStop(w http.ResponseWriter, r *http.Request) {
	s.Stop()
	s.handleStatus(w, r)
}

func (s *Supervisor) handleLogs(w http.ResponseWriter, r *http.Request) {
	tail, _ := strconv.Atoi(query(r, "tail", "200"))
	for _, line := range s.logs.tail(tail) {
		fmt.Fprintln(w, line)
	}
}

// Start runs the program, or the debugger in front of it.
func (s *Supervisor) Start(mode Mode) error {
	s.Stop()

	s.mutex.Lock()
	defer s.mutex.Unlock()

	if _, err := os.Stat(s.options.BinaryPath); err != nil {
		return fmt.Errorf("nothing to run at %s", s.options.BinaryPath)
	}
	if err := os.Chmod(s.options.BinaryPath, 0o755); err != nil {
		return fmt.Errorf("cannot make %s executable: %w", s.options.BinaryPath, err)
	}

	var command *exec.Cmd
	switch mode {
	case ModeDebug:
		// `dlv dap` waits for a client and takes the program to launch from
		// it, so the editor decides the arguments and the environment — and
		// they are the ones it is showing the user.
		command = exec.Command(
			s.options.DelvePath,
			"dap",
			"--listen="+s.options.DebugAddr,
			"--log-dest=2",
		)
	default:
		command = exec.Command(s.options.BinaryPath, s.options.Args...)
	}
	command.Dir = s.options.WorkDir
	command.Env = append(os.Environ(), s.extraEnvironment...)

	stdout, err := command.StdoutPipe()
	if err != nil {
		return err
	}
	stderr, err := command.StderrPipe()
	if err != nil {
		return err
	}
	if err := command.Start(); err != nil {
		return fmt.Errorf("cannot start %s: %w", command.Path, err)
	}

	s.command = command
	s.mode = mode
	s.startedAt = time.Now()
	s.exitCode = nil

	go s.pump(stdout, "out")
	go s.pump(stderr, "err")
	go s.reap(command)

	log.Printf("started %s (%s), pid %d", command.Path, mode, command.Process.Pid)
	return nil
}

// Stop ends the child, politely and then not.
func (s *Supervisor) Stop() {
	s.mutex.Lock()
	command := s.command
	s.mutex.Unlock()
	if command == nil || command.Process == nil {
		return
	}

	_ = command.Process.Signal(syscall.SIGTERM)
	done := make(chan struct{})
	go func() {
		_ = command.Wait()
		close(done)
	}()

	select {
	case <-done:
	case <-time.After(5 * time.Second):
		// A program stuck in a shutdown handler must not hold up the next
		// push: waiting longer than this is waiting for a person to give up.
		_ = command.Process.Kill()
		<-done
	}

	s.mutex.Lock()
	if s.command == command {
		s.command = nil
	}
	s.mutex.Unlock()
}

func (s *Supervisor) reap(command *exec.Cmd) {
	err := command.Wait()

	s.mutex.Lock()
	defer s.mutex.Unlock()
	if s.command != command {
		return // already replaced
	}
	s.command = nil

	code := 0
	var exit *exec.ExitError
	if errors.As(err, &exit) {
		code = exit.ExitCode()
	} else if err != nil {
		code = -1
	}
	s.exitCode = &code
	if !s.replacing {
		log.Printf("program exited with %d", code)
		s.logs.add(fmt.Sprintf("[supervisor] program exited with %d", code))
	}
}

// pump copies the child's output to ours, so `kubectl logs` shows the program
// rather than the supervisor, and keeps a tail for the editor.
func (s *Supervisor) pump(reader io.Reader, stream string) {
	buffer := make([]byte, 8192)
	for {
		n, err := reader.Read(buffer)
		if n > 0 {
			text := string(buffer[:n])
			if stream == "err" {
				fmt.Fprint(os.Stderr, text)
			} else {
				fmt.Fprint(os.Stdout, text)
			}
			for _, line := range strings.Split(strings.TrimRight(text, "\n"), "\n") {
				s.logs.add(line)
			}
		}
		if err != nil {
			return
		}
	}
}

func (s *Supervisor) setReplacing(value bool) {
	s.mutex.Lock()
	s.replacing = value
	s.mutex.Unlock()
}
