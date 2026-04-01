import SwiftUI

enum ShowcaseScene: String, CaseIterable {
    case breaker = "Breaker"
    case tetris = "Tetris"
    case shrinkwrap = "Shrinkwrap"
    case testimonial = "Testimonial"
    case swiftui = "SwiftUI vs"
    case orbs = "Bouncing Orbs"
    case dynamic = "Dynamic Layout"
    case editorial = "Editorial"
}

struct ShowcasesView: View {
    @State private var scene: ShowcaseScene = .breaker

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ShowcaseScene.allCases, id: \.self) { s in
                            Button {
                                scene = s
                            } label: {
                                Text(s.rawValue)
                                    .font(isPad ? .body.bold() : .caption.bold())
                                    .padding(.horizontal, isPad ? 18 : 12)
                                    .padding(.vertical, isPad ? 10 : 6)
                                    .background(scene == s ? Color.blue : Color(.systemGray5))
                                    .foregroundStyle(scene == s ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, isPad ? 10 : 6)
                }
                Divider()

                switch scene {
                case .breaker:
                    BreakerScene()
                case .tetris:
                    TetrisScene()
                case .shrinkwrap:
                    ShrinkwrapScene()
                case .testimonial:
                    TestimonialScene()
                case .swiftui:
                    SwiftUIComparisonScene()
                case .orbs:
                    BouncingOrbsScene()
                case .dynamic:
                    DynamicDragScene()
                case .editorial:
                    EditorialSpreadScene()
                }
            }
            .navigationTitle("Showcases")
        }
    }
}
