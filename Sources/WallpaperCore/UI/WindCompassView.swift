import SwiftUI

/// An interactive 360° circular compass control with a draggable wind vector joystick,
/// matching the design and physics controls of https://tryflake.ru.
public struct WindCompassView: View {
    @Binding public var windAngleDegrees: Double // 0° = East, 90° = Down/South, 180° = West, 270° = Up/North
    @Binding public var windSpeed: Double        // 0.0 to 3.0

    private let dialRadius: CGFloat = 55

    public init(windAngleDegrees: Binding<Double>, windSpeed: Binding<Double>) {
        self._windAngleDegrees = windAngleDegrees
        self._windSpeed = windSpeed
    }

    public var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Dial Background
                Circle()
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.8))
                    .frame(width: dialRadius * 2, height: dialRadius * 2)
                    .overlay(
                        Circle()
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1.5)
                    )

                // Degree tick marks
                ForEach(0..<8) { i in
                    Rectangle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 1.5, height: 6)
                        .offset(y: -dialRadius + 5)
                        .rotationEffect(.degrees(Double(i) * 45))
                }

                // Center origin dot
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 6, height: 6)

                // Directional Needle / Arrow Indicator
                VStack(spacing: 0) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.accentColor)
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 2.5, height: dialRadius * 0.65)
                    Spacer()
                }
                .frame(height: dialRadius * 2)
                .rotationEffect(.degrees(windAngleDegrees - 270)) // Offset so 90° points down (South)
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateAngle(from: value.location)
                    }
            )

            // Dynamic readouts
            HStack(spacing: 12) {
                Text("\(Int(windAngleDegrees))°")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)

                Text(windDirectionLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var windDirectionLabel: String {
        let normalized = (windAngleDegrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        switch normalized {
        case 67.5..<112.5: return "Down (Calm)"
        case 22.5..<67.5: return "South-East"
        case 337.5...360, 0..<22.5: return "East Gust"
        case 292.5..<337.5: return "North-East"
        case 247.5..<292.5: return "Updraft"
        case 202.5..<247.5: return "North-West"
        case 157.5..<202.5: return "West Gust"
        case 112.5..<157.5: return "South-West"
        default: return "Variable"
        }
    }

    private func updateAngle(from location: CGPoint) {
        let center = CGPoint(x: dialRadius, y: dialRadius)
        let dx = location.x - center.x
        let dy = location.y - center.y

        // Calculate radians from center (Y inverted for screen coordinates)
        let angleRad = atan2(dy, dx)
        var degrees = angleRad * 180 / .pi
        if degrees < 0 {
            degrees += 360
        }
        self.windAngleDegrees = degrees
    }
}
