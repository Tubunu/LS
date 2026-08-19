import SwiftUI

/// Glass effect style configuration representing iOS 26 Liquid Glass and Apple Music vibrancy
public struct GlassStyleConfig {
    public var material: Material
    public var isInteractive: Bool
    public var tintColor: Color?
    public var opacity: Double
    
    public init(
        material: Material = .ultraThinMaterial,
        isInteractive: Bool = false,
        tintColor: Color? = nil,
        opacity: Double = 0.85
    ) {
        self.material = material
        self.isInteractive = isInteractive
        self.tintColor = tintColor
        self.opacity = opacity
    }
    
    public static var regular: GlassStyleConfig {
        GlassStyleConfig(material: .regularMaterial, isInteractive: false)
    }
    
    public static var thin: GlassStyleConfig {
        GlassStyleConfig(material: .thinMaterial, isInteractive: false)
    }
    
    public static var ultraThin: GlassStyleConfig {
        GlassStyleConfig(material: .ultraThinMaterial, isInteractive: false)
    }
    
    public var interactive: GlassStyleConfig {
        var copy = self
        copy.isInteractive = true
        return copy
    }
    
    public func tint(_ color: Color) -> GlassStyleConfig {
        var copy = self
        copy.tintColor = color
        return copy
    }
}

public enum GlassShapeType {
    case rect(cornerRadius: CGFloat)
    case capsule
    case circle
}

public struct GlassEffectModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    public let config: GlassStyleConfig
    public let shapeType: GlassShapeType
    
    public init(config: GlassStyleConfig = .regular, shapeType: GlassShapeType = .rect(cornerRadius: 16)) {
        self.config = config
        self.shapeType = shapeType
    }
    
    public func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        
        switch shapeType {
        case .rect(let radius):
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            content
                .background {
                    glassBackground(shape: shape, isDark: isDark)
                }
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: isDark ? [
                                .white.opacity(0.35),
                                .white.opacity(0.12),
                                .clear,
                                .white.opacity(0.18)
                            ] : [
                                .white.opacity(0.9),
                                .white.opacity(0.6),
                                .white.opacity(0.3),
                                .white.opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                }
                .shadow(
                    color: isDark ? Color.black.opacity(0.35) : Color.black.opacity(0.06),
                    radius: isDark ? 16 : 10,
                    x: 0,
                    y: isDark ? 8 : 4
                )
                
        case .capsule:
            let shape = Capsule()
            content
                .background {
                    glassBackground(shape: shape, isDark: isDark)
                }
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: isDark ? [
                                .white.opacity(0.4),
                                .white.opacity(0.15),
                                .clear,
                                .white.opacity(0.2)
                            ] : [
                                .white.opacity(0.95),
                                .white.opacity(0.65),
                                .white.opacity(0.3),
                                .white.opacity(0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                }
                .shadow(
                    color: isDark ? Color.black.opacity(0.35) : Color.black.opacity(0.06),
                    radius: isDark ? 14 : 8,
                    x: 0,
                    y: isDark ? 6 : 3
                )
                
        case .circle:
            let shape = Circle()
            content
                .background {
                    glassBackground(shape: shape, isDark: isDark)
                }
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: isDark ? [
                                .white.opacity(0.45),
                                .white.opacity(0.15),
                                .clear,
                                .white.opacity(0.25)
                            ] : [
                                .white.opacity(0.95),
                                .white.opacity(0.65),
                                .white.opacity(0.35),
                                .white.opacity(0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                }
                .shadow(
                    color: isDark ? Color.black.opacity(0.3) : Color.black.opacity(0.06),
                    radius: isDark ? 12 : 6,
                    x: 0,
                    y: isDark ? 6 : 2
                )
        }
    }
    
    @ViewBuilder
    private func glassBackground<S: Shape>(shape: S, isDark: Bool) -> some View {
        ZStack {
            Rectangle()
                .fill(config.material)
            
            if let tint = config.tintColor {
                tint.opacity(isDark ? 0.22 : 0.12)
            }
            
            // Specular sheen light gradient
            LinearGradient(
                colors: isDark ? [
                    .white.opacity(0.12),
                    .clear,
                    .white.opacity(0.04)
                ] : [
                    .white.opacity(0.4),
                    .clear,
                    .white.opacity(0.15)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

public extension View {
    /// Applies an adaptive Liquid Glass backdrop with specular borders and ambient elevation
    func glassEffect(_ config: GlassStyleConfig = .regular, in shapeType: GlassShapeType = .rect(cornerRadius: 16)) -> some View {
        self.modifier(GlassEffectModifier(config: config, shapeType: shapeType))
    }
}

/// Container that groups glass elements with modern spacing and layout
public struct GlassEffectContainer<Content: View>: View {
    public let spacing: CGFloat
    public let content: Content
    
    public init(spacing: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }
    
    public var body: some View {
        VStack(spacing: spacing) {
            content
        }
    }
}

/// Apple Music animated aurora mesh background with dynamic light and dark theme adaptation
public struct MusicAmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var animateOrb: Bool = false
    
    public init() {}
    
    public var body: some View {
        let isDark = colorScheme == .dark
        
        ZStack {
            // Base background
            (isDark ? Color(red: 0.04, green: 0.03, blue: 0.08) : Color(red: 0.96, green: 0.96, blue: 0.98))
                .ignoresSafeArea()
            
            // Orb 1: Apple Music Flamingo Pink / Red
            Circle()
                .fill(
                    RadialGradient(
                        colors: isDark ? [
                            Color(red: 0.98, green: 0.14, blue: 0.24).opacity(0.7),
                            Color.clear
                        ] : [
                            Color(red: 1.0, green: 0.45, blue: 0.58).opacity(0.4),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 180
                    )
                )
                .frame(width: 320, height: 320)
                .blur(radius: 60)
                .offset(x: animateOrb ? -80 : -120, y: animateOrb ? -180 : -220)
            
            // Orb 2: Electric Violet / Purple
            Circle()
                .fill(
                    RadialGradient(
                        colors: isDark ? [
                            Color(red: 0.66, green: 0.13, blue: 0.84).opacity(0.75),
                            Color.clear
                        ] : [
                            Color(red: 0.82, green: 0.60, blue: 0.98).opacity(0.45),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 360, height: 360)
                .blur(radius: 70)
                .offset(x: animateOrb ? 120 : 160, y: animateOrb ? 40 : 0)
            
            // Orb 3: Deep Indigo / Vibrant Blue
            Circle()
                .fill(
                    RadialGradient(
                        colors: isDark ? [
                            Color(red: 0.35, green: 0.34, blue: 0.84).opacity(0.7),
                            Color.clear
                        ] : [
                            Color(red: 0.55, green: 0.75, blue: 1.0).opacity(0.4),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 180
                    )
                )
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .offset(x: animateOrb ? -100 : -60, y: animateOrb ? 240 : 200)
            
            // Orb 4: Cyan / Mint Glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: isDark ? [
                            Color(red: 0.0, green: 0.78, blue: 0.75).opacity(0.35),
                            Color.clear
                        ] : [
                            Color(red: 0.50, green: 0.92, blue: 0.80).opacity(0.3),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 160
                    )
                )
                .frame(width: 260, height: 260)
                .blur(radius: 50)
                .offset(x: animateOrb ? 100 : 80, y: animateOrb ? 320 : 360)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 8.0).repeatForever(autoreverses: true)) {
                animateOrb = true
            }
        }
    }
}
