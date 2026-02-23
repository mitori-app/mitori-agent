package collectors

import (
	"fmt"
	"net/netip"
	"strings"
	"time"

	"github.com/shirou/gopsutil/v4/net"

	pb "github.com/mitori-app/mitori-agent/proto/gen"
)

// NetworkCollector collects network metrics
type NetworkCollector struct {
	previousCounters map[string]net.IOCountersStat
	previousTime     time.Time
}

// NewNetworkCollector creates a new network collector
func NewNetworkCollector() *NetworkCollector {
	return &NetworkCollector{
		previousCounters: make(map[string]net.IOCountersStat),
		previousTime:     time.Now(),
	}
}

// Name returns the collector name
func (c *NetworkCollector) Name() string {
	return "network"
}

// shouldFilterInterface determines if a network interface should be excluded
func shouldFilterInterface(name string) bool {
	// Loopback
	if name == "lo" || name == "lo0" {
		return true
	}

	// macOS virtual interfaces
	if strings.HasPrefix(name, "gif") ||
		strings.HasPrefix(name, "stf") ||
		strings.HasPrefix(name, "utun") ||
		strings.HasPrefix(name, "awdl") ||
		strings.HasPrefix(name, "llw") ||
		strings.HasPrefix(name, "bridge") ||
		strings.HasPrefix(name, "anpi") ||
		strings.HasPrefix(name, "ap") {
		return true
	}

	// Linux virtual interfaces
	if strings.HasPrefix(name, "docker") ||
		strings.HasPrefix(name, "veth") ||
		strings.HasPrefix(name, "br-") ||
		strings.HasPrefix(name, "virbr") {
		return true
	}

	// Windows virtual interfaces
	if strings.Contains(name, "vEthernet") ||
		strings.Contains(name, "Pseudo") {
		return true
	}

	return false
}

// CollectNetworkInterfaceStats gathers network interface information with rates
func (c *NetworkCollector) CollectNetworkInterfaceStats() ([]*pb.NetworkInterfaceStat, error) {
	// Get network interfaces metadata
	interfaces, err := net.Interfaces()
	if err != nil {
		return nil, fmt.Errorf("failed to get network interfaces: %w", err)
	}

	// Create a map of interface metadata by name
	interfaceMap := make(map[string]net.InterfaceStat)
	for _, iface := range interfaces {
		interfaceMap[iface.Name] = iface
	}

	// Get I/O counters per NIC
	now := time.Now()
	ioCounters, err := net.IOCounters(true)
	if err != nil {
		return nil, fmt.Errorf("failed to get network counters: %w", err)
	}

	var networkStats []*pb.NetworkInterfaceStat
	timeDelta := now.Sub(c.previousTime).Seconds()

	for _, counter := range ioCounters {
		// Filter out virtual/system interfaces
		if shouldFilterInterface(counter.Name) {
			continue
		}

		// Get interface metadata if available
		iface, hasMetadata := interfaceMap[counter.Name]

		// Calculate rates if we have previous data
		var bytesSentPerSec, bytesRecvPerSec float64
		if prev, exists := c.previousCounters[counter.Name]; exists && timeDelta > 0 {
			bytesSentPerSec = float64(counter.BytesSent-prev.BytesSent) / timeDelta
			bytesRecvPerSec = float64(counter.BytesRecv-prev.BytesRecv) / timeDelta
		}

		stat := &pb.NetworkInterfaceStat{
			Name:            counter.Name,
			BytesSentPerSec: bytesSentPerSec,
			BytesRecvPerSec: bytesRecvPerSec,
		}

		// Add interface metadata if available
		if hasMetadata {
			stat.Index = int32(iface.Index)
			stat.Mtu = int32(iface.MTU)

			// Filter for IPv4 addresses only
			var ipv4Addrs []string
			for _, addr := range iface.Addrs {
				// Parse the address (format: "192.168.1.1/24" or "fe80::1/64")
				prefix, err := netip.ParsePrefix(addr.Addr)
				if err != nil {
					continue
				}

				// Only include IPv4 addresses
				if prefix.Addr().Is4() {
					ipv4Addrs = append(ipv4Addrs, addr.Addr)
				}
			}

			// Skip interfaces without IPv4 addresses
			if len(ipv4Addrs) == 0 {
				continue
			}

			stat.Addrs = ipv4Addrs
		}

		networkStats = append(networkStats, stat)

		// Store current counter for next calculation
		c.previousCounters[counter.Name] = counter
	}

	c.previousTime = now
	return networkStats, nil
}
