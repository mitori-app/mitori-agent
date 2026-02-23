//go:build darwin

package config

func platformConfigPath() (configPath, tokenPath string) {
	return "/Library/Application Support/Mitori/config.yaml",
		"/Library/Application Support/Mitori/token"
}
