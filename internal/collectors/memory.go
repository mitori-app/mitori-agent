package collectors

import (
	"fmt"

	"github.com/shirou/gopsutil/v4/mem"

	pb "github.com/mitori-app/mitori-agent/internal/proto/gen"
)

// MemoryCollector collects memory metrics
type MemoryCollector struct{}

// NewMemoryCollector creates a new memory collector
func NewMemoryCollector() *MemoryCollector {
	return &MemoryCollector{}
}

// Name returns the collector name
func (c *MemoryCollector) Name() string {
	return "memory"
}

// CollectMemoryStats gathers memory information
func (c *MemoryCollector) CollectMemoryStats() (*pb.MemoryStat, error) {
	vmStat, err := mem.VirtualMemory()
	if err != nil {
		return nil, fmt.Errorf("failed to get memory stats: %w", err)
	}

	return &pb.MemoryStat{
		Total:       vmStat.Total,
		Available:   vmStat.Available,
		UsedPercent: vmStat.UsedPercent,
	}, nil
}
