package main

import (
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/mitori-app/mitori-agent/internal/client"
	"github.com/mitori-app/mitori-agent/internal/collectors"
	"github.com/mitori-app/mitori-agent/internal/config"

	pb "github.com/mitori-app/mitori-agent/internal/proto/gen"
)

const (
	snapshotInterval = 15 * time.Second
	agentVersion     = "1.0.0"
)

func main() {
	var handler slog.Handler
	opts := &slog.HandlerOptions{Level: slog.LevelInfo}
	if os.Getenv("LOG_FORMAT") == "text" {
		handler = slog.NewTextHandler(os.Stdout, opts)
	} else {
		handler = slog.NewJSONHandler(os.Stdout, opts)
	}
	slog.SetDefault(slog.New(handler))

	slog.Info("Mitori agent starting", "version", agentVersion)

	// Load config + token from platform-specific paths
	cfg, err := config.Load()
	if err != nil {
		slog.Error("Failed to load config", "error", err)
		os.Exit(1)
	}
	slog.Info("Config loaded", "host_id", cfg.HostID, "ingestor", cfg.IngestorURL)

	// Create HTTP client
	httpClient := client.NewHTTPClient(cfg.IngestorURL, cfg.HostAPIKey)
	defer httpClient.Close()

	// Initialize collectors
	cpuCollector := collectors.NewCPUCollector()
	memoryCollector := collectors.NewMemoryCollector()
	diskCollector := collectors.NewDiskCollector()
	networkCollector := collectors.NewNetworkCollector()
	systemCollector := collectors.NewSystemCollector()
	dockerCollector := collectors.NewDockerCollector()

	// Handle graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)

	// Send initial snapshot on startup
	sendSnapshot(cfg.HostID, httpClient, systemCollector, cpuCollector, memoryCollector, diskCollector, networkCollector, dockerCollector)

	// Create ticker for snapshots
	snapshotTicker := time.NewTicker(snapshotInterval)
	defer snapshotTicker.Stop()

	for {
		select {
		case <-sigChan:
			slog.Info("Shutting down")
			os.Exit(0)

		case <-snapshotTicker.C:
			sendSnapshot(cfg.HostID, httpClient, systemCollector, cpuCollector, memoryCollector, diskCollector, networkCollector, dockerCollector)
		}
	}
}

func sendSnapshot(
	hostID string,
	httpClient *client.HTTPClient,
	systemCollector *collectors.SystemCollector,
	cpuCollector *collectors.CPUCollector,
	memoryCollector *collectors.MemoryCollector,
	diskCollector *collectors.DiskCollector,
	networkCollector *collectors.NetworkCollector,
	dockerCollector *collectors.DockerCollector,
) {
	// Create the system snapshot
	snapshot := &pb.SystemSnapshot{}

	// Collect host stats
	hostStat, err := systemCollector.CollectHostStats()
	if err != nil {
		slog.Error("Failed to collect host stats", "error", err)
		return
	}
	snapshot.HostStat = hostStat

	// Collect CPU stats (static metadata)
	cpuStats, err := cpuCollector.CollectCPUStats()
	if err != nil {
		slog.Warn("Failed to collect CPU stats", "error", err)
	} else {
		snapshot.CpuStats = cpuStats
	}

	// Collect CPU time stats (per-core usage)
	cpuTimeStats, err := cpuCollector.CollectCPUTimeStats()
	if err != nil {
		slog.Warn("Failed to collect CPU time stats", "error", err)
	} else {
		snapshot.CpuTimeStats = cpuTimeStats
	}

	// Collect CPU combined stats
	cpuCombinedStats, err := cpuCollector.CollectCPUCombinedStats()
	if err != nil {
		slog.Warn("Failed to collect CPU combined stats", "error", err)
	} else {
		snapshot.CpuCombinedStats = cpuCombinedStats
	}

	// Collect memory stats
	memoryStats, err := memoryCollector.CollectMemoryStats()
	if err != nil {
		slog.Warn("Failed to collect memory stats", "error", err)
	} else {
		snapshot.MemoryStats = memoryStats
	}

	// Collect disk stats
	diskStats, err := diskCollector.CollectDiskStats()
	if err != nil {
		slog.Warn("Failed to collect disk stats", "error", err)
	} else {
		snapshot.DiskStats = diskStats
	}

	// Collect network interface stats
	networkStats, err := networkCollector.CollectNetworkInterfaceStats()
	if err != nil {
		slog.Warn("Failed to collect network stats", "error", err)
	} else {
		snapshot.NetworkInterfaceStats = networkStats
	}

	// Collect Docker container stats
	dockerStats, err := dockerCollector.CollectDockerStats()
	if err != nil {
		slog.Warn("Failed to collect Docker stats", "error", err)
	} else if dockerStats != nil {
		snapshot.DockerContainers = dockerStats
	}

	// Build AgentMessage
	agentMsg := &pb.AgentMessage{
		AgentVersion: agentVersion,
		HostId:       hostID,
		Payload: &pb.AgentMessage_SystemSnapshot{
			SystemSnapshot: snapshot,
		},
	}

	// Send protobuf message via HTTP
	if err = httpClient.SendProto(agentMsg); err != nil {
		slog.Error("Failed to send snapshot", "error", err)
		return
	}

	slog.Info("Snapshot sent",
		"hostname", hostStat.Hostname,
		"os", hostStat.Os,
		"cpus", len(cpuStats),
		"cpu_cores", len(cpuTimeStats),
		"disks", len(diskStats),
		"network_interfaces", len(networkStats),
		"containers", len(dockerStats),
	)
}
