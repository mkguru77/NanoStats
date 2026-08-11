import AppKit

public class IconProvider {
    /// SF Symbol for App Icon / Menu Bar fallback
    public static var mainAppIcon: NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = (NSImage(systemSymbolName: "gauge.with.dots.needle.bottom.50percent", accessibilityDescription: "NanoStats")
                    ?? NSImage(systemSymbolName: "cpu", accessibilityDescription: "NanoStats"))?.withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }
    
    private static let stackedFont = NSFont.monospacedDigitSystemFont(ofSize: 9.0, weight: .bold)
    private static let paragraphStyle: NSMutableParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        return style
    }()
    private static let stackedAttrs: [NSAttributedString.Key: Any] = [
        .font: stackedFont,
        .foregroundColor: NSColor.black,
        .paragraphStyle: paragraphStyle
    ]
    
    /// Renders a dynamic multi-metric image for enabled metrics in user-specified order
    public static func renderMetricsImage(
        enabledMetrics: [MetricType],
        upStr: String,
        downStr: String,
        cpuPercent: Double,
        gpuPercent: Double,
        memPercent: Double,
        tempCelsius: Double
    ) -> NSImage {
        guard !enabledMetrics.isEmpty else {
            return mainAppIcon ?? NSImage()
        }
        
        struct RenderBlock {
            let topString: NSAttributedString
            let bottomString: NSAttributedString
            let width: CGFloat
        }
        
        var blocks: [RenderBlock] = []
        let gap: CGFloat = 8.0
        var totalWidth: CGFloat = 0.0
        
        for metric in enabledMetrics {
            let topText: String
            let bottomText: String
            
            switch metric {
            case .network:
                topText = "▲ \(upStr)"
                bottomText = "▼ \(downStr)"
            case .cpu:
                topText = "CPU"
                bottomText = String(format: "%.0f%%", cpuPercent)
            case .gpu:
                topText = "GPU"
                bottomText = String(format: "%.0f%%", gpuPercent)
            case .memory:
                topText = "RAM"
                bottomText = String(format: "%.0f%%", memPercent)
            case .temperature:
                topText = "TEMP"
                bottomText = String(format: "%.0f°C", tempCelsius)
            }
            
            let upAttr = NSAttributedString(string: topText, attributes: stackedAttrs)
            let downAttr = NSAttributedString(string: bottomText, attributes: stackedAttrs)
            
            let w = max(upAttr.size().width, downAttr.size().width)
            let blockWidth = ceil(w + 1.0)
            
            blocks.append(RenderBlock(topString: upAttr, bottomString: downAttr, width: blockWidth))
            totalWidth += blockWidth
        }
        
        totalWidth += CGFloat(blocks.count - 1) * gap
        let totalHeight: CGFloat = 22.0
        
        let image = NSImage(size: NSMakeSize(max(totalWidth, 1.0), totalHeight))
        image.lockFocus()
        
        var currentX: CGFloat = 0.0
        for block in blocks {
            block.topString.draw(at: NSMakePoint(currentX, 11.5))
            block.bottomString.draw(at: NSMakePoint(currentX, 0.5))
            currentX += block.width + gap
        }
        
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
