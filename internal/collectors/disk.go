package collectors

import (
	"fmt"
	"slices"
	"strings"

	"github.com/shirou/gopsutil/v4/disk"

	pb "github.com/mitori-app/mitori-agent/internal/proto/gen"
)

// DiskCollector collects disk metrics
type DiskCollector struct{}

// NewDiskCollector creates a new disk collector
func NewDiskCollector() *DiskCollector {
	return &DiskCollector{}
}

// Name returns the collector name
func (c *DiskCollector) Name() string {
	return "disk"
}

// CollectDiskStats gathers disk information for all partitions
func (c *DiskCollector) CollectDiskStats() ([]*pb.DiskStat, error) {
	partitions, err := disk.Partitions(false)
	if err != nil {
		return nil, fmt.Errorf("failed to get disk partitions: %w", err)
	}

	var diskStats []*pb.DiskStat

	for _, partition := range partitions {
		// Filter out system volumes and pseudo filesystems
		// macOS specific
		if strings.HasPrefix(partition.Mountpoint, "/System/Volumes") ||
			partition.Mountpoint == "/dev" ||
			partition.Fstype == "devfs" ||
			partition.Fstype == "autofs" ||
			slices.Contains(partition.Opts, "nobrowse") {
			continue
		}

		// Linux pseudo filesystems
		if partition.Fstype == "proc" ||
			partition.Fstype == "sysfs" ||
			partition.Fstype == "tmpfs" ||
			partition.Fstype == "cgroup" ||
			partition.Fstype == "cgroup2" ||
			partition.Fstype == "bpf" ||
			partition.Fstype == "pstore" ||
			partition.Fstype == "debugfs" ||
			partition.Fstype == "tracefs" ||
			partition.Fstype == "configfs" ||
			partition.Fstype == "fusectl" ||
			partition.Fstype == "securityfs" ||
			partition.Fstype == "overlay" ||
			partition.Fstype == "overlayfs" {
			continue
		}

		// Linux special mount points
		if strings.HasPrefix(partition.Mountpoint, "/sys") ||
			strings.HasPrefix(partition.Mountpoint, "/proc") ||
			strings.HasPrefix(partition.Mountpoint, "/run") ||
			strings.HasPrefix(partition.Mountpoint, "/dev") {
			continue
		}

		// Linux loop devices (snaps on Ubuntu)
		if strings.HasPrefix(partition.Device, "/dev/loop") {
			continue
		}

		usage, err := disk.Usage(partition.Mountpoint)
		if err != nil {
			continue // Skip partitions we can't read
		}

		diskStats = append(diskStats, &pb.DiskStat{
			Device:      partition.Device,
			MountPoint:  partition.Mountpoint,
			Fstype:      partition.Fstype,
			Total:       usage.Total,
			Free:        usage.Free,
			UsedPercent: usage.UsedPercent,
		})
	}

	return diskStats, nil
}
