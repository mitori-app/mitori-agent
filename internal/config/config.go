// Package config loads agent configuration from platform-specific paths.
//
// Config file locations:
//   - Linux:   /etc/mitori/config.yaml
//   - macOS:   /Library/Application Support/Mitori/config.yaml
//   - Windows: %ProgramData%\Mitori\config.yaml
//
// Token storage:
//   - Linux/macOS: secret file next to config (token), chmod 600
//   - Windows:     Windows Credential Manager via go-keyring
package config

import (
	"fmt"
	"os"
	"strings"

	"gopkg.in/yaml.v3"
)

// Config holds the agent's persistent configuration.
type Config struct {
	HostID      string `yaml:"hostId"`
	Hostname    string `yaml:"hostname"`
	IngestorURL string `yaml:"ingestorUrl"`
}

// AgentConfig bundles the config file values with the host API key.
type AgentConfig struct {
	Config
	HostAPIKey string
}

// Load reads the config file and retrieves the host token from secure storage.
// It returns an error if either the config file or token is missing.
func Load() (*AgentConfig, error) {
	configPath, tokenPath := platformPaths()

	// Read config file
	data, err := os.ReadFile(configPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("config file not found at %s — run the Mitori install script first", configPath)
		}
		return nil, fmt.Errorf("failed to read config file %s: %w", configPath, err)
	}

	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("failed to parse config file: %w", err)
	}

	if cfg.HostID == "" {
		return nil, fmt.Errorf("hostId is missing from config file %s", configPath)
	}
	if cfg.IngestorURL == "" {
		return nil, fmt.Errorf("ingestorUrl is missing from config file %s", configPath)
	}

	// Read token from platform-specific secure storage
	token, err := readToken(tokenPath)
	if err != nil {
		return nil, err
	}

	return &AgentConfig{
		Config:     cfg,
		HostAPIKey: token,
	}, nil
}

// readToken retrieves the host token. On Linux/macOS it reads a chmod-600
// secret file; on Windows it uses the Windows Credential Manager via go-keyring.
// The platform-specific implementations live in token_unix.go and token_windows.go.
func readToken(tokenPath string) (string, error) {
	return readTokenPlatform(tokenPath)
}

// platformPaths returns the config file path and token path/key for the current OS.
// Implemented per-platform in paths_*.go files.
func platformPaths() (configPath, tokenPath string) {
	return platformConfigPath()
}

// trimToken removes trailing whitespace/newlines from a token string.
func trimToken(s string) string {
	return strings.TrimSpace(s)
}
