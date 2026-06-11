import ActivityKit
import WidgetKit
import SwiftUI

// 🟢 Dart側と足並みを揃えるデータ構造の定義
struct LiveNotificationAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {}

    // 固定データ（Live Activity起動時に一発で渡される枠）
    var title: String
    var subtitle: String
    var endTimeMillis: Int64
    var type: String
    var targetId: String
}

@main
struct LiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveNotificationAttributes.self) { context in
            // 🔒 ロック画面での表示UI
            VStack(alignment: .leading) {
                Text(context.attributes.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                HStack {
                    Text(context.attributes.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    Spacer()
                    // 🟢 決定打：アプリが死んでいてもiOSが自動で秒刻みカウントダウンするタイマー
                    Text(Date(timeIntervalSince1970: Double(context.attributes.endTimeMillis) / 1000.0), style: .timer)
                        .font(.system(.body, design: .monospaced))
                        .bold()
                        .foregroundColor(.orange)
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.8))

        } dynamicIsland: { context in
            // 🍏 ダイナミックアイランド（上部領域）での表示UI
            DynamicIsland {
                // 長押ししてビジュアルが広がった時（Expanded）
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.title).font(.system(size: 13, weight: .bold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // カウントダウンタイマー
                    Text(Date(timeIntervalSince1970: Double(context.attributes.endTimeMillis) / 1000.0), style: .timer)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.orange)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.subtitle).font(.system(size: 11)).foregroundColor(.gray)
                }
            } compactLeading: {
                // 通常時：左側の小さなアイコンや文字
                Text(context.attributes.type == "task" ? "⚠️" : "📝")
            } compactTrailing: {
                // 通常時：右側の小さなカウントダウン
                Text(Date(timeIntervalSince1970: Double(context.attributes.endTimeMillis) / 1000.0), style: .timer)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
            } minimal: {
                // 他のアプリと競合して丸い点だけになった時
                Text("⏳")
            }
        }
    }
}