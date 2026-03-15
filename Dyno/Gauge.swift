//
//  Gauge.swift
//  Gauge
//
//  Created by Martin Imobersteg on 14.03.2026.
//

import SwiftUI

struct Gauge: View {
    @Binding var value: Int
    @State private var displayAngle: Double = 210

    private let tickDistance = 1000
    private let maxValue = 10000
    
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = size * 0.4
            let needleLength = radius * 0.9
            
            ZStack {
                Color.black

                // Draw gauge arc from 7 o'clock (120°) to 5 o'clock (420°) in CG angle space (0° = 3 o'clock)
                Path { path in
                    path.addArc(center: center, radius: radius * 0.86, startAngle: Angle(degrees: 120), endAngle: Angle(degrees: 420), clockwise: false)
                }
                .stroke(Color.gray.opacity(0.4), lineWidth: 8)

                // Draw major tick marks and labels
                ForEach(0...Int(maxValue / tickDistance), id: \.self) { index in
                    let tickValue = index * tickDistance
                    let angle = angleForValue(tickValue)

                    Path { path in
                        let tickStart = pointOnCircle(center: center, radius: radius * 0.95, angle: angle)
                        let tickEnd = pointOnCircle(center: center, radius: radius * 0.82, angle: angle)
                        path.move(to: tickStart)
                        path.addLine(to: tickEnd)
                    }
                    .stroke(Color.yellow, lineWidth: 3)

                    Text("\(tickValue / 1000)")
                        .font(.system(size: size * 0.06, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .position(pointOnCircle(center: center, radius: radius * 0.72, angle: angle))
                }

                // Draw minor tick marks (halfway between major ticks)
                ForEach(0..<Int(maxValue / tickDistance), id: \.self) { index in
                    let minorValue = index * tickDistance + tickDistance / 2
                    let angle = angleForValue(minorValue)

                    Path { path in
                        let tickStart = pointOnCircle(center: center, radius: radius * 0.9, angle: angle)
                        let tickEnd = pointOnCircle(center: center, radius: radius * 0.8, angle: angle)
                        path.move(to: tickStart)
                        path.addLine(to: tickEnd)
                    }
                    .stroke(Color.white, lineWidth: 1.5)
                }

                // Draw needle
                Path { path in
                    path.move(to: center)
                    let needleEnd = pointOnCircle(center: center, radius: needleLength, angle: Angle(degrees: displayAngle))
                    path.addLine(to: needleEnd)
                }
                .stroke(Color.red, style: StrokeStyle(lineWidth: 3, lineCap: .round))

                // Center dot
                Circle()
                    .fill(Color.red)
                    .frame(width: size * 0.05, height: size * 0.05)
                    .position(center)

                // Value label below center
                Text(String((value + 5) / 10 * 10))
                    .font(.system(size: size * 0.05, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .position(x: center.x, y: center.y + radius * 0.2)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { displayAngle = angleForValue(value).degrees }
        .onChange(of: value) { _, newValue in
            withAnimation(.spring(response: 0.01, dampingFraction: 0.1)) {
                displayAngle = angleForValue(newValue).degrees
            }
        }
    }
    
    // Convert value to angle (210° at 7 o'clock to 330° at 5 o'clock, open at 6 o'clock)
    private func angleForValue(_ val: Int) -> Angle {
        let clampedValue = min(max(val, 0), maxValue)
        let fraction = Double(clampedValue) / Double(maxValue)
        let degrees = 210 + (fraction * 300) // 210° to 510° (which is 150°, but we want 330°)
        return Angle(degrees: degrees)
    }
    
    // Calculate point on circle given center, radius, and angle
    private func pointOnCircle(center: CGPoint, radius: CGFloat, angle: Angle) -> CGPoint {
        let radians = CGFloat((angle.degrees - 90) * .pi / 180) // Adjust so 0° is at top
        return CGPoint(
            x: center.x + radius * cos(radians),
            y: center.y + radius * sin(radians)
        )
    }
}

#Preview {
    @Previewable @State var value = 0
    Gauge(value: $value)
        .task {
            while true {
                // Rev up to near redline
                let revTarget = Int.random(in: 2500...5000)
                let revStart = value
                for i in 1...50 {
                    value = revStart + (revTarget - revStart) * i / 50
                    try? await Task.sleep(nanoseconds: 8_000_000)
                }
                // Drop to launch RPM
                let dropTarget = Int.random(in: 6000...7500)
                let dropStart = value
                for i in 1...30 {
                    value = dropStart + (dropTarget - dropStart) * i / 30
                    try? await Task.sleep(nanoseconds: 12_000_000)
                }
                // Hold briefly before next blip
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
}
