import SwiftUI

/// Animated circular progress ring with Apple Music spatial audio style glowing halo
public struct ProgressRing: View {
    @Environment(\.colorScheme) private var colorScheme
    public let progress: Double
    public let iconName: String
    public let tintColor: Color
    
    public init(progress: Double, iconName: String, tintColor: Color) {
        self.progress = progress
        self.iconName = iconName
        self.tintColor = tintColor
    }
    
    public var body: some View {
        let isDark = colorScheme == .dark
        
        ZStack {
            // Ambient spatial glow halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            tintColor.opacity(isDark ? 0.35 : 0.20),
                            Color.purple.opacity(isDark ? 0.15 : 0.08),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 100
                    )
                )
                .frame(width: 200, height: 200)
            
            // Track background
            Circle()
                .stroke(lineWidth: 8)
                .foregroundStyle(isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                .frame(width: 150, height: 150)
            
            // Glowing progress arc
            Circle()
                .trim(from: 0, to: max(0.01, min(1.0, progress)))
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(red: 0.98, green: 0.14, blue: 0.24), // Apple Music Red
                            Color(red: 0.66, green: 0.13, blue: 0.84), // Purple
                            Color(red: 0.0, green: 0.78, blue: 0.75),  // Cyan
                            Color(red: 0.98, green: 0.14, blue: 0.24)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 150, height: 150)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.25), value: progress)
            
            // Center info
            VStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(tintColor)
                
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }
        }
    }
}
