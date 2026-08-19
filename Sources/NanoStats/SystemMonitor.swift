import Foundation
import IOKit
import AppKit

public struct SystemSample {
    public let cpuPercent: Double
    public let gpuPercent: Double
    public let memoryPercent: Double
    public let memoryUsedGB: Double
    public let memoryTotalGB: Double
    public let temperatureCelsius: Double
    public let thermalStateName: String
}

public class SystemMonitor {
    private var lastCpuUser: UInt64 = 0
    private var lastCpuSystem: UInt64 = 0
    private var lastCpuTotal: UInt64 = 0
    private var isFirstCpuSample = true
    
    // Cached IOHIDEventSystemClient for real die-temperature reads (Apple Silicon)
    private var hidClient: CFTypeRef?
    private var hidSymbols: HIDSymbols?
    
    public init() {}
    
    public func poll() -> SystemSample {
        let cpu = pollCPU()
        let gpu = pollGPU()
        let (memPercent, memUsed, memTotal) = pollMemory()
        let (temp, thermalState) = pollThermal()
        
        return SystemSample(
            cpuPercent: cpu,
            gpuPercent: gpu,
            memoryPercent: memPercent,
            memoryUsedGB: memUsed,
            memoryTotalGB: memTotal,
            temperatureCelsius: temp,
            thermalStateName: thermalState
        )
    }
    
    // MARK: - CPU Utilization (host_statistics64)
    private func pollCPU() -> Double {
        var cpuInfo = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else { return 0.0 }
        
        let user = UInt64(cpuInfo.cpu_ticks.0)
        let system = UInt64(cpuInfo.cpu_ticks.1)
        let idle = UInt64(cpuInfo.cpu_ticks.2)
        let nice = UInt64(cpuInfo.cpu_ticks.3)
        
        let totalUser = user + nice
        let totalSystem = system
        let totalIdle = idle
        let total = totalUser + totalSystem + totalIdle
        
        if isFirstCpuSample {
            lastCpuUser = totalUser
            lastCpuSystem = totalSystem
            lastCpuTotal = total
            isFirstCpuSample = false
            return 0.0
        }
        
        let deltaUser = totalUser >= lastCpuUser ? (totalUser - lastCpuUser) : totalUser
        let deltaSystem = totalSystem >= lastCpuSystem ? (totalSystem - lastCpuSystem) : totalSystem
        let deltaTotal = total >= lastCpuTotal ? (total - lastCpuTotal) : total
        
        lastCpuUser = totalUser
        lastCpuSystem = totalSystem
        lastCpuTotal = total
        
        if deltaTotal > 0 {
            let usage = Double(deltaUser + deltaSystem) / Double(deltaTotal) * 100.0
            return min(max(usage, 0.0), 100.0)
        }
        return 0.0
    }
    
    // MARK: - Memory Usage (host_statistics64 VM Info)
    private func pollMemory() -> (percent: Double, usedGB: Double, totalGB: Double) {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let totalGB = Double(totalBytes) / (1024.0 * 1024.0 * 1024.0)
        
        guard result == KERN_SUCCESS else {
            return (0.0, 0.0, totalGB)
        }
        
        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * pageSize
        let wire = UInt64(stats.wire_count) * pageSize
        let compress = UInt64(stats.compressor_page_count) * pageSize
        
        let usedBytes = active + wire + compress
        let usedGB = Double(usedBytes) / (1024.0 * 1024.0 * 1024.0)
        let percent = min(max((usedGB / totalGB) * 100.0, 0.0), 100.0)
        
        return (percent, usedGB, totalGB)
    }
    
    private func pollGPU() -> Double {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        
        let mainPort: mach_port_t
        if #available(macOS 12.0, *) {
            mainPort = kIOMainPortDefault
        } else {
            mainPort = kIOMasterPortDefault
        }
        
        guard IOServiceGetMatchingServices(mainPort, matching, &iterator) == kIOReturnSuccess else {
            return 0.0
        }
        defer { IOObjectRelease(iterator) }
        
        var maxGpuUtil: Double = 0.0
        var service = IOIteratorNext(iterator)
        
        while service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let stats = dict["PerformanceStatistics"] as? [String: Any] {
                
                if let val = stats["Device Utilization %"] as? NSNumber {
                    maxGpuUtil = max(maxGpuUtil, val.doubleValue)
                } else if let val = stats["GPU Activity"] as? NSNumber {
                    maxGpuUtil = max(maxGpuUtil, val.doubleValue)
                } else if let val = stats["Device Utilization"] as? NSNumber {
                    let doubleVal = val.doubleValue
                    maxGpuUtil = max(maxGpuUtil, doubleVal > 1.0 ? doubleVal : doubleVal * 100.0)
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        
        return min(max(maxGpuUtil, 0.0), 100.0)
    }
    
    // MARK: - Temperature & Thermal State
    private func pollThermal() -> (temperatureCelsius: Double, thermalStateName: String) {
        let state = ProcessInfo.processInfo.thermalState
        let stateName: String
        
        switch state {
        case .nominal:
            stateName = "Nominal"
        case .fair:
            stateName = "Fair"
        case .serious:
            stateName = "Serious"
        case .critical:
            stateName = "Critical"
        @unknown default:
            stateName = "Normal"
        }
        
        // Prefer a real die-temperature reading on Apple Silicon; fall back to
        // an estimate from the thermal state when the sensor is unavailable.
        let temp = pollDieTemperature() ?? estimatedTemperature(for: state)
        return (temp, stateName)
    }
    
    private func estimatedTemperature(for state: ProcessInfo.ThermalState) -> Double {
        switch state {
        case .nominal: return 42.0
        case .fair: return 58.0
        case .serious: return 75.0
        case .critical: return 92.0
        @unknown default: return 45.0
        }
    }
    
    // MARK: - Real Die Temperature (IOHIDEventSystemClient, Apple Silicon)
    //
    // Apple Silicon exposes die-temperature sensors through the private
    // IOHIDEventSystemClient API (the same source `powermetrics` uses).
    // Symbols are resolved at runtime via dlopen/dlsym so the app still
    // builds and runs on Intel Macs and older macOS versions.
    private struct HIDSymbols {
        let create: @convention(c) (CFAllocator?) -> CFTypeRef?
        let setMatching: @convention(c) (CFTypeRef?, CFDictionary?) -> Void
        let copyServices: @convention(c) (CFTypeRef?) -> CFArray?
        let copyEvent: @convention(c) (CFTypeRef?, Int64, Int32, Int64) -> CFTypeRef?
        let getFloatValue: @convention(c) (CFTypeRef?, UInt32) -> Double
        let copyProperty: @convention(c) (CFTypeRef?, CFString?) -> CFTypeRef?
    }
    
    private func loadHIDSymbols() -> HIDSymbols? {
        if let cached = hidSymbols { return cached }
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else {
            return nil
        }
        typealias CreateFn = @convention(c) (CFAllocator?) -> CFTypeRef?
        typealias SetMatchingFn = @convention(c) (CFTypeRef?, CFDictionary?) -> Void
        typealias CopyServicesFn = @convention(c) (CFTypeRef?) -> CFArray?
        typealias CopyEventFn = @convention(c) (CFTypeRef?, Int64, Int32, Int64) -> CFTypeRef?
        typealias GetFloatValueFn = @convention(c) (CFTypeRef?, UInt32) -> Double
        typealias CopyPropertyFn = @convention(c) (CFTypeRef?, CFString?) -> CFTypeRef?
        
        guard let createPtr = dlsym(handle, "IOHIDEventSystemClientCreate"),
              let setMatchingPtr = dlsym(handle, "IOHIDEventSystemClientSetMatching"),
              let copyServicesPtr = dlsym(handle, "IOHIDEventSystemClientCopyServices"),
              let copyEventPtr = dlsym(handle, "IOHIDServiceClientCopyEvent"),
              let getFloatValuePtr = dlsym(handle, "IOHIDEventGetFloatValue"),
              let copyPropertyPtr = dlsym(handle, "IOHIDServiceClientCopyProperty") else {
            return nil
        }
        let symbols = HIDSymbols(
            create: unsafeBitCast(createPtr, to: CreateFn.self),
            setMatching: unsafeBitCast(setMatchingPtr, to: SetMatchingFn.self),
            copyServices: unsafeBitCast(copyServicesPtr, to: CopyServicesFn.self),
            copyEvent: unsafeBitCast(copyEventPtr, to: CopyEventFn.self),
            getFloatValue: unsafeBitCast(getFloatValuePtr, to: GetFloatValueFn.self),
            copyProperty: unsafeBitCast(copyPropertyPtr, to: CopyPropertyFn.self)
        )
        hidSymbols = symbols
        return symbols
    }
    
    private func pollDieTemperature() -> Double? {
        guard let symbols = loadHIDSymbols() else { return nil }
        
        let client: CFTypeRef
        if let existing = hidClient {
            client = existing
        } else {
            guard let created = symbols.create(kCFAllocatorDefault) else { return nil }
            hidClient = created
            client = created
        }
        
        // Match the Apple ARM IO device temperature services (page 0xff00, usage 5).
        let matching: CFDictionary = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        symbols.setMatching(client, matching)
        
        guard let services = symbols.copyServices(client) as? [CFTypeRef] else { return nil }
        
        var maxTemp: Double?
        for service in services {
            guard let event = symbols.copyEvent(service, 15, 0, 0) else { continue }
            let value = symbols.getFloatValue(event, UInt32(15 << 16))
            // Keep only plausible die temperatures; ignore uninitialized sensors
            // (some report -22) and non-die sensors like battery or NAND.
            guard value > 0, value < 150 else { continue }
            guard let name = symbols.copyProperty(service, "Product" as CFString) as? String,
                  name.contains("tdie") else { continue }
            maxTemp = max(maxTemp ?? 0, value)
        }
        return maxTemp
    }
}
