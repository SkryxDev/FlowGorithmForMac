// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import SwiftUI

/// How much of today's free-model allowance is used, as a ring that fills up; clicking it shows
/// the details. The allowance belongs to the user's OpenRouter account, not to the app.
struct UsageIndicator: View {
    var account: OpenRouterAccount
    @State private var showsDetails = false

    var body: some View {
        if let used = account.dailyUsage {
            Button {
                showsDetails.toggle()
            } label: {
                UsageRing(fraction: used)
                    .frame(width: 15, height: 15)
                    .padding(3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(Text("Daily usage: \(UsageRing.percent(used))"))
            .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
                UsageDetails(account: account)
            }
        }
    }
}

struct UsageRing: View {
    var fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: min(1, max(0.03, fraction)))
                .stroke(Self.color(for: fraction), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.snappy, value: fraction)
    }

    static func color(for fraction: Double) -> Color {
        fraction >= 1 ? .red : fraction >= 0.8 ? .orange : .accentColor
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((min(1, fraction) * 100).rounded()))%"
    }
}

/// The popover: today's limit with when it resets, and whose limit it is.
private struct UsageDetails: View {
    var account: OpenRouterAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Usage limits · OpenRouter")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let used = account.dailyUsage {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Daily limit")
                        Spacer(minLength: 8)
                        Text("Resets \(OpenRouterAccount.nextReset.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                            .foregroundStyle(.secondary)
                        Text(verbatim: UsageRing.percent(used))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(1, used))
                        .tint(UsageRing.color(for: used))
                }
            }
            Divider()
            Text("This limit doesn't depend on FlowGorithmForMac: it's the daily allowance for free models of your OpenRouter account, shared by every app you use it with.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link("OpenRouter Account…", destination: OpenRouterAccount.settingsURL)
                .font(.caption)
        }
        .padding(16)
        .frame(width: 320)
        .task { await account.refreshUsage() }
    }
}
