package collectors

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"sync"
	"time"

	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/client"

	pb "github.com/mitori-app/mitori-agent/proto/gen"
)

// NetworkStatsSnapshot holds previous network stats for a container
type NetworkStatsSnapshot struct {
	timestamp int64 // Unix timestamp in nanoseconds
	rxBytes   uint64
	txBytes   uint64
}

// DockerCollector collects Docker container metrics
type DockerCollector struct {
	client              *client.Client
	previousNetStats    map[string]map[string]*NetworkStatsSnapshot // containerID -> networkName -> snapshot
	previousNetStatsMux sync.RWMutex
}

// NewDockerCollector creates a new Docker collector
func NewDockerCollector() *DockerCollector {
	// Try to connect to Docker daemon
	cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		// Docker not available, return collector with nil client
		return &DockerCollector{client: nil, previousNetStats: make(map[string]map[string]*NetworkStatsSnapshot)}
	}

	return &DockerCollector{client: cli, previousNetStats: make(map[string]map[string]*NetworkStatsSnapshot)}
}

// Name returns the collector name
func (c *DockerCollector) Name() string {
	return "docker"
}

// CollectDockerStats gathers Docker container metrics
func (c *DockerCollector) CollectDockerStats() ([]*pb.DockerContainer, error) {
	// Check if Docker is available
	if c.client == nil {
		return nil, nil // Return empty list if Docker not available
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// List all containers (running and stopped)
	containers, err := c.client.ContainerList(ctx, container.ListOptions{All: true})
	if err != nil {
		return nil, fmt.Errorf("failed to list containers: %w", err)
	}

	var containerStats []*pb.DockerContainer

	for _, ctr := range containers {
		// Build container metadata from container.Summary
		containerStat := &pb.DockerContainer{
			ContainerId: ctr.ID,
			Names:       ctr.Names,
			Image:       ctr.Image,
			Created:     ctr.Created,
			State:       ctr.State,
			Status:      ctr.Status,
		}
		// Add Mount Points
		for _, mount := range ctr.Mounts {
			containerStat.Mounts = append(containerStat.Mounts, &pb.DockerMountPoint{
				Name:        mount.Name,
				Source:      mount.Source,
				Destination: mount.Destination,
				Driver:      mount.Driver,
			})
		}

		// Add port mappings
		for _, port := range ctr.Ports {
			containerStat.Ports = append(containerStat.Ports, &pb.DockerPort{
				Ip:          port.IP,
				PrivatePort: uint32(port.PrivatePort),
				PublicPort:  uint32(port.PublicPort),
				Type:        port.Type,
			})
		}

		// Get performance stats (only for running containers)
		if ctr.State == "running" {
			stats, err := c.client.ContainerStats(ctx, ctr.ID, false)
			if err == nil {
				// Decode stats JSON
				var statsJSON container.StatsResponse
				statsData, err := io.ReadAll(stats.Body)
				stats.Body.Close()

				if err == nil && json.Unmarshal(statsData, &statsJSON) == nil {
					// Add CPU stats
					containerStat.CpuStats = &pb.DockerCPUStats{
						CpuUsage: &pb.DockerCPUUsage{
							TotalUsage: statsJSON.CPUStats.CPUUsage.TotalUsage,
						},
						SystemCpuUsage: statsJSON.CPUStats.SystemUsage,
						OnlineCpus:     statsJSON.CPUStats.OnlineCPUs,
					}

					// Add memory stats
					containerStat.MemoryStats = &pb.DockerMemoryStats{
						Usage: statsJSON.MemoryStats.Usage,
						Limit: statsJSON.MemoryStats.Limit,
					}

					// Add network stats
					containerStat.Networks = make(map[string]*pb.DockerNetworkStats)
					currentTime := time.Now().UnixNano()

					// Ensure container entry exists in previousNetStats
					c.previousNetStatsMux.Lock()
					if _, exists := c.previousNetStats[ctr.ID]; !exists {
						c.previousNetStats[ctr.ID] = make(map[string]*NetworkStatsSnapshot)
					}

					for netName, netStats := range statsJSON.Networks {
						dockerNetStats := &pb.DockerNetworkStats{}

						// Calculate bytes per second if we have previous stats
						if prevSnapshot, exists := c.previousNetStats[ctr.ID][netName]; exists {
							timeDeltaNano := currentTime - prevSnapshot.timestamp
							if timeDeltaNano > 0 {
								timeDeltaSec := float64(timeDeltaNano) / 1e9

								rxDelta := int64(netStats.RxBytes) - int64(prevSnapshot.rxBytes)
								if rxDelta > 0 {
									dockerNetStats.RxBytesPerSec = float64(rxDelta) / timeDeltaSec
								}

								txDelta := int64(netStats.TxBytes) - int64(prevSnapshot.txBytes)
								if txDelta > 0 {
									dockerNetStats.TxBytesPerSec = float64(txDelta) / timeDeltaSec
								}
							}
						}

						// Update snapshot for next collection
						c.previousNetStats[ctr.ID][netName] = &NetworkStatsSnapshot{
							timestamp: currentTime,
							rxBytes:   netStats.RxBytes,
							txBytes:   netStats.TxBytes,
						}

						containerStat.Networks[netName] = dockerNetStats
					}
					c.previousNetStatsMux.Unlock()
				}
			}
		}

		containerStats = append(containerStats, containerStat)
	}

	return containerStats, nil
}
