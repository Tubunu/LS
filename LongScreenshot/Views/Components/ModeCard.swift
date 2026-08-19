import SwiftUI

/// Mode selection hero card designed with Apple Music artwork card aesthetics
public struct ModeCard: View {
    @Environment(\.colorScheme) private var colorScheme
    public let modeNumber: String
    public let icon: String
    public let title: String
    public let subtitle: String
    public let actionText: String
    public let gradientColors: [Color]
    
    public init(
        modeNumber: String = "MODE 01",
        icon: String,
        title: String,
        subtitle: String,
        actionText: String = "开始拼接",
        gradientColors: [Color]
    ) {
        self.modeNumber = modeNumber
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.actionText = actionText
        self.gradientColors = gradientColors
    }
    
    public var body: some View {
        let isDark = colorScheme == .dark
        
        VStack(alignment: .leading, spacing: 18) {
            // Top icon & action badge pill
            HStack {
                // Glass icon container
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(isDark ? 0.22 : 0.3))
                    
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.white)
                }
                .frame(width: 50, height: 50)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                }
                
                Spacer()
                
                // Action Pill Badge
                HStack(spacing: 4) {
                    Text(actionText)
                        .font(.system(size: 12, weight: .bold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.white)
                .clipShape(Capsule())
                .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 3)
            }
            
            // Bottom text area
            VStack(alignment: .leading, spacing: 4) {
                Text(modeNumber)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Color.white.opacity(0.8))
                
                Text(title)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .background {
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.55),
                            .white.opacity(0.2),
                            .clear,
                            .white.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(
            color: gradientColors.first?.opacity(isDark ? 0.35 : 0.25) ?? Color.black.opacity(0.2),
            radius: 18,
            x: 0,
            y: 8
        )
    }
}
