package main

import (
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// Pushing the image to a registry, without a daemon.
//
// A remote cluster cannot be handed a tarball: it pulls, so the image has to be
// somewhere it can pull from. Everything the registry protocol needs for a
// single-layer image is here — a blob upload, a manifest per architecture, and
// an index naming them — which is a few hundred lines and removes the
// requirement for Docker and buildx on the machine that publishes.

const (
	mediaManifest = "application/vnd.docker.distribution.manifest.v2+json"
	mediaIndex    = "application/vnd.docker.distribution.manifest.list.v2+json"
	mediaConfig   = "application/vnd.docker.container.image.v1+json"
	mediaLayer    = "application/vnd.docker.image.rootfs.diff.tar.gzip"
)

type descriptor struct {
	MediaType string    `json:"mediaType"`
	Digest    string    `json:"digest"`
	Size      int64     `json:"size"`
	Platform  *platform `json:"platform,omitempty"`
}

type platform struct {
	Architecture string `json:"architecture"`
	OS           string `json:"os"`
}

type manifest struct {
	SchemaVersion int          `json:"schemaVersion"`
	MediaType     string       `json:"mediaType"`
	Config        descriptor   `json:"config"`
	Layers        []descriptor `json:"layers"`
}

type index struct {
	SchemaVersion int          `json:"schemaVersion"`
	MediaType     string       `json:"mediaType"`
	Manifests     []descriptor `json:"manifests"`
}

// A rootfs directory and the architecture it was built for.
type variant struct {
	arch string
	dir  string
}

type registry struct {
	base   string // https://registry-1.docker.io
	name   string // pharndt/abydos-devpod
	tag    string
	token  string
	client *http.Client
}

// publish uploads one image per variant and an index naming all of them.
func publish(reference string, variants []variant, entrypoint string, envs, ports []string) error {
	if len(variants) == 0 {
		return errors.New("nothing to push: give at least one -layer arch=dir")
	}

	target, err := newRegistry(reference)
	if err != nil {
		return err
	}
	if err := target.authenticate(); err != nil {
		return err
	}

	var manifests []descriptor
	for _, item := range variants {
		descriptor, err := target.pushVariant(item, entrypoint, envs, ports)
		if err != nil {
			return fmt.Errorf("%s: %w", item.arch, err)
		}
		manifests = append(manifests, descriptor)
		fmt.Printf("  %-6s %s\n", item.arch, descriptor.Digest)
	}

	body, err := json.Marshal(index{
		SchemaVersion: 2,
		MediaType:     mediaIndex,
		Manifests:     manifests,
	})
	if err != nil {
		return err
	}
	if err := target.putManifest(target.tag, mediaIndex, body); err != nil {
		return err
	}
	fmt.Printf("%s/%s:%s → %s\n", target.base, target.name, target.tag, digestOf(body))
	return nil
}

// pushVariant sends one architecture's layer, config and manifest.
func (r *registry) pushVariant(item variant, entrypoint string, envs, ports []string) (descriptor, error) {
	layer, diffID, err := makeLayer(item.dir)
	if err != nil {
		return descriptor{}, err
	}

	// Compressed on the way out: a registry stores what it is given, and a
	// cluster on the other side of a VPN pulls half as much this way.
	var compressed bytes.Buffer
	writer, _ := gzip.NewWriterLevel(&compressed, gzip.BestCompression)
	if _, err := writer.Write(layer); err != nil {
		return descriptor{}, err
	}
	if err := writer.Close(); err != nil {
		return descriptor{}, err
	}

	configJSON, err := json.Marshal(imageConfig(item.arch, diffID, entrypoint, envs, ports))
	if err != nil {
		return descriptor{}, err
	}

	for _, blob := range []struct {
		data []byte
		what string
	}{
		{compressed.Bytes(), "layer"},
		{configJSON, "config"},
	} {
		if err := r.putBlob(blob.data); err != nil {
			return descriptor{}, fmt.Errorf("%s: %w", blob.what, err)
		}
	}

	body, err := json.Marshal(manifest{
		SchemaVersion: 2,
		MediaType:     mediaManifest,
		Config:        descriptor{MediaType: mediaConfig, Digest: digestOf(configJSON), Size: int64(len(configJSON))},
		Layers: []descriptor{{
			MediaType: mediaLayer,
			Digest:    digestOf(compressed.Bytes()),
			Size:      int64(compressed.Len()),
		}},
	})
	if err != nil {
		return descriptor{}, err
	}

	// By digest, not by tag: the tag belongs to the index, which is what a
	// `docker pull` of this repository should find.
	if err := r.putManifest(digestOf(body), mediaManifest, body); err != nil {
		return descriptor{}, err
	}
	return descriptor{
		MediaType: mediaManifest,
		Digest:    digestOf(body),
		Size:      int64(len(body)),
		Platform:  &platform{Architecture: item.arch, OS: "linux"},
	}, nil
}

func imageConfig(arch, diffID, entrypoint string, envs, ports []string) map[string]any {
	created := time.Unix(0, 0).UTC().Format(time.RFC3339)
	return map[string]any{
		"architecture": arch,
		"os":           "linux",
		"created":      created,
		"config": map[string]any{
			"Entrypoint":   []string{entrypoint},
			"Env":          envs,
			"WorkingDir":   "/app",
			"ExposedPorts": exposed(ports),
		},
		"rootfs":  map[string]any{"type": "layers", "diff_ids": []string{"sha256:" + diffID}},
		"history": []map[string]any{{"created": created, "created_by": "abydos mkimage"}},
	}
}

func digestOf(data []byte) string {
	sum := sha256.Sum256(data)
	return "sha256:" + hex.EncodeToString(sum[:])
}

// MARK: - The registry protocol

func newRegistry(reference string) (*registry, error) {
	name, tag := reference, "latest"
	if index := strings.LastIndex(reference, ":"); index > strings.LastIndex(reference, "/") {
		name, tag = reference[:index], reference[index+1:]
	}

	host := "registry-1.docker.io"
	scheme := "https"
	if parts := strings.SplitN(name, "/", 2); len(parts) == 2 &&
		(strings.Contains(parts[0], ".") || strings.Contains(parts[0], ":") || parts[0] == "localhost") {
		host, name = parts[0], parts[1]
		if strings.HasPrefix(host, "localhost") || strings.HasPrefix(host, "127.0.0.1") {
			scheme = "http"
		}
	} else if !strings.Contains(name, "/") {
		// `ubuntu` means `library/ubuntu`, and so does anything else without a
		// user in front of it.
		name = "library/" + name
	}

	return &registry{
		base:   scheme + "://" + host,
		name:   name,
		tag:    tag,
		client: &http.Client{Timeout: 10 * time.Minute},
	}, nil
}

// authenticate asks the registry what it wants and gets a token for it.
//
// The challenge is followed rather than assumed: Docker Hub, GHCR and a
// registry somebody runs in their cluster all say where their token endpoint
// is, and one that wants nothing simply says so.
func (r *registry) authenticate() error {
	response, err := r.client.Get(r.base + "/v2/")
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode == http.StatusOK {
		return nil
	}

	challenge := response.Header.Get("Www-Authenticate")
	if !strings.HasPrefix(strings.ToLower(challenge), "bearer ") {
		return fmt.Errorf("registry wants %q, which this does not speak", challenge)
	}
	fields := map[string]string{}
	for _, part := range strings.Split(challenge[len("Bearer "):], ",") {
		key, value, found := strings.Cut(strings.TrimSpace(part), "=")
		if found {
			fields[key] = strings.Trim(value, `"`)
		}
	}

	request, err := http.NewRequest("GET", fields["realm"], nil)
	if err != nil {
		return err
	}
	query := request.URL.Query()
	if service := fields["service"]; service != "" {
		query.Set("service", service)
	}
	query.Set("scope", "repository:"+r.name+":pull,push")
	request.URL.RawQuery = query.Encode()

	user, secret, err := credentials(strings.TrimPrefix(strings.TrimPrefix(r.base, "https://"), "http://"))
	if err != nil {
		return err
	}
	request.SetBasicAuth(user, secret)

	token, err := r.client.Do(request)
	if err != nil {
		return err
	}
	defer token.Body.Close()
	if token.StatusCode != http.StatusOK {
		return fmt.Errorf("could not log in as %q: %s", user, status(token))
	}

	var answer struct {
		Token       string `json:"token"`
		AccessToken string `json:"access_token"`
	}
	if err := json.NewDecoder(token.Body).Decode(&answer); err != nil {
		return err
	}
	r.token = answer.Token
	if r.token == "" {
		r.token = answer.AccessToken
	}
	return nil
}

func (r *registry) request(method, url string, body io.Reader) (*http.Request, error) {
	request, err := http.NewRequest(method, url, body)
	if err != nil {
		return nil, err
	}
	if r.token != "" {
		request.Header.Set("Authorization", "Bearer "+r.token)
	}
	return request, nil
}

// putBlob uploads a blob unless the registry already has it.
func (r *registry) putBlob(data []byte) error {
	digest := digestOf(data)

	head, err := r.request("HEAD", r.blobURL(digest), nil)
	if err != nil {
		return err
	}
	if response, err := r.client.Do(head); err == nil {
		response.Body.Close()
		if response.StatusCode == http.StatusOK {
			return nil
		}
	}

	start, err := r.request("POST", r.base+"/v2/"+r.name+"/blobs/uploads/", nil)
	if err != nil {
		return err
	}
	response, err := r.client.Do(start)
	if err != nil {
		return err
	}
	response.Body.Close()
	if response.StatusCode != http.StatusAccepted {
		return fmt.Errorf("upload refused: %s", status(response))
	}

	location := response.Header.Get("Location")
	if location == "" {
		return errors.New("upload accepted without saying where to")
	}
	if strings.HasPrefix(location, "/") {
		location = r.base + location
	}
	separator := "?"
	if strings.Contains(location, "?") {
		separator = "&"
	}

	upload, err := r.request("PUT", location+separator+"digest="+digest, bytes.NewReader(data))
	if err != nil {
		return err
	}
	upload.Header.Set("Content-Type", "application/octet-stream")
	upload.ContentLength = int64(len(data))

	done, err := r.client.Do(upload)
	if err != nil {
		return err
	}
	done.Body.Close()
	if done.StatusCode != http.StatusCreated && done.StatusCode != http.StatusOK {
		return fmt.Errorf("upload failed: %s", status(done))
	}
	return nil
}

func (r *registry) putManifest(name, mediaType string, body []byte) error {
	request, err := r.request("PUT", r.base+"/v2/"+r.name+"/manifests/"+name, bytes.NewReader(body))
	if err != nil {
		return err
	}
	request.Header.Set("Content-Type", mediaType)

	response, err := r.client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusCreated && response.StatusCode != http.StatusOK {
		return fmt.Errorf("manifest refused: %s", status(response))
	}
	return nil
}

func (r *registry) blobURL(digest string) string {
	return r.base + "/v2/" + r.name + "/blobs/" + digest
}

// status turns a failed response into something worth reading.
func status(response *http.Response) string {
	body, _ := io.ReadAll(io.LimitReader(response.Body, 4096))
	text := strings.TrimSpace(string(body))
	if text == "" {
		return response.Status
	}
	return response.Status + ": " + text
}

// MARK: - Credentials

// credentials finds a login for a registry the way the docker CLI does.
//
// The environment first, so a CI job can say what it is without a config file;
// then `~/.docker/config.json`, including the credential helpers, because on a
// Mac that file usually holds no password at all — the keychain does.
func credentials(host string) (user, secret string, err error) {
	if user, secret := os.Getenv("DOCKER_USERNAME"), os.Getenv("DOCKER_PASSWORD"); user != "" && secret != "" {
		return user, secret, nil
	}

	path := filepath.Join(os.Getenv("HOME"), ".docker", "config.json")
	data, err := os.ReadFile(path)
	if err != nil {
		return "", "", fmt.Errorf("no login for %s: set DOCKER_USERNAME and DOCKER_PASSWORD, or run docker login", host)
	}

	var config struct {
		Auths map[string]struct {
			Auth string `json:"auth"`
		} `json:"auths"`
		CredsStore  string            `json:"credsStore"`
		CredHelpers map[string]string `json:"credHelpers"`
	}
	if err := json.Unmarshal(data, &config); err != nil {
		return "", "", err
	}

	for _, key := range keysFor(host) {
		if entry, ok := config.Auths[key]; ok && entry.Auth != "" {
			decoded, err := base64.StdEncoding.DecodeString(entry.Auth)
			if err != nil {
				return "", "", err
			}
			user, secret, found := strings.Cut(string(decoded), ":")
			if found {
				return user, secret, nil
			}
		}
	}

	helper := config.CredsStore
	for _, key := range keysFor(host) {
		if named, ok := config.CredHelpers[key]; ok {
			helper = named
			break
		}
	}
	if helper == "" {
		return "", "", fmt.Errorf("no login for %s in %s", host, path)
	}
	return fromHelper(helper, host)
}

// The names a registry goes by in a docker config: Docker Hub is written four
// different ways depending on which version of the CLI logged in.
func keysFor(host string) []string {
	keys := []string{host, "https://" + host}
	if host == "registry-1.docker.io" || host == "index.docker.io" || host == "docker.io" {
		keys = append(keys,
			"https://index.docker.io/v1/", "index.docker.io", "docker.io", "registry-1.docker.io")
	}
	return keys
}

func fromHelper(helper, host string) (user, secret string, err error) {
	command := exec.Command("docker-credential-"+helper, "get")
	command.Stdin = strings.NewReader(host)
	output, err := command.Output()
	if err != nil {
		// The keychain is asked for the name it was stored under, which for
		// Docker Hub is not the host a pull goes to.
		if host == "registry-1.docker.io" {
			return fromHelper(helper, "https://index.docker.io/v1/")
		}
		return "", "", fmt.Errorf("docker-credential-%s could not find a login for %s", helper, host)
	}

	var answer struct{ Username, Secret string }
	if err := json.Unmarshal(output, &answer); err != nil {
		return "", "", err
	}
	return answer.Username, answer.Secret, nil
}
