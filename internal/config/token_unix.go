//go:build linux || darwin

package config

import (
	"fmt"
	"os"
)

// readTokenPlatform reads the host token from the secret file on Linux/macOS.
// The file is written by the install script with chmod 600.
func readTokenPlatform(tokenPath string) (string, error) {
	data, err := os.ReadFile(tokenPath)
	if err != nil {
		if os.IsNotExist(err) {
			return "", fmt.Errorf("token file not found at %s — run the Mitori install script first", tokenPath)
		}
		return "", fmt.Errorf("failed to read token file %s: %w", tokenPath, err)
	}
	token := trimToken(string(data))
	if token == "" {
		return "", fmt.Errorf("token file at %s is empty", tokenPath)
	}
	return token, nil
}
