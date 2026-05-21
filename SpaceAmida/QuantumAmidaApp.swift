import SwiftUI
import AudioToolbox
import AppTrackingTransparency

@main
struct QuantumAmidaApp: App {
    var body: some Scene {
        WindowGroup {
            QuantumAmidaView()
        }
    }
}

struct QuantumAmidaView: View {
    @State private var laneCount = 5.0
    @State private var names = ["ミラ", "レイ", "ノア", "カイ", "ユリ", "ゼン", "アオ", "ルナ"]
    @State private var prizes = ["船長", "通信士", "観測員", "整備士", "補給係", "航法士", "記録係", "自由枠"]
    @State private var board = SpaceAmidaBoard(count: 5)
    @State private var startDate: Date?
    @State private var revealedLanes: Set<Int> = []
    @State private var soundEnabled = true
    @State private var isRunning = false
    @State private var history: [String] = []
    @AppStorage("didRequestTrackingPermission") private var didRequestTrackingPermission = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var iPad: Bool { sizeClass == .regular }
    private var count: Int { Int(laneCount.rounded()) }
    private var visibleNames: [String] { Array(names.prefix(count)) }
    private var visiblePrizes: [String] { Array(prizes.prefix(count)) }

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width >= 760
            let isCompact = proxy.size.height < 750
            let boardHeight = isWide
                ? min(max(proxy.size.height - 250, 380), 720)
                : isCompact
                    ? min(max(proxy.size.height * 0.38, 280), 420)
                    : min(max(proxy.size.height * 0.42, 320), 500)

            ZStack {
                SpaceBackground()
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        header
                        mainPanels(isWide: isWide, boardHeight: boardHeight)
                    }
                    .frame(maxWidth: isWide ? 1200 : .infinity)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, isWide ? 24 : 12)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            normalizeArrays()
            rebuildBoard()
            requestTrackingPermissionIfNeeded()
        }
        .onChange(of: count) { _ in
            normalizeArrays()
            rebuildBoard()
        }
        .onReceive(Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()) { date in
            advanceAnimation(date)
        }
    }

    @ViewBuilder
    private func mainPanels(isWide: Bool, boardHeight: CGFloat) -> some View {
        if isWide {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 10) {
                    commandPanel
                    historyPanel
                }
                .frame(width: 400)

                VStack(spacing: 10) {
                    boardPanel(height: boardHeight)
                    resultPanel
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 10) {
                commandPanel
                boardPanel(height: boardHeight)
                resultPanel
                historyPanel
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: iPad ? 18 : 12) {
            VStack(alignment: .leading, spacing: iPad ? 8 : 6) {
                Text("SPACE AMIDA")
                    .font(.system(size: iPad ? 16 : 12, weight: .black, design: .monospaced))
                    .foregroundStyle(.cyan)
                    .tracking(1.8)

                Text("スペースあみだ")
                    .font(.system(size: iPad ? 42 : 32, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                Text("星のレーンを走らせて、今日の役割を決める。")
                    .font(.system(size: iPad ? 18 : 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                soundEnabled.toggle()
                playTap()
            } label: {
                Image(systemName: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: iPad ? 24 : 18, weight: .bold))
                    .frame(width: iPad ? 56 : 46, height: iPad ? 56 : 46)
                    .foregroundStyle(soundEnabled ? .cyan : .white.opacity(0.45))
                    .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.18)))
            }
            .accessibilityLabel(soundEnabled ? "効果音をオフ" : "効果音をオン")
        }
    }

    private var commandPanel: some View {
        VStack(spacing: iPad ? 14 : 10) {
            HStack {
                Label("参加レーン", systemImage: "slider.horizontal.3")
                    .font(.system(size: iPad ? 16 : 12, weight: .black))
                    .foregroundStyle(.white.opacity(0.68))
                Spacer()
                Text("\(count)")
                    .font(.system(size: iPad ? 26 : 20, weight: .black))
                    .foregroundStyle(.yellow)
                    .monospacedDigit()
            }

            Slider(value: $laneCount, in: 2...8, step: 1)
                .tint(.cyan)
                .disabled(isRunning)

            VStack(alignment: .leading, spacing: iPad ? 8 : 6) {
                sectionTitle("クルー")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: iPad ? 160 : 130), spacing: iPad ? 10 : 8)], spacing: iPad ? 10 : 8) {
                    ForEach(0..<count, id: \.self) { index in
                        FieldTile(index: index, title: "レーン \(index + 1)", text: binding($names, index: index), disabled: isRunning, iPad: iPad)
                    }
                }
            }

            VStack(alignment: .leading, spacing: iPad ? 8 : 6) {
                HStack {
                    sectionTitle("ゴール")
                    Spacer()
                    Button {
                        for index in 0..<count {
                            prizes[index] = names[index].isEmpty ? "ゴール \(index + 1)" : names[index]
                        }
                        revealedLanes = []
                        playTap()
                    } label: {
                        Label("名前を使う", systemImage: "arrow.down.doc.fill")
                    }
                    .font(.system(size: iPad ? 15 : 12, weight: .bold))
                    .foregroundStyle(.mint)
                    .disabled(isRunning)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: iPad ? 160 : 130), spacing: iPad ? 10 : 8)], spacing: iPad ? 10 : 8) {
                    ForEach(0..<count, id: \.self) { index in
                        FieldTile(index: index, title: "結果 \(index + 1)", text: binding($prizes, index: index), disabled: isRunning, iPad: iPad)
                    }
                }
            }

            HStack(spacing: iPad ? 12 : 8) {
                Button {
                    rebuildBoard()
                    playTap()
                } label: {
                    Label("組み直す", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(SecondarySpaceButtonStyle(iPad: iPad))
                .disabled(isRunning)

                Button {
                    startRun()
                } label: {
                    Label(isRunning ? "航行中" : "スタート", systemImage: isRunning ? "bolt.fill" : "sparkles")
                }
                .buttonStyle(PrimarySpaceButtonStyle(iPad: iPad))
                .disabled(isRunning)
            }
        }
        .padding(iPad ? 18 : 12)
        .background(.black.opacity(0.44), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.cyan.opacity(0.22)))
    }

    private func boardPanel(height: CGFloat) -> some View {
        TimelineView(.animation) { timeline in
            let elapsed = startDate.map { timeline.date.timeIntervalSince($0) } ?? 0
            SpaceAmidaCanvas(
                board: board,
                names: visibleNames,
                prizes: visiblePrizes,
                elapsed: elapsed,
                isRunning: isRunning,
                revealedLanes: revealedLanes
            )
            .frame(height: height)
            .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.cyan.opacity(0.26)))
        }
    }

    private var resultPanel: some View {
        let outputs = board.outputs(for: visibleNames)
        return VStack(alignment: .leading, spacing: iPad ? 14 : 10) {
            HStack {
                sectionTitle("結果")
                Spacer()
                Text(revealedLanes.count == count ? "COMPLETE" : "\(revealedLanes.count)/\(count)")
                    .font(.system(size: iPad ? 15 : 12, weight: .black))
                    .foregroundStyle(revealedLanes.count == count ? .mint : .white.opacity(0.58))
                    .monospacedDigit()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: iPad ? 180 : 150), spacing: iPad ? 10 : 8)], spacing: iPad ? 10 : 8) {
                ForEach(0..<count, id: \.self) { index in
                    let revealed = revealedLanes.contains(index)
                    VStack(alignment: .leading, spacing: iPad ? 8 : 6) {
                        Text(prizes[index].isEmpty ? "ゴール \(index + 1)" : prizes[index])
                            .font(.system(size: iPad ? 15 : 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text(revealed ? outputs[index] : "待機中")
                            .font(.system(size: iPad ? 20 : 17, weight: .black))
                            .foregroundStyle(revealed ? .white : .white.opacity(0.48))
                            .lineLimit(3)
                            .minimumScaleFactor(0.62)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: iPad ? 66 : 56, alignment: .leading)
                    .padding(iPad ? 14 : 10)
                    .background(revealed ? .mint.opacity(0.15) : .white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(revealed ? .mint.opacity(0.48) : .white.opacity(0.11)))
                }
            }
        }
        .padding(iPad ? 14 : 10)
        .background(.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 8))
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: iPad ? 14 : 10) {
            HStack {
                sectionTitle("ログ")
                Spacer()
                Button("消す") {
                    history.removeAll()
                    playTap()
                }
                .font(.system(size: iPad ? 15 : 12, weight: .bold))
                .foregroundStyle(history.isEmpty ? .white.opacity(0.28) : .white.opacity(0.72))
                .disabled(history.isEmpty)
            }

            if history.isEmpty {
                Text("完了した結果がここに残ります。")
                    .font(.system(size: iPad ? 16 : 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.48))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(iPad ? 18 : 14)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: iPad ? 10 : 8) {
                    ForEach(Array(history.prefix(4).enumerated()), id: \.offset) { index, value in
                        HStack(spacing: iPad ? 14 : 10) {
                            Text("#\(index + 1)")
                                .font(.system(size: iPad ? 15 : 12, weight: .black))
                                .foregroundStyle(.cyan)
                                .frame(width: iPad ? 40 : 32, alignment: .leading)
                            Text(value)
                                .font(.system(size: iPad ? 17 : 15, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.86))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                        }
                        .padding(iPad ? 16 : 12)
                        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: iPad ? 16 : 12, weight: .black))
            .foregroundStyle(.white.opacity(0.66))
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
            names.append("クルー \(names.count + 1)")
        }
        while prizes.count < 8 {
            prizes.append("ゴール \(prizes.count + 1)")
        }
    }

    private func rebuildBoard() {
        board = SpaceAmidaBoard(count: count)
        startDate = nil
        revealedLanes = []
        isRunning = false
    }

    private func startRun() {
        startDate = Date()
        revealedLanes = []
        isRunning = true
        playTap()
    }

    private func advanceAnimation(_ date: Date) {
        guard isRunning, let startDate else { return }
        let elapsed = date.timeIntervalSince(startDate)
        var next = revealedLanes
        for path in board.paths where elapsed >= path.delay + path.duration {
            next.insert(path.endIndex)
        }

        if next != revealedLanes {
            revealedLanes = next
            playTap()
        }

        if next.count == count {
            isRunning = false
            let outputs = board.outputs(for: visibleNames)
            let summary = (0..<count).map { index in
                "\(prizes[index]): \(outputs[index])"
            }.joined(separator: " / ")
            history.insert(summary, at: 0)
            if history.count > 8 {
                history.removeLast()
            }
        }
    }

    private func playTap() {
        guard soundEnabled else { return }
        AudioServicesPlaySystemSound(1104)
    }

    private func requestTrackingPermissionIfNeeded() {
        guard !didRequestTrackingPermission else { return }
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
            didRequestTrackingPermission = true
            return
        }

        didRequestTrackingPermission = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            ATTrackingManager.requestTrackingAuthorization { _ in }
        }
    }
}

private struct FieldTile: View {
    let index: Int
    let title: String
    @Binding var text: String
    let disabled: Bool
    var iPad: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: iPad ? 8 : 6) {
            Text(title)
                .font(.system(size: iPad ? 13 : 10, weight: .black))
                .foregroundStyle(SpaceAmidaBoard.palette[index % SpaceAmidaBoard.palette.count])
            TextField(title, text: $text)
                .textFieldStyle(SpaceFieldStyle(iPad: iPad))
                .font(.system(size: iPad ? 17 : 15, weight: .semibold))
                .disabled(disabled)
        }
    }
}

private struct SpaceAmidaCanvas: View {
    let board: SpaceAmidaBoard
    let names: [String]
    let prizes: [String]
    let elapsed: TimeInterval
    let isRunning: Bool
    let revealedLanes: Set<Int>

    var body: some View {
        Canvas { context, size in
            drawBackdrop(context: &context, size: size)
            let layout = board.layout(in: size)
            drawGrid(context: &context, layout: layout)
            drawLabels(context: &context, layout: layout, size: size)
            drawParticles(context: &context, layout: layout)

            if isRunning {
                drawPulse(context: &context, size: size)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func drawBackdrop(context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [
                Color(red: 0.01, green: 0.02, blue: 0.05),
                Color(red: 0.04, green: 0.07, blue: 0.11),
                Color(red: 0.10, green: 0.03, blue: 0.10)
            ]),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: size.width, y: size.height)
        ))

        var blurContext = context
        blurContext.addFilter(.blur(radius: 24))
        let nebula = Path(ellipseIn: CGRect(x: size.width * 0.12, y: size.height * 0.12, width: size.width * 0.86, height: size.height * 0.42))
        blurContext.fill(nebula, with: .radialGradient(
            Gradient(colors: [.cyan.opacity(0.34), .pink.opacity(0.22), .clear]),
            center: CGPoint(x: size.width * 0.58, y: size.height * 0.34),
            startRadius: 12,
            endRadius: size.width * 0.55
        ))

        for index in 0..<72 {
            let x = CGFloat((index * 47) % 103) / 102 * size.width
            let y = CGFloat((index * 71) % 109) / 108 * size.height
            let alpha = 0.22 + Double((index * 13) % 6) * 0.06
            let dot = Path(ellipseIn: CGRect(x: x, y: y, width: 1.3, height: 1.3))
            context.fill(dot, with: .color(.white.opacity(alpha)))
        }
    }

    private func drawGrid(context: inout GraphicsContext, layout: SpaceAmidaLayout) {
        var glow = context
        glow.addFilter(.shadow(color: .cyan.opacity(0.72), radius: 12))

        for column in layout.columns {
            var line = Path()
            line.move(to: CGPoint(x: column.x, y: layout.top))
            line.addLine(to: CGPoint(x: column.x, y: layout.bottom))
            glow.stroke(line, with: .color(.cyan.opacity(0.46)), lineWidth: 7)
            context.stroke(line, with: .color(.white.opacity(0.78)), lineWidth: 1.6)
        }

        for bridge in layout.bridges {
            let color = SpaceAmidaBoard.palette[bridge.index % SpaceAmidaBoard.palette.count]
            var line = Path()
            line.move(to: CGPoint(x: bridge.x1, y: bridge.y))
            line.addLine(to: CGPoint(x: bridge.x2, y: bridge.y))
            glow.stroke(line, with: .color(color.opacity(0.68)), lineWidth: 7)
            context.stroke(line, with: .color(.white.opacity(0.84)), lineWidth: 1.8)
        }
    }

    private func drawLabels(context: inout GraphicsContext, layout: SpaceAmidaLayout, size: CGSize) {
        let isLarge = size.width > 500
        let labelOffset: CGFloat = isLarge ? 28 : 22
        for index in layout.columns.indices {
            drawBadge(
                context: &context,
                text: names[safe: index]?.isEmpty == false ? names[index] : "クルー \(index + 1)",
                point: CGPoint(x: layout.columns[index].x, y: layout.top - labelOffset),
                color: SpaceAmidaBoard.palette[index % SpaceAmidaBoard.palette.count],
                isLarge: isLarge
            )
            drawBadge(
                context: &context,
                text: prizes[safe: index]?.isEmpty == false ? prizes[index] : "ゴール \(index + 1)",
                point: CGPoint(x: layout.columns[index].x, y: layout.bottom + labelOffset),
                color: revealedLanes.contains(index) ? .mint : .white.opacity(0.42),
                isLarge: isLarge
            )
        }
    }

    private func drawBadge(context: inout GraphicsContext, text: String, point: CGPoint, color: Color, isLarge: Bool) {
        let displayText = text.count > 8 ? String(text.prefix(8)) + "…" : text
        let font: Font = isLarge ? .caption.weight(.black) : .caption2.weight(.black)
        let resolved = context.resolve(Text(displayText).font(font).foregroundColor(.white))
        let maxW: CGFloat = isLarge ? 180 : 150
        let badgeH: CGFloat = isLarge ? 36 : 32
        let minW: CGFloat = isLarge ? 72 : 62
        let width = min(max(resolved.measure(in: CGSize(width: maxW, height: badgeH)).width + 24, minW), maxW)
        let rect = CGRect(x: point.x - width / 2, y: point.y - badgeH / 2, width: width, height: badgeH)
        context.fill(Path(roundedRect: rect, cornerRadius: 10), with: .color(.black.opacity(0.72)))
        context.stroke(Path(roundedRect: rect, cornerRadius: 10), with: .color(color.opacity(0.72)), lineWidth: 1)
        context.draw(resolved, at: point)
    }

    private func drawParticles(context: inout GraphicsContext, layout: SpaceAmidaLayout) {
        for path in board.paths {
            let progress = path.progress(at: elapsed)
            guard progress > 0 else { continue }

            let color = SpaceAmidaBoard.palette[path.startIndex % SpaceAmidaBoard.palette.count]
            let point = layout.point(on: path, progress: progress)
            let trailStart = max(0, progress - 0.18)

            var trail = Path()
            for step in 0...10 {
                let p = trailStart + (progress - trailStart) * Double(step) / 10
                let trailPoint = layout.point(on: path, progress: p)
                if step == 0 {
                    trail.move(to: trailPoint)
                } else {
                    trail.addLine(to: trailPoint)
                }
            }

            var glow = context
            glow.addFilter(.shadow(color: color.opacity(0.9), radius: 16))
            glow.stroke(trail, with: .color(color.opacity(0.82)), lineWidth: 7)
            context.stroke(trail, with: .color(.white.opacity(0.86)), lineWidth: 1.6)

            let ship = Path(ellipseIn: CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16))
            glow.fill(ship, with: .color(color))
            context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)), with: .color(.white))
        }
    }

    private func drawPulse(context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let pulse = 0.5 + sin(elapsed * 7) * 0.5
        let radius = 26 + pulse * 24
        context.stroke(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(.cyan.opacity(0.24)),
            lineWidth: 3
        )
    }
}

private struct SpaceAmidaBoard {
    static let palette: [Color] = [.cyan, .pink, .yellow, .mint, .orange, .purple, .green, .indigo]

    let count: Int
    let bridges: [SpaceAmidaBridge]
    let paths: [SpaceAmidaPath]

    init(count: Int) {
        let safeCount = max(2, min(8, count))
        self.count = safeCount
        self.bridges = SpaceAmidaBoard.makeBridges(count: safeCount)
        self.paths = SpaceAmidaBoard.makePaths(count: safeCount, bridges: bridges)
    }

    func layout(in size: CGSize) -> SpaceAmidaLayout {
        let isLarge = size.width > 500
        let top: CGFloat = isLarge ? 58 : 46
        let bottom = max(top + 120, size.height - (isLarge ? 58 : 46))
        let side = max(CGFloat(44), min(CGFloat(120), size.width * 0.12))
        let left = side
        let right = size.width - side
        let gap = (right - left) / CGFloat(max(1, count - 1))
        let columns = (0..<count).map { SpaceAmidaColumn(x: left + CGFloat($0) * gap) }
        let layoutBridges = bridges.enumerated().map { index, bridge in
            SpaceAmidaLayoutBridge(
                index: index,
                left: bridge.left,
                x1: columns[bridge.left].x,
                x2: columns[bridge.left + 1].x,
                y: top + (bottom - top) * bridge.yRank
            )
        }
        return SpaceAmidaLayout(top: top, bottom: bottom, columns: columns, bridges: layoutBridges)
    }

    func outputs(for names: [String]) -> [String] {
        var outputs = Array(repeating: "", count: count)
        for path in paths {
            let value = names[safe: path.startIndex] ?? "クルー \(path.startIndex + 1)"
            outputs[path.endIndex] = value.isEmpty ? "クルー \(path.startIndex + 1)" : value
        }
        return outputs
    }

    private static func makeBridges(count: Int) -> [SpaceAmidaBridge] {
        let rowCount = max(8, min(24, count * 3 + 4))
        var bridges: [SpaceAmidaBridge] = []
        var previousLeft: Int?

        for row in 0..<rowCount {
            var candidates = Array(0..<(count - 1))
            if let previousLeft {
                candidates.removeAll { abs($0 - previousLeft) <= 0 }
            }
            if candidates.isEmpty {
                candidates = Array(0..<(count - 1))
            }

            let seed = Int.random(in: 0..<max(1, candidates.count))
            let left = candidates[(row + seed) % candidates.count]
            previousLeft = left
            bridges.append(SpaceAmidaBridge(left: left, yRank: CGFloat(row + 1) / CGFloat(rowCount + 1)))
        }

        return bridges
    }

    private static func makePaths(count: Int, bridges: [SpaceAmidaBridge]) -> [SpaceAmidaPath] {
        (0..<count).map { startIndex in
            var current = startIndex
            var points = [SpaceAmidaPoint(column: current, bridgeIndex: nil, isTop: true)]

            for (bridgeIndex, bridge) in bridges.enumerated() {
                if bridge.left == current {
                    points.append(SpaceAmidaPoint(column: current, bridgeIndex: bridgeIndex, isTop: false))
                    current += 1
                    points.append(SpaceAmidaPoint(column: current, bridgeIndex: bridgeIndex, isTop: false))
                } else if bridge.left + 1 == current {
                    points.append(SpaceAmidaPoint(column: current, bridgeIndex: bridgeIndex, isTop: false))
                    current -= 1
                    points.append(SpaceAmidaPoint(column: current, bridgeIndex: bridgeIndex, isTop: false))
                }
            }

            points.append(SpaceAmidaPoint(column: current, bridgeIndex: nil, isTop: false))
            return SpaceAmidaPath(startIndex: startIndex, endIndex: current, points: points, delay: Double(startIndex) * 0.14, duration: 3.2)
        }
    }
}

private struct SpaceAmidaLayout {
    let top: CGFloat
    let bottom: CGFloat
    let columns: [SpaceAmidaColumn]
    let bridges: [SpaceAmidaLayoutBridge]

    func point(on path: SpaceAmidaPath, progress: Double) -> CGPoint {
        let points = path.points.map { point -> CGPoint in
            if point.isTop {
                return CGPoint(x: columns[point.column].x, y: top)
            }
            if let bridgeIndex = point.bridgeIndex, bridges.indices.contains(bridgeIndex) {
                return CGPoint(x: columns[point.column].x, y: bridges[bridgeIndex].y)
            }
            return CGPoint(x: columns[point.column].x, y: bottom)
        }

        let targetLength = totalLength(points) * CGFloat(max(0, min(1, progress)))
        var distance: CGFloat = 0

        for index in 1..<points.count {
            let a = points[index - 1]
            let b = points[index]
            let segment = hypot(b.x - a.x, b.y - a.y)
            if distance + segment >= targetLength {
                let t = segment == 0 ? 0 : (targetLength - distance) / segment
                return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
            distance += segment
        }

        return points.last ?? .zero
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

private struct SpaceAmidaPath {
    let startIndex: Int
    let endIndex: Int
    let points: [SpaceAmidaPoint]
    let delay: Double
    let duration: Double

    func progress(at elapsed: TimeInterval) -> Double {
        let raw = (elapsed - delay) / duration
        let clamped = max(0, min(1, raw))
        return 1 - pow(1 - clamped, 3)
    }
}

private struct SpaceAmidaBridge {
    let left: Int
    let yRank: CGFloat
}

private struct SpaceAmidaPoint {
    let column: Int
    let bridgeIndex: Int?
    let isTop: Bool
}

private struct SpaceAmidaColumn {
    let x: CGFloat
}

private struct SpaceAmidaLayoutBridge {
    let index: Int
    let left: Int
    let x1: CGFloat
    let x2: CGFloat
    let y: CGFloat
}

private struct SpaceBackground: View {
    var body: some View {
        ZStack {
            Image("andromeda-amida-bg")
                .resizable()
                .scaledToFill()
                .opacity(0.56)

            LinearGradient(
                colors: [
                    Color(red: 0.01, green: 0.02, blue: 0.06).opacity(0.88),
                    Color(red: 0.02, green: 0.09, blue: 0.12).opacity(0.68),
                    Color(red: 0.12, green: 0.03, blue: 0.10).opacity(0.78)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(colors: [.cyan.opacity(0.34), .clear], center: .topTrailing, startRadius: 0, endRadius: 430)
            RadialGradient(colors: [.pink.opacity(0.22), .clear], center: .bottomLeading, startRadius: 0, endRadius: 460)
        }
    }
}

private struct SpaceFieldStyle: TextFieldStyle {
    var iPad: Bool = false
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, iPad ? 14 : 10)
            .frame(minHeight: iPad ? 48 : 38)
            .foregroundStyle(.white)
            .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.cyan.opacity(0.22)))
    }
}

private struct SecondarySpaceButtonStyle: ButtonStyle {
    var iPad: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: iPad ? 20 : 17, weight: .black))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity)
            .frame(minHeight: iPad ? 56 : 46)
            .foregroundStyle(.cyan)
            .background(.white.opacity(configuration.isPressed ? 0.13 : 0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.cyan.opacity(0.28)))
    }
}

private struct PrimarySpaceButtonStyle: ButtonStyle {
    var iPad: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: iPad ? 20 : 17, weight: .black))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity)
            .frame(minHeight: iPad ? 56 : 46)
            .foregroundStyle(.black)
            .background(
                LinearGradient(colors: [.yellow, .mint, .cyan], startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.38)))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}


#Preview {
    QuantumAmidaView()
}
