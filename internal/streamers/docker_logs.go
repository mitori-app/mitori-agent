package streamers

import (
	"bufio"
	"context"
	"io"
	"log"
	"sync"
	"time"

	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/client"
)

// DockerLogsStreamer streams logs from all running Docker containers
type DockerLogsStreamer struct {
	client     *client.Client
	ctx        context.Context
	cancel     context.CancelFunc
	wg         sync.WaitGroup
	containers map[string]bool // Track which containers we're streaming
	mu         sync.Mutex
}

// NewDockerLogsStreamer creates a new Docker logs streamer
func NewDockerLogsStreamer() (*DockerLogsStreamer, error) {
	cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		return nil, err
	}

	ctx, cancel := context.WithCancel(context.Background())

	return &DockerLogsStreamer{
		client:     cli,
		ctx:        ctx,
		cancel:     cancel,
		containers: make(map[string]bool),
	}, nil
}

// Name returns the streamer name
func (s *DockerLogsStreamer) Name() string {
	return "docker_logs"
}

// Start begins streaming logs from all running containers
func (s *DockerLogsStreamer) Start(handler LogHandler) error {
	// Start monitoring for new/stopped containers
	go s.monitorContainers(handler)

	return nil
}

// Stop gracefully stops all log streams
func (s *DockerLogsStreamer) Stop() error {
	s.cancel()
	s.wg.Wait()

	if s.client != nil {
		return s.client.Close()
	}

	return nil
}

// monitorContainers periodically checks for new/stopped containers
func (s *DockerLogsStreamer) monitorContainers(handler LogHandler) {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	// Start streaming existing containers immediately
	s.updateContainerStreams(handler)

	for {
		select {
		case <-s.ctx.Done():
			return
		case <-ticker.C:
			s.updateContainerStreams(handler)
		}
	}
}

// updateContainerStreams updates which containers we're streaming from
func (s *DockerLogsStreamer) updateContainerStreams(handler LogHandler) {
	containers, err := s.client.ContainerList(s.ctx, container.ListOptions{})
	if err != nil {
		log.Printf("Error listing containers: %v", err)
		return
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	// Track current running containers
	runningContainers := make(map[string]bool)

	for _, ctr := range containers {
		runningContainers[ctr.ID] = true

		// Start streaming if not already streaming
		if !s.containers[ctr.ID] {
			s.containers[ctr.ID] = true
			s.wg.Add(1)
			go s.streamContainerLogs(ctr.ID, ctr.Names[0], handler)
		}
	}

	// Mark stopped containers (cleanup happens when goroutine exits)
	for id := range s.containers {
		if !runningContainers[id] {
			delete(s.containers, id)
		}
	}
}

// streamContainerLogs streams logs from a single container
func (s *DockerLogsStreamer) streamContainerLogs(containerID, containerName string, handler LogHandler) {
	defer s.wg.Done()

	options := container.LogsOptions{
		ShowStdout: true,
		ShowStderr: true,
		Follow:     true,
		Tail:       "0", // Only new logs (not historical)
		Timestamps: true,
	}

	logs, err := s.client.ContainerLogs(s.ctx, containerID, options)
	if err != nil {
		log.Printf("Error streaming logs for container %s: %v", containerName, err)
		return
	}
	defer logs.Close()

	// Docker multiplexes stdout/stderr, we need to demux
	// For simplicity, we'll just read line by line
	reader := bufio.NewReader(logs)

	for {
		select {
		case <-s.ctx.Done():
			return
		default:
			// Read a line from the log stream
			line, err := reader.ReadString('\n')
			if err != nil {
				if err == io.EOF {
					// Container stopped
					return
				}
				log.Printf("Error reading logs for container %s: %v", containerName, err)
				return
			}

			// Skip Docker's 8-byte header if present
			// Docker log format: [8 bytes header][log line]
			if len(line) > 8 {
				line = line[8:]
			}

			// Send log line to handler
			logLine := LogLine{
				Timestamp:   time.Now().Unix(),
				Source:      "docker",
				ContainerID: containerID[:12], // Short ID
				Message:     line,
				Metadata: map[string]string{
					"container_name": containerName,
					"full_id":        containerID,
				},
			}

			handler(logLine)
		}
	}
}
