package client

import (
	"bytes"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"time"

	"google.golang.org/protobuf/proto"

	pb "github.com/mitori-app/mitori-agent/proto/gen"
)

// HTTPClient sends protobuf messages to the ingestor via HTTP POST
type HTTPClient struct {
	url        string
	token      string
	httpClient *http.Client
}

// NewHTTPClient creates a new HTTP client for sending protobuf messages.
// token is sent as a Bearer token in the Authorization header on every request.
func NewHTTPClient(url, token string) *HTTPClient {
	return &HTTPClient{
		url:   url,
		token: token,
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

// SendProto sends a protobuf message via HTTP POST
func (c *HTTPClient) SendProto(msg *pb.AgentMessage) error {
	// Marshal protobuf to binary
	data, err := proto.Marshal(msg)
	if err != nil {
		return fmt.Errorf("failed to marshal protobuf: %w", err)
	}

	slog.Debug("Sending protobuf payload", "bytes", len(data))

	// Create HTTP POST request
	req, err := http.NewRequest("POST", c.url, bytes.NewReader(data))
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	// Set content type for protobuf
	req.Header.Set("Content-Type", "application/x-protobuf")
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}

	// Send request
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	// Check response status
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("server returned status %d: %s", resp.StatusCode, string(body))
	}

	return nil
}

// Close is a no-op for HTTP client (for compatibility with WebSocket client interface)
func (c *HTTPClient) Close() error {
	return nil
}
