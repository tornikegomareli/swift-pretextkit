import SwiftUI
import UIKit
import CoreText
import PretextKit

/// Twitter/X-style social feed with 1000+ posts.
///
/// Each post has variable-height text. Toggle between PretextKit sizing
/// and UILabel sizing to feel the scroll performance difference.
/// Shows timing stats for height computation across all posts.
struct SocialFeedView: View {
    enum SizingMode: String, CaseIterable {
        case pretext = "PretextKit"
        case uilabel = "UILabel"
    }

    @State private var mode: SizingMode = .pretext
    @State private var posts: [SocialPost] = []
    @State private var preparedPosts: [PreparedSocialPost] = []
    @State private var prepareMs: Double = 0
    @State private var sizingMs: Double = 0
    @State private var isLoaded = false

    private let font = CTFontCreateWithName("Helvetica Neue" as CFString, 15, nil)
    private let nameFont = CTFontCreateWithName("Helvetica Neue" as CFString, 15, nil)
    private let lineHeight: CGFloat = 20

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Mode picker
                Picker("Mode", selection: $mode) {
                    ForEach(SizingMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 6)

                // Stats
                HStack(spacing: 12) {
                    Text("\(posts.count) posts")
                        .font(.caption)
                    Spacer()
                    if isLoaded {
                        if mode == .pretext {
                            Text(String(format: "prepare: %.1fms", prepareMs))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.green)
                        }
                        Text(String(format: "sizing: %.2fms", sizingMs))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(mode == .pretext ? .green : .orange)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 6)

                Divider()

                // Feed
                SocialFeedCollectionView(
                    posts: posts,
                    preparedPosts: preparedPosts,
                    mode: mode,
                    font: font,
                    lineHeight: lineHeight,
                    onSizingTime: { ms in sizingMs = ms }
                )
            }
            .navigationTitle("Feed")
            .toolbar {
                Menu {
                    Button("Load 500") { loadPosts(count: 500) }
                    Button("Load 1000") { loadPosts(count: 1000) }
                    Button("Load 2000") { loadPosts(count: 2000) }
                } label: {
                    Image(systemName: "plus.circle")
                }
            }
            .onAppear {
                if posts.isEmpty { loadPosts(count: 1000) }
            }
        }
    }

    private func loadPosts(count: Int) {
        isLoaded = false
        let newPosts = SocialPost.generate(count: count)
        let fontDesc = FontDescriptor(font)
        let lh = lineHeight

        let start = CFAbsoluteTimeGetCurrent()
        DispatchQueue.global(qos: .userInitiated).async {
            let prepared = newPosts.map { post -> PreparedSocialPost in
                let p = PretextKit.prepare(post.text, font: fontDesc)
                let result = PretextKit.layout(p, maxWidth: 340, lineHeight: lh)
                return PreparedSocialPost(post: post, prepared: p, height: result.height, lineCount: result.lineCount)
            }
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

            DispatchQueue.main.async {
                self.posts = newPosts
                self.preparedPosts = prepared
                self.prepareMs = elapsed
                self.isLoaded = true
            }
        }
    }
}

// MARK: - Post model

struct SocialPost: Identifiable {
    let id: Int
    let authorName: String
    let handle: String
    let text: String
    let time: String
    let likes: Int
    let reposts: Int
    let replies: Int
    let avatarColor: Color

    static func generate(count: Int) -> [SocialPost] {
        let authors = [
            ("Cheng Lou", "@chenglou"),
            ("Sebastian Markbage", "@sebmarkbage"),
            ("Swift Developer", "@swiftdev"),
            ("iOS Engineer", "@ioseng"),
            ("Text Layout Nerd", "@textlayout"),
            ("UIKit Veteran", "@uikitveteran"),
            ("SwiftUI Fan", "@swiftuifan"),
            ("Performance Eng", "@perfeng"),
        ]

        let texts = [
            "Just shipped a text layout engine that does pure arithmetic reflow. No CoreText calls on resize. The future of iOS text performance is here.",
            "The key insight: decouple measurement from layout. Measure once via CoreText, cache segment widths, then reflow at any width with just math. Sub-microsecond per text block.",
            "春天到了万物复苏百花齐放。人工智能正在改变我们的生活方式和工作方式。这是一条混合中英文的推文 with some English text mixed in.",
            "TextKit 2's viewport estimation causes scroll jitter. usageBoundsForTextContainer is unstable during scrolling. We need exact heights, not estimates.",
            "🚀 Benchmark results: layout() x 500 texts in 0.05ms. That's 0.0001ms per text. boundingRect takes 8ms for the same batch. 160x faster on resize.",
            "مرحبا بالعالم! الذكاء الاصطناعي يغير حياتنا بطرق لم نكن نتخيلها. هذا اختبار للنص العربي في تغريدة.",
            "The three levels of iOS text measurement:\n1. UILabel.sizeThatFits — easy, expensive\n2. NSLayoutManager — cached but complex\n3. PretextKit — arithmetic, instant\n\nChoose wisely.",
            "Hot take: most iOS scroll performance issues in chat/feed apps come from text measurement, not rendering. Fix the measurement, fix the scroll.",
            "서울은 대한민국의 수도이며 가장 큰 도시입니다. 한글은 세종대왕이 창제한 문자로 과학적이고 체계적입니다.",
            "Interesting pattern: prepare() costs ~0.04ms/text (one-time). But layout() costs ~0.0001ms/text (every resize). After 400 resizes, PretextKit is net faster than even a single boundingRect call.",
            "OK",
            "The web has the same problem. Pretext (JS) solves it with canvas measureText + arithmetic reflow. We ported the same architecture to iOS with CoreText + CTLine.",
            "Thread: Why self-sizing UICollectionView cells are slow 🧵\n\n1. systemLayoutSizeFitting triggers constraint solver\n2. Constraint solver triggers text measurement\n3. Text measurement triggers CoreText shaping\n4. This happens PER CELL, PER SCROLL FRAME",
            "東京タワーは日本の有名な観光名所です。Tokyo Tower は 333 メートルです。桜の花が咲く季節になりました。",
            "Just found out Android has PrecomputedText since API 28. iOS has... nothing equivalent in the SDK. Until now.",
            "walkLineRanges() is the secret weapon for shrinkwrap. Binary search for tightest bubble width without materializing any line text. Zero allocations in the hot path.",
            "Hello 🌍🌎🌏 World 🚀✨ Testing emojis 👨‍👩‍👧‍👦 in a social feed post with mixed content and various Unicode scripts!",
            "Soft hyphens (U+00AD), NBSP (U+00A0), ZWSP (U+200B) — all handled correctly. The segment model distinguishes 8 break kinds.",
        ]

        let times = ["1m", "3m", "7m", "12m", "23m", "45m", "1h", "2h", "4h", "8h", "12h", "1d", "2d"]
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .mint, .red]

        return (0..<count).map { i in
            let (name, handle) = authors[i % authors.count]
            return SocialPost(
                id: i,
                authorName: name,
                handle: handle,
                text: texts[i % texts.count],
                time: times[i % times.count],
                likes: Int.random(in: 0...2000),
                reposts: Int.random(in: 0...500),
                replies: Int.random(in: 0...300),
                avatarColor: colors[i % colors.count]
            )
        }
    }
}

struct PreparedSocialPost {
    let post: SocialPost
    let prepared: PreparedText
    let height: CGFloat
    let lineCount: Int
}

// MARK: - UICollectionView wrapper

private struct SocialFeedCollectionView: UIViewControllerRepresentable {
    let posts: [SocialPost]
    let preparedPosts: [PreparedSocialPost]
    let mode: SocialFeedView.SizingMode
    let font: CTFont
    let lineHeight: CGFloat
    let onSizingTime: @MainActor (Double) -> Void

    func makeUIViewController(context: Context) -> SocialFeedViewController {
        SocialFeedViewController()
    }

    func updateUIViewController(_ vc: SocialFeedViewController, context: Context) {
        vc.update(
            posts: posts,
            preparedPosts: preparedPosts,
            mode: mode,
            font: font,
            lineHeight: lineHeight,
            onSizingTime: onSizingTime
        )
    }
}

final class SocialFeedViewController: UIViewController {
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, Int>!
    private var posts: [SocialPost] = []
    private var preparedPosts: [PreparedSocialPost] = []
    private var mode: SocialFeedView.SizingMode = .pretext
    private var textFont: CTFont = CTFontCreateWithName("Helvetica Neue" as CFString, 15, nil)
    private var lineHeight: CGFloat = 20
    private var onSizingTime: (@MainActor (Double) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
        setupDataSource()
    }

    func update(
        posts: [SocialPost],
        preparedPosts: [PreparedSocialPost],
        mode: SocialFeedView.SizingMode,
        font: CTFont,
        lineHeight: CGFloat,
        onSizingTime: @escaping @MainActor (Double) -> Void
    ) {
        let modeChanged = self.mode != mode
        self.posts = posts
        self.preparedPosts = preparedPosts
        self.mode = mode
        self.textFont = font
        self.lineHeight = lineHeight
        self.onSizingTime = onSizingTime

        applySnapshot()
        if modeChanged {
            measureSizingTime()
            collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 0
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        collectionView.register(SocialPostCell.self, forCellWithReuseIdentifier: "post")
        view.addSubview(collectionView)
    }

    private func setupDataSource() {
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { [weak self] cv, ip, item in
            guard let self else { return UICollectionViewCell() }
            let cell = cv.dequeueReusableCell(withReuseIdentifier: "post", for: ip) as! SocialPostCell
            if item < self.posts.count {
                cell.configure(with: self.posts[item], font: self.textFont as UIFont)
            }
            return cell
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems(Array(0..<posts.count))
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func measureSizingTime() {
        let width = view.bounds.width - 80 // avatar + padding
        guard width > 0 else { return }

        let start = CFAbsoluteTimeGetCurrent()

        switch mode {
        case .pretext:
            for pp in preparedPosts {
                _ = PretextKit.layout(pp.prepared, maxWidth: width, lineHeight: lineHeight)
            }
        case .uilabel:
            let uiFont = textFont as UIFont
            for post in posts {
                let attrStr = NSAttributedString(string: post.text, attributes: [.font: uiFont])
                _ = attrStr.boundingRect(
                    with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
            }
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        onSizingTime?(elapsed)
    }
}

extension SocialFeedViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ cv: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = cv.bounds.width
        let textWidth = width - 80

        let textHeight: CGFloat
        switch mode {
        case .pretext:
            if indexPath.item < preparedPosts.count {
                textHeight = PretextKit.layout(preparedPosts[indexPath.item].prepared, maxWidth: textWidth, lineHeight: lineHeight).height
            } else {
                textHeight = 60
            }
        case .uilabel:
            if indexPath.item < posts.count {
                let attrStr = NSAttributedString(string: posts[indexPath.item].text, attributes: [.font: textFont as UIFont])
                let rect = attrStr.boundingRect(
                    with: CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                textHeight = ceil(rect.height)
            } else {
                textHeight = 60
            }
        }

        // name + handle + text + engagement bar + padding
        let totalHeight = 20 + textHeight + 36 + 24
        return CGSize(width: width, height: totalHeight)
    }
}

// MARK: - Post cell

private final class SocialPostCell: UICollectionViewCell {
    private let avatarView = UIView()
    private let nameLabel = UILabel()
    private let handleLabel = UILabel()
    private let timeLabel = UILabel()
    private let bodyLabel = UILabel()
    private let likesLabel = UILabel()
    private let repostsLabel = UILabel()
    private let repliesLabel = UILabel()
    private let separator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        // Avatar
        avatarView.layer.cornerRadius = 20
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarView)

        // Name
        nameLabel.font = .systemFont(ofSize: 15, weight: .bold)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)

        // Handle + time
        handleLabel.font = .systemFont(ofSize: 14)
        handleLabel.textColor = .secondaryLabel
        handleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(handleLabel)

        // Body
        bodyLabel.font = .systemFont(ofSize: 15)
        bodyLabel.numberOfLines = 0
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bodyLabel)

        // Engagement bar
        for label in [likesLabel, repostsLabel, repliesLabel] {
            label.font = .systemFont(ofSize: 13)
            label.textColor = .secondaryLabel
            label.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(label)
        }

        // Separator
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separator)

        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarView.widthAnchor.constraint(equalToConstant: 40),
            avatarView.heightAnchor.constraint(equalToConstant: 40),

            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),

            handleLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            handleLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 4),
            handleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),

            bodyLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            bodyLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            bodyLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            repliesLabel.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 10),
            repliesLabel.leadingAnchor.constraint(equalTo: bodyLabel.leadingAnchor),

            repostsLabel.centerYAnchor.constraint(equalTo: repliesLabel.centerYAnchor),
            repostsLabel.leadingAnchor.constraint(equalTo: repliesLabel.trailingAnchor, constant: 24),

            likesLabel.centerYAnchor.constraint(equalTo: repliesLabel.centerYAnchor),
            likesLabel.leadingAnchor.constraint(equalTo: repostsLabel.trailingAnchor, constant: 24),

            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    func configure(with post: SocialPost, font: UIFont) {
        avatarView.backgroundColor = UIColor(post.avatarColor)
        nameLabel.text = post.authorName
        handleLabel.text = "\(post.handle) · \(post.time)"
        bodyLabel.text = post.text
        bodyLabel.font = font
        repliesLabel.text = "💬 \(post.replies)"
        repostsLabel.text = "🔁 \(post.reposts)"
        likesLabel.text = "❤️ \(post.likes)"
    }
}
