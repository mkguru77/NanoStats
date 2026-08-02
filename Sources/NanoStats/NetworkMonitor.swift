import Foundation
import SystemConfiguration

public struct NetworkInterfaceInfo: Hashable, Identifiable {
    public var id: String { name }
    public let name: String
    public let ipAddress: String?
    public let isPrimary: Bool
}

public struct SpeedSample {
    public let downloadSpeedBytesPerSec: Double
    public let uploadSpeedBytesPerSec: Double
    public let sessionDownloadedBytes: UInt64
    public let sessionUploadedBytes: UInt64
    public let activeInterfaceName: String
}

public class NetworkMonitor {
    private var lastBytesIn: UInt64 = 0
    private var lastBytesOut: UInt64 = 0
    private var lastPollTime: Date?
    
    private var initialSessionBytesIn: UInt64 = 0
    private var initialSessionBytesOut: UInt64 = 0
    private var isFirstPoll: Bool = true
    
    public init() {}
    
    /// Resets session statistics.
    public func resetSession() {
        isFirstPoll = true
    }
    
    /// Returns current network statistics by querying POSIX `getifaddrs`.
    public func poll(selectedInterface: String = "auto") -> SpeedSample {
        let now = Date()
        let (rawIn, rawOut, detectedInterface) = fetchRawBytes(targetInterface: selectedInterface)
        
        if isFirstPoll {
            lastBytesIn = rawIn
            lastBytesOut = rawOut
            initialSessionBytesIn = rawIn
            initialSessionBytesOut = rawOut
            lastPollTime = now
            isFirstPoll = false
            return SpeedSample(
                downloadSpeedBytesPerSec: 0,
                uploadSpeedBytesPerSec: 0,
                sessionDownloadedBytes: 0,
                sessionUploadedBytes: 0,
                activeInterfaceName: detectedInterface
            )
        }
        
        let timeDelta = now.timeIntervalSince(lastPollTime ?? now)
        let effectiveTime = timeDelta > 0 ? timeDelta : 1.0
        
        // Calculate byte deltas with handling for counter reset / overflow
        let deltaIn: UInt64 = rawIn >= lastBytesIn ? (rawIn - lastBytesIn) : rawIn
        let deltaOut: UInt64 = rawOut >= lastBytesOut ? (rawOut - lastBytesOut) : rawOut
        
        let downSpeed = Double(deltaIn) / effectiveTime
        let upSpeed = Double(deltaOut) / effectiveTime
        
        let sessionIn = rawIn >= initialSessionBytesIn ? (rawIn - initialSessionBytesIn) : rawIn
        let sessionOut = rawOut >= initialSessionBytesOut ? (rawOut - initialSessionBytesOut) : rawOut
        
        lastBytesIn = rawIn
        lastBytesOut = rawOut
        lastPollTime = now
        
        return SpeedSample(
            downloadSpeedBytesPerSec: downSpeed,
            uploadSpeedBytesPerSec: upSpeed,
            sessionDownloadedBytes: sessionIn,
            sessionUploadedBytes: sessionOut,
            activeInterfaceName: detectedInterface
        )
    }
    
    /// Fetches total bytes in & out across interfaces using getifaddrs
    private func fetchRawBytes(targetInterface: String) -> (bytesIn: UInt64, bytesOut: UInt64, interfaceName: String) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return (0, 0, "N/A")
        }
        defer { freeifaddrs(ifaddr) }
        
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var primaryName = "en0"
        
        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            
            let flags = Int32(current.pointee.ifa_flags)
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            let isUp = (flags & IFF_UP) != 0
            
            guard isUp && !isLoopback, let addr = current.pointee.ifa_addr else { continue }
            let name = String(cString: current.pointee.ifa_name)
            let family = addr.pointee.sa_family
            
            if family == UInt8(AF_LINK), let data = current.pointee.ifa_data {
                let ifData = data.assumingMemoryBound(to: if_data.self).pointee
                let ibytes = UInt64(ifData.ifi_ibytes)
                let obytes = UInt64(ifData.ifi_obytes)
                
                if targetInterface == "auto" {
                    if name.hasPrefix("en") || name.hasPrefix("utun") {
                        totalIn += ibytes
                        totalOut += obytes
                        if name == "en0" { primaryName = name }
                    }
                } else if name == targetInterface {
                    totalIn = ibytes
                    totalOut = obytes
                    primaryName = name
                    break
                }
            }
        }
        
        let interfaceLabel = targetInterface == "auto" ? "Auto (\(primaryName))" : targetInterface
        return (totalIn, totalOut, interfaceLabel)
    }
    
    /// Returns a list of active network interfaces with IPv4 addresses
    public func getActiveInterfaces() -> [NetworkInterfaceInfo] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return []
        }
        defer { freeifaddrs(ifaddr) }
        
        var interfacesMap: [String: String] = [:]
        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            
            let flags = Int32(current.pointee.ifa_flags)
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            let isUp = (flags & IFF_UP) != 0
            
            guard isUp && !isLoopback, let addr = current.pointee.ifa_addr else { continue }
            let name = String(cString: current.pointee.ifa_name)
            let family = addr.pointee.sa_family
            
            if family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    interfacesMap[name] = String(cString: hostname)
                }
            }
        }
        
        return interfacesMap.map { name, ip in
            NetworkInterfaceInfo(
                name: name,
                ipAddress: ip,
                isPrimary: name == "en0"
            )
        }.sorted { $0.name < $1.name }
    }
}
