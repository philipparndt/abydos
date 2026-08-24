// Command mkimage builds the development pod's image without a builder.
//
// A Docker daemon is one more thing to have working, and on a machine behind a
// corporate proxy it is often the thing that is not: a poisoned pull-through
// cache breaks every build, and none of it has anything to do with the two
// static binaries this image contains. So the image is assembled here — a tar
// of files, a JSON config, a manifest — which is all a single-layer image is,
// and handed straight to the cluster.
//
// The output is a docker-save tarball, which is what containerd, k3s's
// auto-import directory, `k3d image import` and `docker load` all accept.
package main

import (
	"archive/tar"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

func main() {
	var (
		output    = flag.String("out", "image.tar", "tarball to write")
		reference = flag.String("tag", "abydos-devpod:dev", "image reference")
		arch      = flag.String("arch", "arm64", "linux architecture")
		from      = flag.String("from", "", "directory whose contents become the image")
		entry     = flag.String("entrypoint", "/usr/local/bin/abydos-supervisor", "entrypoint")
		envs      = flag.String("env", "", "comma-separated KEY=VALUE")
		ports     = flag.String("ports", "7999/tcp,2345/tcp", "comma-separated exposed ports")
		push      = flag.String("push", "", "registry reference to publish to, e.g. user/image:tag")
	)
	var layers variants
	flag.Var(&layers, "layer", "arch=directory to publish (repeatable)")
	flag.Parse()

	// Publishing takes one rootfs per architecture and writes no tarball: what
	// a remote cluster needs is something to pull, not a file on this machine.
	if *push != "" {
		if err := publish(*push, layers, *entry, split(*envs), split(*ports)); err != nil {
			fmt.Fprintln(os.Stderr, "mkimage:", err)
			os.Exit(1)
		}
		return
	}

	if *from == "" {
		fmt.Fprintln(os.Stderr, "mkimage: -from is required")
		os.Exit(2)
	}
	if err := build(*from, *output, *reference, *arch, *entry, split(*envs), split(*ports)); err != nil {
		fmt.Fprintln(os.Stderr, "mkimage:", err)
		os.Exit(1)
	}
	info, _ := os.Stat(*output)
	fmt.Printf("%s → %s (%.1f MB)\n", *reference, *output, float64(info.Size())/(1<<20))
}

// variants collects the repeated -layer flags.
type variants []variant

func (v *variants) String() string { return fmt.Sprint([]variant(*v)) }

func (v *variants) Set(value string) error {
	arch, dir, found := strings.Cut(value, "=")
	if !found {
		return fmt.Errorf("want arch=directory, got %q", value)
	}
	*v = append(*v, variant{arch: arch, dir: dir})
	return nil
}

func split(value string) []string {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	parts := strings.Split(value, ",")
	for i := range parts {
		parts[i] = strings.TrimSpace(parts[i])
	}
	return parts
}

func build(root, output, reference, arch, entrypoint string, envs, ports []string) error {
	// The layer first, because the config has to name its digest.
	layer, diffID, err := makeLayer(root)
	if err != nil {
		return err
	}

	config := map[string]any{
		"architecture": arch,
		"os":           "linux",
		"created":      time.Unix(0, 0).UTC().Format(time.RFC3339),
		"config": map[string]any{
			"Entrypoint":   []string{entrypoint},
			"Env":          envs,
			"WorkingDir":   "/app",
			"ExposedPorts": exposed(ports),
		},
		"rootfs": map[string]any{
			"type":     "layers",
			"diff_ids": []string{"sha256:" + diffID},
		},
		"history": []map[string]any{
			{"created": time.Unix(0, 0).UTC().Format(time.RFC3339), "created_by": "abydos mkimage"},
		},
	}
	configJSON, err := json.Marshal(config)
	if err != nil {
		return err
	}
	configDigest := sha256.Sum256(configJSON)
	configName := hex.EncodeToString(configDigest[:]) + ".json"

	manifest := []map[string]any{{
		"Config":   configName,
		"RepoTags": []string{reference},
		"Layers":   []string{"layer.tar"},
	}}
	manifestJSON, err := json.Marshal(manifest)
	if err != nil {
		return err
	}

	file, err := os.Create(output)
	if err != nil {
		return err
	}
	defer file.Close()

	writer := tar.NewWriter(file)
	defer writer.Close()

	for _, entry := range []struct {
		name string
		data []byte
	}{
		{configName, configJSON},
		{"manifest.json", manifestJSON},
	} {
		if err := writeFile(writer, entry.name, entry.data); err != nil {
			return err
		}
	}
	return writeFile(writer, "layer.tar", layer)
}

func exposed(ports []string) map[string]any {
	result := map[string]any{}
	for _, port := range ports {
		result[port] = map[string]any{}
	}
	return result
}

func writeFile(writer *tar.Writer, name string, data []byte) error {
	header := &tar.Header{
		Name:     name,
		Mode:     0o644,
		Size:     int64(len(data)),
		Typeflag: tar.TypeReg,
		ModTime:  time.Unix(0, 0),
	}
	if err := writer.WriteHeader(header); err != nil {
		return err
	}
	_, err := writer.Write(data)
	return err
}

// makeLayer tars a directory and returns it with its digest.
//
// Uncompressed, because the tarball is imported locally and gzip would only
// add a second of CPU at both ends. Deterministic: sorted names, fixed times,
// so the same inputs make the same image and a cluster that already has it
// does nothing.
func makeLayer(root string) (data []byte, diffID string, err error) {
	var paths []string
	err = filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if path == root {
			return nil
		}
		paths = append(paths, path)
		return nil
	})
	if err != nil {
		return nil, "", err
	}
	sort.Strings(paths)

	buffer := &writeCounter{}
	digest := sha256.New()
	writer := tar.NewWriter(io.MultiWriter(buffer, digest))

	for _, path := range paths {
		info, err := os.Lstat(path)
		if err != nil {
			return nil, "", err
		}
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return nil, "", err
		}

		header, err := tar.FileInfoHeader(info, "")
		if err != nil {
			return nil, "", err
		}
		header.Name = filepath.ToSlash(relative)
		header.Uid, header.Gid = 0, 0
		header.Uname, header.Gname = "", ""
		header.ModTime = time.Unix(0, 0)
		header.AccessTime = time.Time{}
		header.ChangeTime = time.Time{}
		if info.IsDir() {
			header.Name += "/"
			// A directory a non-root pod has to write into: the binary is
			// pushed in at runtime, and the chart may run as anybody.
			if header.Name == "app/" || header.Name == "tmp/" {
				header.Mode = 0o1777
			}
		}

		if err := writer.WriteHeader(header); err != nil {
			return nil, "", err
		}
		if info.Mode().IsRegular() {
			source, err := os.Open(path)
			if err != nil {
				return nil, "", err
			}
			if _, err := io.Copy(writer, source); err != nil {
				source.Close()
				return nil, "", err
			}
			source.Close()
		}
	}
	if err := writer.Close(); err != nil {
		return nil, "", err
	}
	return buffer.Bytes(), hex.EncodeToString(digest.Sum(nil)), nil
}

// writeCounter keeps the layer in memory: it is tens of megabytes, and having
// it whole is what lets the digest and the tarball be written in one pass.
type writeCounter struct{ data []byte }

func (w *writeCounter) Write(p []byte) (int, error) {
	w.data = append(w.data, p...)
	return len(p), nil
}

func (w *writeCounter) Bytes() []byte { return w.data }
