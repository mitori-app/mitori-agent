//go:build linux

package config

func platformConfigPath() (configPath, tokenPath string) {
	return "/etc/mitori/config.yaml", "/etc/mitori/token"
}
