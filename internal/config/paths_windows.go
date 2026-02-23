//go:build windows

package config

import (
	"os"
	"path/filepath"
)

func platformConfigPath() (configPath, tokenPath string) {
	programData := os.Getenv("ProgramData")
	if programData == "" {
		programData = `C:\ProgramData`
	}
	dir := filepath.Join(programData, "Mitori")
	// tokenPath is unused on Windows (go-keyring reads from Credential Manager).
	// We return a sentinel value so token_windows.go can ignore it.
	return filepath.Join(dir, "config.yaml"), ""
}
