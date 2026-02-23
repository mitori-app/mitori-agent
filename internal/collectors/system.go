package collectors

import (
	"fmt"

	"github.com/shirou/gopsutil/v4/host"

	pb "github.com/mitori-app/mitori-agent/internal/proto/gen"
)

// SystemCollector collects system information
type SystemCollector struct{}

// NewSystemCollector creates a new system collector
func NewSystemCollector() *SystemCollector {
	return &SystemCollector{}
}

// Name returns the collector name
func (c *SystemCollector) Name() string {
	return "system"
}

// CollectHostStats gathers host information (hostname, OS, platform, uptime, etc.)
func (c *SystemCollector) CollectHostStats() (*pb.HostStat, error) {
	hostInfo, err := host.Info()
	if err != nil {
		return nil, fmt.Errorf("failed to get host info: %w", err)
	}

	return &pb.HostStat{
		Hostname:        hostInfo.Hostname,
		Uptime:          hostInfo.Uptime,
		Os:              hostInfo.OS,
		Platform:        hostInfo.Platform,
		PlatformVersion: hostInfo.PlatformVersion,
		KernelArch:      hostInfo.KernelArch,
	}, nil
}
