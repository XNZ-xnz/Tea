import SwiftUI
import TeaCore

@main
struct TeaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Tea")
                .font(.largeTitle.bold())
            Text("v\(TeaVersion.string)")
                .foregroundStyle(.secondary)
                .font(.callout.monospaced())
        }
        .frame(minWidth: 520, minHeight: 360)
    }
}

#Preview {
    ContentView()
}
