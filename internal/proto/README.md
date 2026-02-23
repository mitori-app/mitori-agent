# Mitori Protocol Buffers

Shared Protocol Buffer definitions for communication between Agent and Ingestor.

## Setup

### Prerequisites

1. **Install protoc** (Protocol Buffer compiler):
   ```bash
   # macOS
   brew install protobuf

   # Linux
   apt-get install protobuf-compiler

   # Verify installation
   protoc --version  # Should be 3.x or higher
   ```

2. **Install Go protobuf plugin** (auto-installed by generate.sh):
   ```bash
   go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
   ```

## Generating Code

```bash
# From packages/proto directory
pnpm generate

# Or directly
./generate.sh
```

This will generate Go code in `gen/mitori.pb.go`.

## Usage in Go Services

### Agent
```go
import pb "mitori/packages/proto/gen"

msg := &pb.AgentMessage{
    AgentVersion: "1.0.0",
    ServerId: "server-123",
    Timestamp: time.Now().Unix(),
    Payload: &pb.AgentMessage_Metrics{
        Metrics: &pb.MetricBatch{...},
    },
}

// Serialize to binary
data, err := proto.Marshal(msg)

// Deserialize from binary
var received pb.AgentMessage
err := proto.Unmarshal(data, &received)
```

### Ingestor
```go
import pb "mitori/packages/proto/gen"

// Receive message from WebSocket
var msg pb.AgentMessage
err := proto.Unmarshal(data, &msg)

// Handle different payload types
switch p := msg.Payload.(type) {
case *pb.AgentMessage_Registration:
    handleRegistration(p.Registration)
case *pb.AgentMessage_Metrics:
    handleMetrics(msg.ServerId, p.Metrics)
case *pb.AgentMessage_Logs:
    handleLogs(msg.ServerId, p.Logs)
}
```

## Schema Versioning

**Important Rules for Backward Compatibility:**

1. ✅ **NEVER** change field numbers
2. ✅ **NEVER** reuse field numbers
3. ✅ **DO** add new fields (old code will ignore them)
4. ✅ **DO** use `reserved` for deleted fields
5. ✅ **DO** include `agent_version` in messages

Example:
```protobuf
message Example {
  string field1 = 1;  // NEVER change this number

  // To delete a field:
  // reserved 2;  // Don't reuse field 2

  string new_field = 3;  // Safe to add
}
```
