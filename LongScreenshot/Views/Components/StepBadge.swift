import SwiftUI

/// Numbered indicator badge for multi-step workflows
public struct StepBadge: View {
    public let number: Int
    public let text: String
    public let isActive: Bool
    
    public init(number: Int, text: String, isActive: Bool) {
        self.number = number
        self.text = text
        self.isActive = isActive
    }
    
    public var body: some View {
        HStack(spacing: 6) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(isActive ? Color.white : Color.secondary)
                .frame(width: 20, height: 20)
                .background(
                    isActive ? AnyShapeStyle(Color.blue) : AnyShapeStyle(Color.gray.opacity(0.25))
                )
                .clipShape(Circle())
            
            Text(text)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
        }
    }
}
