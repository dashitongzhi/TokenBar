import SwiftUI

struct MiniTrendLine: View {
    var points: [UsagePoint]
    var color: Color

    var body: some View {
        GeometryReader { proxy in
            let values = points.map(\.value)
            let minValue = values.min() ?? 0
            let maxValue = values.max() ?? 1
            let range = max(maxValue - minValue, 1)

            Path { path in
                for index in points.indices {
                    let x = proxy.size.width * CGFloat(index) / CGFloat(max(points.count - 1, 1))
                    let normalized = (points[index].value - minValue) / range
                    let y = proxy.size.height - proxy.size.height * CGFloat(normalized)
                    if index == points.startIndex {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}
