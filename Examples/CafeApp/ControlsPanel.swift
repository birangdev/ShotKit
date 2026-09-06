import Charts
import SwiftUI

// MARK: - A control-heavy panel for the ImageRenderer-vs-ShotKit comparison
//
// Every element here is platform-backed: a segmented `Picker`, linear
// `ProgressView`s, a `Slider`, a `Toggle`, and a Swift `Chart`. SwiftUI's
// `ImageRenderer` rasterizes its own drawing but not these, so a rendered copy
// comes out with the labels present and the controls missing. Capturing the live
// hierarchy (what ShotKit does) keeps all of it.

public struct ControlsPanel: View {
    @State private var range = 1
    @State private var threshold = 0.8
    @State private var notify = true

    private let daily: [(day: String, tokens: Double)] = [
        ("Mon", 1.2), ("Tue", 2.1), ("Wed", 1.7), ("Thu", 2.8),
        ("Fri", 2.3), ("Sat", 0.9), ("Sun", 1.5),
    ]

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Usage this week")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)

            Picker("Range", selection: $range) {
                Text("Day").tag(0)
                Text("Week").tag(1)
                Text("Month").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Chart(daily, id: \.day) { row in
                BarMark(
                    x: .value("Day", row.day),
                    y: .value("Tokens", row.tokens)
                )
                .foregroundStyle(.green.gradient)
                .cornerRadius(4)
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 130)

            VStack(alignment: .leading, spacing: 14) {
                limitRow(title: "5-hour limit", value: 0.62)
                limitRow(title: "Weekly limit", value: 0.38)
            }

            Divider().overlay(.white.opacity(0.15))

            HStack(spacing: 12) {
                Text("Alert threshold")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                Slider(value: $threshold)
            }

            Toggle("Notify when limits reset", isOn: $notify)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
                .tint(.green)
        }
        .padding(24)
        .frame(width: 460, height: 560, alignment: .top)
        .background(Color(red: 0.09, green: 0.11, blue: 0.14))
    }

    private func limitRow(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            ProgressView(value: value)
                .tint(.green)
        }
    }
}
