import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ShowcasesView()
                .tabItem {
                    Label("Showcases", systemImage: "sparkles")
                }

            DynamicLayoutView()
                .tabItem {
                    Label("Dynamic", systemImage: "circle.dashed")
                }

            SocialFeedView()
                .tabItem {
                    Label("Feed", systemImage: "list.bullet")
                }

            AccuracyComparisonView()
                .tabItem {
                    Label("Accuracy", systemImage: "checkmark.circle")
                }

            ScrollStressTestView()
                .tabItem {
                    Label("Scroll", systemImage: "arrow.up.arrow.down")
                }
        }
    }
}

#Preview {
    ContentView()
}
