import SwiftUI
import AudioToolbox
import GoogleMobileAds

@main
struct QuantumAmidaApp: App {
    var body: some Scene {
        WindowGroup {
            QuantumAmidaView()
        }
    }
}

struct QuantumAmidaView: View {
    @State private var entryCount = 5.0
    @State private var names = ["ミラ", "レイ", "ノヴァ", "カイ", "ユリ", "ゼン", "アオ", "ルナ"]
    @State private var resultLabels = ["大当たり", "調査任務", "補給係", "船長", "解析班", "ワープ係", "通信士", "自由枠"]
    @State private var model = AmidaModel(count: 5)
    @State private var startDate: Date?
    @State private var revealedResults: Set<Int> = []
    @State private var soundEnabled = true
    @State private var isRunning = false
    @State private var interstitial: GADInterstitialAd?

    private let bannerAdUnitID = "ca-app-pub-9404799280370656/3487355456"

    private var count: Int {
        Int(entryCount.rounded())
    }

    var body: some View {
        ZStack {
            GalaxyBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        settingsPanel
                        board
                        resultGrid
                    }
                    .padding(16)
                }
                BannerAdView(adUnitID: bannerAdUnitID)
                    .frame(height: 50)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            rebuild()
            loadInterstitial()
        }
        .onChange(of: count) { _ in
            normalizeArrays()
            rebuild()
        }
        .onReceive(Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()) { date in
            tick(date)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("SPACE AMIDA")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.cyan)
                Text("スペースあみだ")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.72)
            }
            Spacer()
            Button {
                soundEnabled.toggle()
                playTap()
            } label: {
                Image(systemName: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .frame(width: 46, height: 46)
                    .foregroundStyle(soundEnabled ? .cyan : .secondary)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.14)))
            }
            .accessibilityLabel(soundEnabled ? "効果音をオフ" : "効果音をオン")
        }
    }

    private var settingsPanel: some View {
        VStack(spacing: 14) {
            HStack {
                Text("エントリー数")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(count)")
                    .font(.title3.weight(.black))
                    .foregroundStyle(.yellow)
            }

            Slider(value: $entryCount, in: 2...8, step: 1)
                .tint(.cyan)
                .disabled(isRunning)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(0..<count, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("#\(String(format: "%02d", index + 1))")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        TextField("名前", text: binding($names, index: index))
                            .textFieldStyle(AmidaTextFieldStyle())
                            .disabled(isRunning)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("RESULT LABELS")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.green)
                    Spacer()
                    Button("名前から作成") {
                        for index in 0..<count {
                            resultLabels[index] = names[index]
                        }
                        revealedResults = []
                        playTap()
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.green)
                    .disabled(isRunning)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(0..<count, id: \.self) { index in
                        TextField("結果", text: binding($resultLabels, index: index))
                            .textFieldStyle(AmidaTextFieldStyle())
                            .disabled(isRunning)
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    rebuild()
                    playTap()
                } label: {
                    Label("再生成", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(AmidaGhostButtonStyle())
                .disabled(isRunning)

                Button {
                    start()
                } label: {
                    Label(isRunning ? "RUNNING" : "START", systemImage: "sparkles")
                }
                .buttonStyle(AmidaStartButtonStyle())
                .disabled(isRunning)
            }
        }
        .padding(16)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.cyan.opacity(0.2)))
    }

    private var board: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date
            let elapsed = startDate.map { now.timeIntervalSince($0) } ?? 0
            AmidaCanvasView(
                model: model,
                names: Array(names.prefix(count)),
                resultLabels: Array(resultLabels.prefix(count)),
                elapsed: elapsed,
                isRunning: isRunning,
                revealedResults: revealedResults
            )
            .frame(height: 440)
            .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.cyan.opacity(0.26)))
        }
    }

    private var resultGrid: some View {
        let outputs = model.outputs(for: Array(names.prefix(count)))
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(0..<count, id: \.self) { index in
                VStack(alignment: .leading, spacing: 6) {
                    Text(resultLabels[index])
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(revealedResults.contains(index) ? outputs[index] : "待機中")
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(revealedResults.contains(index) ? .green.opacity(0.12) : .white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(revealedResults.contains(index) ? .green.opacity(0.42) : .white.opacity(0.12)))
            }
        }
    }

    private func binding(_ array: Binding<[String]>, index: Int) -> Binding<String> {
        Binding {
            guard array.wrappedValue.indices.contains(index) else { return "" }
            return array.wrappedValue[index]
        } set: { newValue in
            guard array.wrappedValue.indices.contains(index) else { return }
            array.wrappedValue[index] = newValue
        }
    }

    private func normalizeArrays() {
        while names.count < 8 {
            names.append("ENTRY \(names.count + 1)")
        }
        while resultLabels.count < 8 {
            resultLabels.append("RESULT \(resultLabels.count + 1)")
        }
    }

    private func rebuild() {
        model = AmidaModel(count: count)
        startDate = nil
        revealedResults = []
        isRunning = false
    }

    private func start() {
        startDate = Date()
        revealedResults = []
        isRunning = true
        playTap()
    }

    private func tick(_ date: Date) {
        guard isRunning, let startDate else { return }
        let elapsed = date.timeIntervalSince(startDate)
        var nextRevealed = revealedResults
        for path in model.paths {
            if elapsed >= path.delay + path.duration {
                nextRevealed.insert(path.endIndex)
            }
        }
        if nextRevealed != revealedResults {
            revealedResults = nextRevealed
            playTap()
        }
        if nextRevealed.count == count {
            isRunning = false
            showInterstitialIfReady()
        }
    }

    private func playTap() {
        guard soundEnabled else { return }
        AudioServicesPlaySystemSound(1104)
    }

    private func loadInterstitial() {
        GADInterstitialAd.load(withAdUnitID: bannerAdUnitID, request: GADRequest()) { ad, _ in
            self.interstitial = ad
        }
    }

    private func showInterstitialIfReady() {
        guard let interstitial,
              let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
        interstitial.present(fromRootViewController: rootVC)
        self.interstitial = nil
        loadInterstitial()
    }
}

private struct AmidaCanvasView: View {
    let model: AmidaModel
    let names: [String]
    let resultLabels: [String]
    let elapsed: TimeInterval
    let isRunning: Bool
    let revealedResults: Set<Int>

    var body: some View {
        Canvas { context, size in
            drawBackdrop(context: &context, size: size)
            let layout = model.layout(in: size)
            drawLines(context: &context, layout: layout)
            drawLabels(context: &context, layout: layout)

            if isRunning {
                drawStartBurst(context: &context, size: size)
            }

            for path in model.paths {
                let progress = path.progress(at: elapsed)
                if progress > 0 {
                    drawParticlePath(context: &context, layout: layout, path: path, progress: progress)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func drawBackdrop(context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [
                Color(red: 0.02, green: 0.03, blue: 0.08).opacity(0.9),
                Color(red: 0.08, green: 0.03, blue: 0.12).opacity(0.72),
                Color(red: 0.01, green: 0.02, blue: 0.04).opacity(0.95)
            ]),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: size.width, y: size.height)
        ))

        let galaxy = Path(ellipseIn: CGRect(x: size.width * 0.18, y: size.height * 0.18, width: size.width * 0.78, height: size.height * 0.38))
        var blurContext = context
        blurContext.addFilter(.blur(radius: 22))
        blurContext.fill(galaxy, with: .radialGradient(
            Gradient(colors: [.cyan.opacity(0.34), .purple.opacity(0.18), .clear]),
            center: CGPoint(x: size.width * 0.58, y: size.height * 0.36),
            startRadius: 20,
            endRadius: size.width * 0.46
        ))

        for index in 0..<46 {
            let x = CGFloat((index * 37) % 101) / 100 * size.width
            let y = CGFloat((index * 59) % 97) / 100 * size.height
            let dot = Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4))
            context.fill(dot, with: .color(.white.opacity(0.46)))
        }
    }

    private func drawLines(context: inout GraphicsContext, layout: AmidaLayout) {
        var glowContext = context
        glowContext.addFilter(.shadow(color: .cyan.opacity(0.78), radius: 12))

        for column in layout.columns {
            var glow = Path()
            glow.move(to: CGPoint(x: column.x, y: layout.top))
            glow.addLine(to: CGPoint(x: column.x, y: layout.bottom))
            glowContext.stroke(glow, with: .color(.cyan.opacity(0.76)), lineWidth: 6.5)
            context.stroke(glow, with: .color(.white.opacity(0.9)), lineWidth: 1.8)
        }

        for bridge in layout.bridges {
            let color = bridge.index.isMultiple(of: 2) ? Color.pink : Color.green
            var line = Path()
            line.move(to: CGPoint(x: bridge.x1, y: bridge.y))
            line.addLine(to: CGPoint(x: bridge.x2, y: bridge.y))
            glowContext.stroke(line, with: .color(color.opacity(0.74)), lineWidth: 7)
            context.stroke(line, with: .color(.white.opacity(0.88)), lineWidth: 1.9)
        }
    }

    private func drawLabels(context: inout GraphicsContext, layout: AmidaLayout) {
        for index in layout.columns.indices {
            drawBadge(context: &context, text: names[safe: index] ?? "ENTRY \(index + 1)", at: CGPoint(x: layout.columns[index].x, y: layout.top - 44), color: .cyan)
            drawBadge(context: &context, text: resultLabels[safe: index] ?? "RESULT \(index + 1)", at: CGPoint(x: layout.columns[index].x, y: layout.bottom + 44), color: revealedResults.contains(index) ? .green : .secondary)
        }
    }

    private func drawBadge(context: inout GraphicsContext, text: String, at point: CGPoint, color: Color) {
        let resolved = context.resolve(Text(text).font(.caption.weight(.black)).foregroundColor(.white))
        let width = min(max(resolved.measure(in: CGSize(width: 140, height: 28)).width + 22, 54), 126)
        let rect = CGRect(x: point.x - width / 2, y: point.y - 14, width: width, height: 28)
        context.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(.black.opacity(0.72)))
        context.stroke(Path(roundedRect: rect, cornerRadius: 8), with: .color(color.opacity(0.72)), lineWidth: 1)
        context.draw(resolved, at: point)
    }

    private func drawStartBurst(context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let pulse = 0.5 + sin(elapsed * 8) * 0.5
        let radius = 24 + pulse * 22
        context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(.cyan.opacity(0.22)), lineWidth: 3)
    }

    private func drawParticlePath(context: inout GraphicsContext, layout: AmidaLayout, path: AmidaPath, progress: Double) {
        let point = layout.point(on: path, progress: progress)
        let color = AmidaModel.palette[path.startIndex % AmidaModel.palette.count]
        var glowContext = context
        glowContext.addFilter(.shadow(color: color.opacity(0.9), radius: 16))

        let trailProgress = max(0, progress - 0.16)
        var trail = Path()
        for step in 0...8 {
            let p = trailProgress + (progress - trailProgress) * Double(step) / 8
            let trailPoint = layout.point(on: path, progress: p)
            if step == 0 {
                trail.move(to: trailPoint)
            } else {
                trail.addLine(to: trailPoint)
            }
        }
        glowContext.stroke(trail, with: .color(color.opacity(0.78)), lineWidth: 7)
        context.stroke(trail, with: .color(.white.opacity(0.82)), lineWidth: 1.8)

        let burst = Path(ellipseIn: CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16))
        glowContext.fill(burst, with: .color(color))
        context.fill(Path(ellipseIn: CGRect(x: point.x - 3.2, y: point.y - 3.2, width: 6.4, height: 6.4)), with: .color(.white))
    }
}

private struct AmidaModel {
    static let palette: [Color] = [.cyan, .pink, .yellow, .green, .purple, .orange, .mint, .indigo]

    let count: Int
    let bridges: [AmidaBridge]
    let paths: [AmidaPath]

    init(count: Int) {
        let count = max(2, min(8, count))
        self.count = count
        self.bridges = AmidaModel.makeBridges(count: count)
        self.paths = AmidaModel.makePaths(count: count, bridges: bridges)
    }

    func layout(in size: CGSize) -> AmidaLayout {
        let top: CGFloat = 78
        let bottom = size.height - 82
        let left = max(CGFloat(36), min(CGFloat(72), size.width * 0.09))
        let right = size.width - left
        let gap = (right - left) / CGFloat(count - 1)
        let columns = (0..<count).map { AmidaColumn(x: left + CGFloat($0) * gap) }
        let layoutBridges = bridges.enumerated().map { index, bridge in
            AmidaLayoutBridge(
                index: index,
                left: bridge.left,
                x1: columns[bridge.left].x,
                x2: columns[bridge.left + 1].x,
                y: top + (bottom - top) * bridge.yRank
            )
        }
        return AmidaLayout(top: top, bottom: bottom, columns: columns, bridges: layoutBridges)
    }

    func outputs(for names: [String]) -> [String] {
        var outputs = Array(repeating: "", count: count)
        for path in paths {
            outputs[path.endIndex] = names[safe: path.startIndex]?.isEmpty == false ? names[path.startIndex] : "ENTRY \(path.startIndex + 1)"
        }
        return outputs
    }

    private static func makeBridges(count: Int) -> [AmidaBridge] {
        let rowCount = max(8, min(22, count * 3 + 2))
        var output: [AmidaBridge] = []
        var lastPair = -10
        for row in 0..<rowCount {
            var candidates = Array(0..<(count - 1)).filter { abs($0 - lastPair) > 0 }
            if candidates.isEmpty {
                candidates = Array(0..<(count - 1))
            }
            let pair = candidates[(row * 7 + count * 3) % candidates.count]
            lastPair = pair
            output.append(AmidaBridge(left: pair, yRank: CGFloat(row + 1) / CGFloat(rowCount + 1)))
        }
        return output
    }

    private static func makePaths(count: Int, bridges: [AmidaBridge]) -> [AmidaPath] {
        (0..<count).map { startIndex in
            var current = startIndex
            var points: [AmidaPoint] = [AmidaPoint(column: current, bridgeIndex: nil, isTop: true)]
            for (bridgeIndex, bridge) in bridges.enumerated() {
                if bridge.left == current {
                    points.append(AmidaPoint(column: current, bridgeIndex: bridgeIndex, isTop: false))
                    current += 1
                    points.append(AmidaPoint(column: current, bridgeIndex: bridgeIndex, isTop: false))
                } else if bridge.left + 1 == current {
                    points.append(AmidaPoint(column: current, bridgeIndex: bridgeIndex, isTop: false))
                    current -= 1
                    points.append(AmidaPoint(column: current, bridgeIndex: bridgeIndex, isTop: false))
                }
            }
            points.append(AmidaPoint(column: current, bridgeIndex: nil, isTop: false))
            return AmidaPath(startIndex: startIndex, endIndex: current, points: points, delay: Double(startIndex) * 0.16, duration: 3.1)
        }
    }
}

private struct AmidaLayout {
    let top: CGFloat
    let bottom: CGFloat
    let columns: [AmidaColumn]
    let bridges: [AmidaLayoutBridge]

    func point(on path: AmidaPath, progress: Double) -> CGPoint {
        let concrete = path.points.map { point -> CGPoint in
            if point.isTop {
                return CGPoint(x: columns[point.column].x, y: top)
            }
            if let bridgeIndex = point.bridgeIndex {
                return CGPoint(x: columns[point.column].x, y: bridges[bridgeIndex].y)
            }
            return CGPoint(x: columns[point.column].x, y: bottom)
        }
        let target = totalLength(concrete) * CGFloat(max(0, min(1, progress)))
        var travelled: CGFloat = 0
        for index in 1..<concrete.count {
            let a = concrete[index - 1]
            let b = concrete[index]
            let segment = hypot(b.x - a.x, b.y - a.y)
            if travelled + segment >= target {
                let t = segment == 0 ? 0 : (target - travelled) / segment
                return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
            travelled += segment
        }
        return concrete.last ?? .zero
    }

    private func totalLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        return (1..<points.count).reduce(CGFloat(0)) { total, index in
            let a = points[index - 1]
            let b = points[index]
            return total + hypot(b.x - a.x, b.y - a.y)
        }
    }
}

private struct AmidaPath {
    let startIndex: Int
    let endIndex: Int
    let points: [AmidaPoint]
    let delay: Double
    let duration: Double

    func progress(at elapsed: TimeInterval) -> Double {
        let raw = (elapsed - delay) / duration
        let clamped = max(0, min(1, raw))
        return 1 - pow(1 - clamped, 3)
    }
}

private struct AmidaBridge {
    let left: Int
    let yRank: CGFloat
}

private struct AmidaPoint {
    let column: Int
    let bridgeIndex: Int?
    let isTop: Bool
}

private struct AmidaColumn {
    let x: CGFloat
}

private struct AmidaLayoutBridge {
    let index: Int
    let left: Int
    let x1: CGFloat
    let x2: CGFloat
    let y: CGFloat
}

private struct GalaxyBackground: View {
    var body: some View {
        ZStack {
            Image("andromeda-amida-bg")
                .resizable()
                .scaledToFill()
                .opacity(0.58)

            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.02, blue: 0.05).opacity(0.86),
                    Color(red: 0.04, green: 0.09, blue: 0.13).opacity(0.58),
                    Color(red: 0.12, green: 0.04, blue: 0.12).opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [.cyan.opacity(0.34), .purple.opacity(0.18), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 360
            )
            .blur(radius: 26)
            .rotationEffect(.degrees(-18))
            .scaleEffect(x: 1.5, y: 0.74)
            .offset(x: 70, y: -120)

            RadialGradient(
                colors: [.pink.opacity(0.18), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 420
            )
        }
    }
}

private struct AmidaTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 10)
            .frame(height: 40)
            .foregroundStyle(.white)
            .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.cyan.opacity(0.22)))
    }
}

private struct AmidaGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.black))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(.cyan)
            .background(.white.opacity(configuration.isPressed ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.cyan.opacity(0.28)))
    }
}

private struct AmidaStartButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.black))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [.pink.opacity(0.38), .cyan.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.pink.opacity(0.52)))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct BannerAdView: UIViewRepresentable {
    let adUnitID: String

    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView(adSize: GADAdSizeBanner)
        banner.adUnitID = adUnitID
        banner.rootViewController = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first(where: { $0.isKeyWindow })?.rootViewController
        banner.load(GADRequest())
        return banner
    }

    func updateUIView(_ uiView: GADBannerView, context: Context) {}
}

#Preview {
    QuantumAmidaView()
}
