import Foundation

public enum MetricType: String, CaseIterable, Codable, Identifiable {
    case temperature = "temperature"
    case memory = "memory"
    case gpu = "gpu"
    case cpu = "cpu"
    case network = "network"
    
    public var id: String { rawValue }
    
    public static let defaultOrder: [MetricType] = [.temperature, .memory, .gpu, .cpu, .network]
    
    public var displayName: String {
        switch self {
        case .network: return "Network Speed"
        case .cpu: return "CPU Usage"
        case .gpu: return "GPU Usage"
        case .memory: return "Memory Usage"
        case .temperature: return "Temperature"
        }
    }
    
    public var shortLabel: String {
        switch self {
        case .network: return "NET"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "RAM"
        case .temperature: return "TEMP"
        }
    }
}
