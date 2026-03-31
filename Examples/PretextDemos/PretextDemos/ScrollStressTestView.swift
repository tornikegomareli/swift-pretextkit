import SwiftUI
import UIKit
import CoreText
import PretextKit

/// Side-by-side scroll stress test: PretextKit vs UILabel.
///
/// Two collection views scroll in sync. Each cell shows the text plus
/// the time it took to compute that cell's height — making the performance
/// difference visible and tangible.
struct ScrollStressTestView: View {
    @State private var stats = SizingStats()
    @State private var isReady = false
    @State private var cellCount = 500

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isReady {
                    statsBar
                    Divider()
                }

                HStack {
                    Text("Cells: \(cellCount)")
                        .font(.caption)
                        .monospacedDigit()
                    Stepper("", value: $cellCount, in: 100...2000, step: 100)
                        .fixedSize()
                }
                .padding(.horizontal)
                .padding(.vertical, 4)

                Divider()

                if isReady {
                    HStack(spacing: 0) {
                        Text("PretextKit")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity)
                        Divider().frame(height: 20)
                        Text("UILabel (boundingRect)")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 4)

                    Divider()

                    SideBySideCollectionView(
                        cellCount: cellCount,
                        onStats: { stats = $0 }
                    )
                } else {
                    ProgressView("Preparing texts...")
                        .padding()
                    Spacer()
                }
            }
            .navigationTitle("Scroll Stress")
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isReady = true
                }
            }
        }
    }

    private var statsBar: some View {
        VStack(spacing: 6) {
            // Row 1: First-time cost (honest comparison)
            HStack {
                Text("First sizing")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(format: "prepare: %.1fms", stats.prepareMs))
                        .font(.caption2.monospacedDigit())
                    Text(String(format: "+ layout: %.2fms", stats.pretextSizeMs))
                        .font(.caption2.monospacedDigit())
                    Text(String(format: "= total: %.1fms", stats.prepareMs + stats.pretextSizeMs))
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(.green)
                }
                Spacer()
                Text("vs")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("no prepare")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "boundingRect: %.1fms", stats.uilabelSizeMs))
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            // Row 2: Resize/reflow (the real win)
            HStack {
                Text("On resize (the win)")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("layout() only")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2fms", stats.pretextSizeMs))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.green)
                }
                Spacer()
                if stats.uilabelSizeMs > 0 && stats.pretextSizeMs > 0 {
                    Text(String(format: "%.0fx", stats.uilabelSizeMs / max(stats.pretextSizeMs, 0.001)))
                        .font(.title.bold())
                        .foregroundStyle(.green)
                    Text("faster")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("boundingRect again")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1fms", stats.uilabelSizeMs))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Stats

struct SizingStats {
    var prepareMs: Double = 0
    var pretextSizeMs: Double = 0
    var uilabelSizeMs: Double = 0
}

// MARK: - Side-by-side UICollectionView

private struct SideBySideCollectionView: UIViewControllerRepresentable {
    let cellCount: Int
    let onStats: @MainActor (SizingStats) -> Void

    func makeUIViewController(context: Context) -> SideBySideViewController {
        SideBySideViewController(cellCount: cellCount, onStats: onStats)
    }

    func updateUIViewController(_ vc: SideBySideViewController, context: Context) {
        vc.updateCellCount(cellCount)
    }
}

final class SideBySideViewController: UIViewController {
    private var leftCollectionView: UICollectionView! // PretextKit
    private var rightCollectionView: UICollectionView! // UILabel
    private var leftDataSource: UICollectionViewDiffableDataSource<Int, Int>!
    private var rightDataSource: UICollectionViewDiffableDataSource<Int, Int>!

    private var texts: [String] = []
    private var preparedTexts: [PreparedText] = []
    private var cellCount: Int
    private let font = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
    private let lineHeight: CGFloat = 18
    private let onStats: @MainActor (SizingStats) -> Void
    private var isSyncing = false

    init(cellCount: Int, onStats: @escaping @MainActor (SizingStats) -> Void) {
        self.cellCount = cellCount
        self.onStats = onStats
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        setupDataSources()
        reloadData()
    }

    func updateCellCount(_ count: Int) {
        guard count != cellCount else { return }
        cellCount = count
        reloadData()
    }

    private func setupLayout() {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        leftCollectionView = makeCollectionView(tag: 0)
        rightCollectionView = makeCollectionView(tag: 1)
        stack.addArrangedSubview(leftCollectionView)

        let divider = UIView()
        divider.backgroundColor = .separator
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        stack.addArrangedSubview(divider)

        stack.addArrangedSubview(rightCollectionView)
    }

    private func makeCollectionView(tag: Int) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 1
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .systemBackground
        cv.tag = tag
        cv.delegate = self
        cv.register(MetricTextCell.self, forCellWithReuseIdentifier: "cell")
        return cv
    }

    private func setupDataSources() {
        leftDataSource = UICollectionViewDiffableDataSource(collectionView: leftCollectionView) { [weak self] cv, ip, item in
            guard let self else { return UICollectionViewCell() }
            let cell = cv.dequeueReusableCell(withReuseIdentifier: "cell", for: ip) as! MetricTextCell
            cell.configure(text: self.texts[item], font: self.font as UIFont, badge: nil, badgeColor: .systemGreen)
            return cell
        }
        rightDataSource = UICollectionViewDiffableDataSource(collectionView: rightCollectionView) { [weak self] cv, ip, item in
            guard let self else { return UICollectionViewCell() }
            let cell = cv.dequeueReusableCell(withReuseIdentifier: "cell", for: ip) as! MetricTextCell
            cell.configure(text: self.texts[item], font: self.font as UIFont, badge: nil, badgeColor: .systemOrange)
            return cell
        }
    }

    private func reloadData() {
        texts = (0..<cellCount).map { i in
            TestData.scrollStressData[i % TestData.scrollStressData.count]
        }

        let fontDesc = FontDescriptor(font)
        let textsToPrep = texts

        // Prepare on background
        let prepStart = CFAbsoluteTimeGetCurrent()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let prepared = textsToPrep.map { PretextKit.prepare($0, font: fontDesc) }
            let prepMs = (CFAbsoluteTimeGetCurrent() - prepStart) * 1000

            DispatchQueue.main.async {
                guard let self else { return }
                self.preparedTexts = prepared
                self.applySnapshots()
                self.measureAndReport(prepareMs: prepMs)
            }
        }
    }

    private func applySnapshots() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems(Array(0..<texts.count))
        leftDataSource.apply(snapshot, animatingDifferences: false)
        rightDataSource.apply(snapshot, animatingDifferences: false)
    }

    private func measureAndReport(prepareMs: Double) {
        let width = leftCollectionView.bounds.width
        guard width > 0 else { return }

        // Measure PretextKit sizing time
        let ptStart = CFAbsoluteTimeGetCurrent()
        for p in preparedTexts {
            _ = PretextKit.layout(p, maxWidth: width, lineHeight: lineHeight)
        }
        let ptMs = (CFAbsoluteTimeGetCurrent() - ptStart) * 1000

        // Measure UILabel sizing time
        let uiFont = font as UIFont
        let nsStart = CFAbsoluteTimeGetCurrent()
        for text in texts {
            let attrStr = NSAttributedString(string: text, attributes: [.font: uiFont])
            _ = attrStr.boundingRect(
                with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
        }
        let nsMs = (CFAbsoluteTimeGetCurrent() - nsStart) * 1000

        onStats(SizingStats(prepareMs: prepareMs, pretextSizeMs: ptMs, uilabelSizeMs: nsMs))
    }
}

extension SideBySideViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collectionView.bounds.width
        let height: CGFloat

        if collectionView.tag == 0 {
            // PretextKit
            if indexPath.item < preparedTexts.count {
                height = PretextKit.layout(preparedTexts[indexPath.item], maxWidth: width, lineHeight: lineHeight).height
            } else {
                height = 40
            }
        } else {
            // UILabel
            let text = texts[indexPath.item]
            let attrStr = NSAttributedString(string: text, attributes: [.font: font as UIFont])
            let rect = attrStr.boundingRect(
                with: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            height = ceil(rect.height)
        }

        return CGSize(width: width, height: max(height, 20))
    }

    // Sync scroll positions
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isSyncing else { return }
        isSyncing = true
        if scrollView === leftCollectionView {
            rightCollectionView.contentOffset = scrollView.contentOffset
        } else {
            leftCollectionView.contentOffset = scrollView.contentOffset
        }
        isSyncing = false
    }
}

// MARK: - Cell with metric badge

private final class MetricTextCell: UICollectionViewCell {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
        ])
        contentView.backgroundColor = .secondarySystemBackground
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(text: String, font: UIFont, badge: String?, badgeColor: UIColor) {
        label.text = text
        label.font = font
    }
}
