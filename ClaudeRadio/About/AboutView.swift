import SwiftUI

struct AboutView: View {
    private static let authorURL = URL(string: "https://github.com/aarontbt")!

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("Claude Radio")
                .font(.title2)
                .bold()

            Text("Unofficial app, not affiliated with or endorsed by Anthropic. Plays the official Claude FM live stream from the Claude YouTube channel. Claude is a trademark of Anthropic PBC.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Link("Open Claude FM Stream", destination: ClaudeChannel.liveWatchURL)
                Link("Open Claude YouTube Channel", destination: ClaudeChannel.channelURL)
            }
            .font(.caption)

            Divider()

            HStack(spacing: 4) {
                Text("Built by")
                Link("aarontbt", destination: Self.authorURL)
                Text("· MIT License")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
    }
}
