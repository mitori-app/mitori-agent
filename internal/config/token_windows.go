//go:build windows

package config

import (
	"fmt"

	keyring "github.com/zalando/go-keyring"
)

const (
	keyringService  = "mitori-agent"
	keyringUsername = "host-token"
)

// readTokenPlatform retrieves the host token from Windows Credential Manager.
// The token is stored there by the install script via cmdkey.
// go-keyring reads Generic credentials using "<service>/<username>" as the target name.
func readTokenPlatform(_ string) (string, error) {
	token, err := keyring.Get(keyringService, keyringUsername)
	if err != nil {
		if err == keyring.ErrNotFound {
			return "", fmt.Errorf("host token not found in Windows Credential Manager (service=%q, user=%q) — run the Mitori install script first", keyringService, keyringUsername)
		}
		return "", fmt.Errorf("failed to retrieve token from Windows Credential Manager: %w", err)
	}
	token = trimToken(token)
	if token == "" {
		return "", fmt.Errorf("host token in Windows Credential Manager is empty")
	}
	return token, nil
}
