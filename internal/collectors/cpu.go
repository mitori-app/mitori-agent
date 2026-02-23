package collectors

import (
	"fmt"

	"github.com/shirou/gopsutil/v4/cpu"

	pb "github.com/mitori-app/mitori-agent/proto/gen"
)

// CPUCollector collects CPU metrics
type CPUCollector struct{}

// NewCPUCollector creates a new CPU collector
func NewCPUCollector() *CPUCollector {
	return &CPUCollector{}
}

// Name returns the collector name
func (c *CPUCollector) Name() string {
	return "cpu"
}

// CollectCPUStats gathers CPU static information
func (c *CPUCollector) CollectCPUStats() ([]*pb.CPUStat, error) {
	infos, err := cpu.Info()
	if err != nil {
		return nil, fmt.Errorf("failed to get cpu info: %w", err)
	}

	var cpuStats []*pb.CPUStat
	for _, cpuInfo := range infos {
		cpuStats = append(cpuStats, &pb.CPUStat{
			CpuId:     cpuInfo.CPU,
			VendorId:  cpuInfo.VendorID,
			Family:    cpuInfo.Family,
			Model:     cpuInfo.Model,
			Cores:     cpuInfo.Cores,
			ModelName: cpuInfo.ModelName,
			Mhz:       cpuInfo.Mhz,
		})
	}

	return cpuStats, nil
}

// CollectCPUTimeStats gathers per-core CPU usage percentages
func (c *CPUCollector) CollectCPUTimeStats() ([]*pb.CPUTimeStat, error) {
	// Get per-CPU percentages
	perCPUPercents, err := cpu.Percent(0, true)
	if err != nil {
		return nil, fmt.Errorf("failed to get per-cpu percent: %w", err)
	}

	// Get CPU times to get the CPU names/IDs
	cpuTimes, err := cpu.Times(true)
	if err != nil {
		return nil, fmt.Errorf("failed to get cpu times: %w", err)
	}

	// They should return the same length
	if len(perCPUPercents) != len(cpuTimes) {
		return nil, fmt.Errorf("cpu percent count (%d) does not match cpu times count (%d)", len(perCPUPercents), len(cpuTimes))
	}

	var cpuTimeStats []*pb.CPUTimeStat
	for i, percent := range perCPUPercents {
		cpuTimeStats = append(cpuTimeStats, &pb.CPUTimeStat{
			CpuId:   cpuTimes[i].CPU,
			Percent: percent,
		})
	}

	return cpuTimeStats, nil
}

// CollectCPUTimeStats gathers per-core CPU usage percentages
func (c *CPUCollector) CollectCPUCombinedStats() (*pb.CPUCombinedStat, error) {
	cpuPercent, err := cpu.Percent(0, false)
	if err != nil {
		return nil, fmt.Errorf("failed to get per-cpu percent: %w", err)
	}

	cpuCombinedStat := &pb.CPUCombinedStat{
		CpuTotalPercent: cpuPercent[0],
	}

	return cpuCombinedStat, nil
}
