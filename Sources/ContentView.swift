import SwiftUI
import PhotosUI
import UIKit

struct ContentView: View {
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var items: [MediaItem] = []
    @State private var startText = "1"
    @State private var endText = ""
    /// 视频裁头秒数（默认 0.05，只作用于视频，不影响图片）
    @State private var trimText = "0.05"
    @State private var isLoadingThumbs = false
    /// 每次清空 / 重新选片都 +1，用来作废还在跑的缩略图加载（否则清空后会被旧任务写回来）
    @State private var loadGeneration = 0
    @StateObject private var runner = ReorderRunner()

    private let cellCorner: CGFloat = 8

    // MARK: - 计算属性

    /// 已选中的素材（点格子可取消/恢复），起止编号都在这个序列上数
    private var selectedItems: [MediaItem] { items.filter(\.isSelected) }
    private var selectedCount: Int { selectedItems.count }

    private var startValue: Int? {
        guard let value = Int(startText.trimmingCharacters(in: .whitespaces)) else { return nil }
        return (value >= 1 && value <= selectedCount) ? value : nil
    }

    private var endValue: Int? {
        guard let value = Int(endText.trimmingCharacters(in: .whitespaces)) else { return nil }
        return (value >= 1 && value <= selectedCount) ? value : nil
    }

    /// 当前区间是否为倒序（起 > 止）
    private var isReverseRange: Bool {
        guard let start = startValue, let end = endValue else { return false }
        return start > end
    }

    /// 起 / 止互换：1→5 变成 5→1
    private func toggleDirection() {
        let start = startValue ?? 1
        let end = endValue ?? selectedCount
        startText = "\(end)"
        endText = "\(start)"
    }

    private var plan: ReorderPlan? {
        guard let start = startValue, let end = endValue else { return nil }
        return ReorderPlanner.makePlan(items: selectedItems, start: start, end: end, now: Date())
    }

    /// item.id → 编号（烧进画面的那个号）。按「起 → 止」的位次 1…M 连排，与图视交替无关
    private var numberMap: [String: Int] {
        guard let plan = plan else { return [:] }
        var map: [String: Int] = [:]
        map.reserveCapacity(plan.entries.count)
        for entry in plan.entries { map[entry.item.id] = entry.number }
        return map
    }

    private var imageCount: Int { selectedItems.filter { $0.kind == .image }.count }
    private var videoCount: Int { selectedItems.filter { $0.kind == .video }.count }

    /// 裁头秒数：非法输入回退 0.05，范围夹在 0 ~ 10 秒
    private var trimValue: Double {
        let raw = trimText
            .replacingOccurrences(of: "，", with: ".")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(raw), value.isFinite else { return 0.05 }
        return min(max(value, 0), 10)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    pickerCard
                    if items.isEmpty {
                        emptyCard
                    } else {
                        gridSection
                        rangeSection
                        if videoCount > 0 { trimSection }
                        orderSection
                    }
                }
                .padding(16)
                .padding(.bottom, 90)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("返图修复集合")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { bottomBar }
            .overlay { if runner.isRunning { progressOverlay } }
            .alert(runner.alertTitle, isPresented: $runner.showAlert) {
                Button("好", role: .cancel) { }
            } message: {
                Text(runner.alertMessage)
            }
            .onChange(of: pickerItems) { _, newValue in
                Task { await reload(newValue) }
            }
        }
    }

    // MARK: - 选片 / 清空

    private var pickerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: 0,
                matching: .any(of: [.images, .videos]),
                photoLibrary: PHPhotoLibrary.shared()
            ) {
                Label(items.isEmpty ? "选择图片和视频" : "重新选择素材",
                      systemImage: "photo.on.rectangle.angled")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            if !items.isEmpty {
                HStack(spacing: 10) {
                    Text("共 \(items.count) 个")
                    Text("已选 \(selectedCount)")
                        .foregroundStyle(selectedCount == items.count ? Color.secondary : Color.accentColor)
                    Text("图 \(imageCount)")
                    Text("视 \(videoCount)")
                    Spacer(minLength: 6)
                    Button {
                        clearAll()
                    } label: {
                        Text("清空")
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.accentColor)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// 清空一切：取消相册选择、清掉网格、复位起止
    private func clearAll() {
        loadGeneration &+= 1
        isLoadingThumbs = false
        pickerItems = []
        items = []
        startText = "1"
        endText = ""
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("怎么用").font(.headline)
            Text("1. 点上面的按钮，一次勾选要处理的图片和视频（不乱也行，程序会按相册时间排序）")
            Text("2. 网格里点某个格子可以取消 / 恢复它，没选中的不参与本次重排")
            Text("3. 用「起 / 止」两个数字圈出这一段；起 > 止 就是倒序（起 9 止 1 → 左上编号 9、右下编号 1）")
            Text("4. 视频默认先裁掉开头 0.05 秒（可在「视频裁头」改，填 0 就不裁），再烧编号写入相册；图片不裁")
            Text("5. 点底部「重新排列」：先写一张红色分隔图进相册，再按 图1 视1 图2 视2… 的顺序批量写入新文件，每张右上角带编号")
            Text("6. 原片一条不动，新文件进系统相册「最近项目」")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 网格

    private var gridSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("素材 · 左上小字=原始序号，右上红字=编号")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if selectedCount < items.count {
                    Button("全选") { selectAll() }
                        .font(.footnote.weight(.medium))
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color.accentColor)
                }
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                spacing: 6
            ) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    thumbCell(index: index, item: item)
                }
            }

            Text("点一下格子＝取消选取，再点一下＝恢复")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if isLoadingThumbs {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("缩略图加载中…").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func toggle(_ index: Int) {
        guard items.indices.contains(index) else { return }
        let oldCount = selectedCount
        let oldStart = Int(startText)
        let oldEnd = Int(endText)

        items[index].isSelected.toggle()
        let newCount = selectedCount

        // 区间原本覆盖全部已选 → 跟着点选一起伸缩，新点的格子立刻拿到编号
        if oldCount > 0, let s = oldStart, let e = oldEnd, s == 1, e == oldCount {
            startText = "1"
            endText = "\(newCount)"
        } else if oldCount > 0, let s = oldStart, let e = oldEnd, s == oldCount, e == 1 {
            startText = "\(newCount)"
            endText = "1"
        } else {
            clampRange()
        }

        if newCount == 0 {
            startText = "1"
            endText = ""
        }
    }

    private func selectAll() {
        let wasReverse = (Int(startText) ?? 1) > (Int(endText) ?? 1)
        for index in items.indices { items[index].isSelected = true }
        if wasReverse {
            startText = "\(selectedCount)"
            endText = "1"
        } else {
            startText = "1"
            endText = "\(selectedCount)"
        }
    }

    /// 起止数字跟着「已选数量」收口，避免取消选取后还停在不存在的序号上
    private func clampRange() {
        let maxValue = selectedCount
        guard maxValue > 0 else {
            startText = "1"
            endText = ""
            return
        }
        if let value = Int(startText), value > maxValue { startText = "\(maxValue)" }
        if let value = Int(endText), value > maxValue { endText = "\(maxValue)" }
        if Int(startText) == nil { startText = "1" }
        if Int(endText) == nil { endText = "\(maxValue)" }
    }

    private func thumbCell(index: Int, item: MediaItem) -> some View {
        let shape = RoundedRectangle(cornerRadius: cellCorner, style: .continuous)
        let number = numberMap[item.id]
        let selected = item.isSelected
        let dim: Double = selected ? (number == nil ? 0.45 : 0) : 0.66

        return Color(uiColor: .secondarySystemFill)
            // 尺寸只由色块决定，缩略图绝不参与布局（否则横屏视频会把格子撑爆）
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    if let thumb = item.thumb {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    } else {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
            }
            .clipShape(shape)
            .overlay { shape.fill(Color.black.opacity(dim)) }
            .overlay(alignment: .topLeading) {
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.62), in: Capsule())
                    .padding(4)
                    .opacity(selected ? 1 : 0.7)
            }
            .overlay(alignment: .topTrailing) {
                if let finalNumber = number {
                    Text("\(finalNumber)")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 1, green: 0.90, blue: 0.0))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 26, minHeight: 26)
                        .background(Color(red: 0.76, green: 0.06, blue: 0.06), in: Capsule())
                        .overlay { Capsule().stroke(Color.white, lineWidth: 1.5) }
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .padding(4)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: item.kind.systemImage)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Color.black.opacity(0.55), in: Circle())
                    .padding(4)
                    .opacity(selected ? 1 : 0.75)
            }
            .overlay(alignment: .bottomLeading) {
                if !selected {
                    Image(systemName: "slash.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                        .padding(4)
                }
            }
            .overlay {
                if selected {
                    shape.stroke(number == nil ? Color(uiColor: .systemGray3) : Color.accentColor,
                                 lineWidth: number == nil ? 1.5 : 2.5)
                }
            }
            .contentShape(shape)
            .onTapGesture { toggle(index) }
    }

    // MARK: - 区间

    private var rangeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("处理区间").font(.headline)
                Spacer(minLength: 8)
                Button {
                    toggleDirection()
                } label: {
                    HStack(spacing: 4) {
                        Text(isReverseRange ? "倒序" : "顺序")
                        Image(systemName: isReverseRange ? "arrow.up" : "arrow.down")
                            .font(.caption.weight(.bold))
                    }
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isReverseRange
                                ? Color.orange.opacity(0.18)
                                : Color(uiColor: .secondarySystemFill))
                    .foregroundStyle(isReverseRange ? Color.orange : Color.secondary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.borderless)
                .disabled(selectedCount < 2)
            }

            HStack(spacing: 12) {
                numberField(title: "起", text: $startText)
                numberField(title: "止", text: $endText)
                Button("全部") {
                    let reverse = (Int(startText) ?? 1) > (Int(endText) ?? 1)
                    startText = reverse ? "\(selectedCount)" : "1"
                    endText = reverse ? "1" : "\(selectedCount)"
                }
                .buttonStyle(.bordered)
            }

            if let start = startValue, let end = endValue {
                let amount = abs(start - end) + 1
                let isReverse = start > end
                VStack(alignment: .leading, spacing: 4) {
                    Text(isReverse
                         ? "倒序：从第 \(start) 个往第 \(end) 个走，共 \(amount) 个"
                         : "正序：从第 \(start) 个往第 \(end) 个走，共 \(amount) 个")
                    Text("编号从「起」那格开始、朝「止」的方向每格 +1：编号 1 = 第 \(start) 个，编号 \(amount) = 第 \(end) 个")
                    if hasBothKinds(in: start, end: end) {
                        Text("图文混排：编号在网格里是 1、2、3… 连排的；相册里的先后按 图1 视1 图2 视2 交替，所以号在相册里会跳着出现")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
                Text(selectedCount == 0
                     ? "至少选 1 个素材（点格子恢复选取）"
                     : "起止数字都要在 1 ~ \(selectedCount) 之间（起 > 止 就是倒序编号）")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 视频裁头

    private var trimSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("视频裁头").font(.headline)
                Spacer(minLength: 6)
                Text("只影响视频").font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                TextField("0.05", text: $trimText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 76)
                    .padding(.vertical, 9)
                    .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9))
                Text("秒").font(.footnote).foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Button("恢复 0.05") { trimText = "0.05" }
                    .buttonStyle(.bordered)
            }

            Text(trimValue > 0
                 ? "每个视频在烧编号前先裁掉开头 \(formatSeconds(trimValue)) 秒，再写入相册；图片不受影响，原视频一条不删。默认 0.05 秒就是解决微信转发黑封面的那个值。"
                 : "填 0 = 不裁头，视频只烧编号直接写入。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if trimValue > 0 {
                Text("裁头与烧号在同一次重编码里完成，只压一次画质")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func formatSeconds(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func hasBothKinds(in start: Int, end: Int) -> Bool {
        let lower = min(start, end)
        let upper = max(start, end)
        guard upper >= lower, upper <= selectedItems.count else { return false }
        let slice = selectedItems[(lower - 1)...(upper - 1)]
        return slice.contains { $0.kind == .image } && slice.contains { $0.kind == .video }
    }

    private func numberField(title: String, text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("1", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 58)
                .padding(.vertical, 9)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    // MARK: - 顺序预览

    private var orderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("重排后的顺序").font(.headline)

            if let plan = plan, !plan.entries.isEmpty, let start = startValue, let end = endValue {
                Text("相册顺序：" + (["分隔图"] + plan.entries.enumerated().map { "\($0.offset + 1)·\($0.element.item.kind.short)" })
                    .joined(separator: " → "))
                    .font(.subheadline.monospacedDigit())
                    .fixedSize(horizontal: false, vertical: true)

                Text("上面是相册里从上往下的先后（图、视交替）；每个素材烧进画面的编号见网格右上角，是 1、2、3… 连排的另一套号")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                let amount = plan.entries.count
                Text(start <= end
                     ? "正序：编号 1 给第 \(start) 个、排最前；编号 \(amount) 给第 \(end) 个、排最后"
                     : "倒序：编号 1 给第 \(start) 个、排最前；编号 \(amount) 给第 \(end) 个、排最后（第 \(start) 个在网格里靠后，编号反而最小）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("先填写有效的起止数字")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 底部按钮

    private var bottomTitle: String {
        if let plan = plan, !plan.entries.isEmpty {
            return "重新排列（\(plan.entries.count) 个）"
        }
        return "重新排列"
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                guard let plan = plan else { return }
                Task {
                    await runner.run(
                        plan: plan,
                        trimSeconds: videoCount > 0 ? trimValue : 0
                    )
                }
            } label: {
                Text(bottomTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(plan == nil ? Color.gray.opacity(0.35) : Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(plan == nil || runner.isRunning)
            .padding(16)
        }
        .background(.bar)
    }

    private var progressOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView(value: runner.fraction)
                    .frame(width: 210)
                Text(runner.status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(videoCount > 0 && trimValue > 0
                     ? "视频要重编码（裁头 + 烧号），会比较慢，别锁屏"
                     : "视频需要重编码，会比较慢，别锁屏")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - 载入

    @MainActor
    private func reload(_ picked: [PhotosPickerItem]) async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoadingThumbs = false

        let ids = picked.compactMap { $0.itemIdentifier }
        guard !ids.isEmpty else {
            items = []
            startText = "1"
            endText = ""
            return
        }

        isLoadingThumbs = true
        var loaded = LibraryService.fetchItems(ids: ids)
        guard generation == loadGeneration else { return }

        items = loaded
        startText = "1"
        endText = "\(loaded.count)"

        for index in loaded.indices {
            guard generation == loadGeneration else { return }
            if let thumb = await LibraryService.thumbnail(
                for: loaded[index].id,
                size: CGSize(width: 320, height: 320)
            ) {
                guard generation == loadGeneration else { return }
                loaded[index].thumb = thumb
                items = loaded
            }
        }

        guard generation == loadGeneration else { return }
        isLoadingThumbs = false
    }
}
