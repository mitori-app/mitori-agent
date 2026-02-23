package streamers

// LogLine represents a single log entry
type LogLine struct {
	Timestamp   int64             `json:"timestamp"`
	Source      string            `json:"source"`       // e.g., "docker", "syslog"
	ContainerID string            `json:"container_id"` // For Docker logs
	Message     string            `json:"message"`
	Metadata    map[string]string `json:"metadata"`
}

// LogHandler is a callback function that processes log lines
type LogHandler func(LogLine)

// Streamer defines the interface for log streamers
type Streamer interface {
	// Start begins streaming logs
	Start(handler LogHandler) error

	// Stop gracefully stops the streamer
	Stop() error

	// Name returns the streamer's identifier
	Name() string
}
