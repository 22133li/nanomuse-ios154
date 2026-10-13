import SwiftUI

// MARK: - 定时任务（v1：本机存储）
//
// 客户端目前没有用户级定时任务的后端接口（代码库里的 cron/scheduled
// 命中全部是内部后台保活任务），所以 v1 用 UserDefaults 做本地持久化，
// 页面只管理"任务定义"（名称 / 执行内容 / 周期 / 开关）。将来接后端时，
// 把 NanoMuseScheduledTaskStore 的 load/save 换成网络调用即可，
// recordRun(_:) 已经预留了"上次执行时间"的写入点。

// MARK: - 数据模型

/// 用户定义的定时任务。
struct NanoMuseScheduledTask: Identifiable, Codable, Equatable {
    var id: UUID
    /// 任务名称，如"每天早报"
    var name: String
    /// 触发时让 agent 做什么（自然语言指令）
    var prompt: String
    var schedule: NanoMuseTaskSchedule
    var isEnabled: Bool
    var createdAt: Date
    var lastRunAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        schedule: NanoMuseTaskSchedule,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        lastRunAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.schedule = schedule
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.lastRunAt = lastRunAt
    }
}

/// 任务周期。预设覆盖常见需求，custom 兜底任意 cron 表达式。
enum NanoMuseTaskSchedule: Codable, Equatable {
    /// 每小时的第 minute 分执行（0–59）
    case hourly(minute: Int)
    /// 每天 hour:minute 执行
    case daily(hour: Int, minute: Int)
    /// 每周 weekday（1=周日…7=周六，对应 Calendar.weekday）hour:minute 执行
    case weekly(weekday: Int, hour: Int, minute: Int)
    /// 每月 day 日（1–28）hour:minute 执行
    case monthly(day: Int, hour: Int, minute: Int)
    /// 自定义 cron（分 时 日 月 周）
    case custom(cron: String)

    /// 列表里展示的中文周期描述。
    var chineseDescription: String {
        switch self {
        case .hourly(let minute):
            return minute == 0 ? "每小时整点" : "每小时的第 \(minute) 分"
        case .daily(let hour, let minute):
            return "每天 \(Self.timeString(hour: hour, minute: minute))"
        case .weekly(let weekday, let hour, let minute):
            return "每\(Self.weekdayName(weekday)) \(Self.timeString(hour: hour, minute: minute))"
        case .monthly(let day, let hour, let minute):
            return "每月 \(day) 日 \(Self.timeString(hour: hour, minute: minute))"
        case .custom(let cron):
            return "自定义：\(cron)"
        }
    }

    /// 换算成标准 cron 表达式（预设转 custom 时用）。
    var cronExpression: String {
        switch self {
        case .hourly(let minute):
            return "\(minute) * * * *"
        case .daily(let hour, let minute):
            return "\(minute) \(hour) * * *"
        case .weekly(let weekday, let hour, let minute):
            // Calendar weekday 1=周日；cron 周日是 0（或 7）
            let cronWeekday = weekday == 1 ? 0 : weekday - 1
            return "\(minute) \(hour) * * \(cronWeekday)"
        case .monthly(let day, let hour, let minute):
            return "\(minute) \(hour) \(day) * *"
        case .custom(let cron):
            return cron
        }
    }

    /// 下一次执行时间（custom 解析不了，返回 nil）。
    func nextRun(after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .hourly(let minute):
            var comps = calendar.dateComponents([.year, .month, .day, .hour], from: date)
            comps.minute = minute
            comps.second = 0
            guard let base = calendar.date(from: comps) else { return nil }
            if base > date { return base }
            return calendar.date(byAdding: .hour, value: 1, to: base)
        case .daily(let hour, let minute):
            var comps = calendar.dateComponents([.year, .month, .day], from: date)
            comps.hour = hour
            comps.minute = minute
            comps.second = 0
            guard let base = calendar.date(from: comps) else { return nil }
            if base > date { return base }
            return calendar.date(byAdding: .day, value: 1, to: base)
        case .weekly(let weekday, let hour, let minute):
            var comps = DateComponents()
            comps.weekday = weekday
            comps.hour = hour
            comps.minute = minute
            comps.second = 0
            return calendar.nextDate(after: date, matching: comps, matchingPolicy: .nextTime)
        case .monthly(let day, let hour, let minute):
            var comps = calendar.dateComponents([.year, .month], from: date)
            comps.day = day
            comps.hour = hour
            comps.minute = minute
            comps.second = 0
            guard let base = calendar.date(from: comps) else { return nil }
            if base > date { return base }
            return calendar.date(byAdding: .month, value: 1, to: base)
        case .custom:
            return nil
        }
    }

    private static func timeString(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    static func weekdayName(_ weekday: Int) -> String {
        // Calendar weekday: 1=周日 … 7=周六
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        guard weekday >= 1, weekday <= 7 else { return "" }
        return names[weekday - 1]
    }
}

// MARK: - 本地存储

/// 定时任务的本地仓库。v1 只读写 UserDefaults。
final class NanoMuseScheduledTaskStore: ObservableObject {
    static let shared = NanoMuseScheduledTaskStore()
    static let storageKey = "nanoMuse.scheduledTasks.v1"

    @Published private(set) var tasks: [NanoMuseScheduledTask] = []

    private init() { load() }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([NanoMuseScheduledTask].self, from: data)
        else {
            tasks = []
            return
        }
        tasks = decoded.sorted { $0.createdAt < $1.createdAt }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    func add(_ task: NanoMuseScheduledTask) {
        tasks.append(task)
        tasks.sort { $0.createdAt < $1.createdAt }
        save()
    }

    func update(_ task: NanoMuseScheduledTask) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[i] = task
        save()
    }

    func remove(_ task: NanoMuseScheduledTask) {
        tasks.removeAll { $0.id == task.id }
        save()
    }

    func setEnabled(_ task: NanoMuseScheduledTask, enabled: Bool) {
        var t = task
        t.isEnabled = enabled
        update(t)
    }

    /// 将来接后端/实际调度器时，在任务触发后调用，刷新"上次执行"。
    func recordRun(_ task: NanoMuseScheduledTask, at date: Date = Date()) {
        var t = task
        t.lastRunAt = date
        update(t)
    }
}

// MARK: - 任务列表页

/// 设置页入口建议（勿改 NanoMuseShell.swift）：在 NanoMuseSettings 的 agentCard
/// 第二组里加一行，例如：
///   NanoMuseLinkRow(title: "定时任务") { NanoMuseScheduledTasksView() }
struct NanoMuseScheduledTasksView: View {
    @ObservedObject private var store = NanoMuseScheduledTaskStore.shared
    @State private var editorRequest: TaskEditorRequest?
    @State private var deleteCandidate: NanoMuseScheduledTask?

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        Group {
            if store.tasks.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
        .navigationTitle("定时任务")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    editorRequest = TaskEditorRequest(existing: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新建定时任务")
            }
        }
        .sheet(item: $editorRequest) { req in
            NanoMuseScheduledTaskEditor(existing: req.existing)
        }
        .confirmationDialog(
            "删除这个定时任务？",
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            ),
            titleVisibility: .visible,
            presenting: deleteCandidate
        ) { task in
            Button("删除", role: .destructive) {
                store.remove(task)
            }
            Button("取消", role: .cancel) {}
        } message: { task in
            Text("“\(task.name)”将不再执行，此操作不可撤销。")
        }
    }

    // MARK: 列表

    private var taskList: some View {
        List {
            ForEach(store.tasks) { task in
                taskRow(task)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteCandidate = task
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
            }
            Section {
                Text("任务定义保存在本机。iOS 会在应用长期未使用时挂起后台，届时定时任务可能无法准时触发。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func taskRow(_ task: NanoMuseScheduledTask) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(task.schedule.chineseDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !task.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(task.prompt)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                runInfo(task)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { task.isEnabled },
                set: { store.setEnabled(task, enabled: $0) }
            ))
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            editorRequest = TaskEditorRequest(existing: task)
        }
        .opacity(task.isEnabled ? 1 : 0.55)
    }

    @ViewBuilder
    private func runInfo(_ task: NanoMuseScheduledTask) -> some View {
        HStack(spacing: 10) {
            if task.isEnabled, let next = task.schedule.nextRun() {
                Text("下次 " + Self.relativeFormatter.localizedString(for: next, relativeTo: Date()))
            }
            if let last = task.lastRunAt {
                Text("上次 " + Self.relativeFormatter.localizedString(for: last, relativeTo: Date()))
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    // MARK: 空状态

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "clock.badge")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("还没有定时任务")
                .font(.headline)
            Text("让 agent 按固定周期自动执行，比如每天早上生成一份简报。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                editorRequest = TaskEditorRequest(existing: nil)
            } label: {
                Label("新建任务", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 驱动编辑 sheet 的请求：existing 为 nil 表示新建。
private struct TaskEditorRequest: Identifiable {
    let id = UUID()
    let existing: NanoMuseScheduledTask?
}

// MARK: - 新建 / 编辑任务

/// 编辑器里的周期选项。
private enum TaskFrequency: String, CaseIterable, Identifiable {
    case hourly, daily, weekly, monthly, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hourly: return "每小时"
        case .daily: return "每天"
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .custom: return "自定义 Cron"
        }
    }

    init(schedule: NanoMuseTaskSchedule) {
        switch schedule {
        case .hourly: self = .hourly
        case .daily: self = .daily
        case .weekly: self = .weekly
        case .monthly: self = .monthly
        case .custom: self = .custom
        }
    }
}

struct NanoMuseScheduledTaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = NanoMuseScheduledTaskStore.shared

    private let existing: NanoMuseScheduledTask?

    @State private var name: String
    @State private var prompt: String
    @State private var frequency: TaskFrequency
    @State private var minute: Int
    @State private var time: Date
    @State private var weekday: Int
    @State private var monthDay: Int
    @State private var cronText: String
    @State private var isEnabled: Bool

    init(existing: NanoMuseScheduledTask?) {
        self.existing = existing
        let schedule = existing?.schedule ?? .daily(hour: 9, minute: 0)
        _name = State(initialValue: existing?.name ?? "")
        _prompt = State(initialValue: existing?.prompt ?? "")
        _frequency = State(initialValue: TaskFrequency(schedule: schedule))
        _isEnabled = State(initialValue: existing?.isEnabled ?? true)
        switch schedule {
        case .hourly(let m):
            _minute = State(initialValue: m)
            _time = State(initialValue: Self.dateAt(hour: 9, minute: 0))
            _weekday = State(initialValue: 2)
            _monthDay = State(initialValue: 1)
            _cronText = State(initialValue: "")
        case .daily(let h, let m):
            _minute = State(initialValue: 0)
            _time = State(initialValue: Self.dateAt(hour: h, minute: m))
            _weekday = State(initialValue: 2)
            _monthDay = State(initialValue: 1)
            _cronText = State(initialValue: "")
        case .weekly(let w, let h, let m):
            _minute = State(initialValue: 0)
            _time = State(initialValue: Self.dateAt(hour: h, minute: m))
            _weekday = State(initialValue: w)
            _monthDay = State(initialValue: 1)
            _cronText = State(initialValue: "")
        case .monthly(let d, let h, let m):
            _minute = State(initialValue: 0)
            _time = State(initialValue: Self.dateAt(hour: h, minute: m))
            _weekday = State(initialValue: 2)
            _monthDay = State(initialValue: min(max(d, 1), 28))
            _cronText = State(initialValue: "")
        case .custom(let cron):
            _minute = State(initialValue: 0)
            _time = State(initialValue: Self.dateAt(hour: 9, minute: 0))
            _weekday = State(initialValue: 2)
            _monthDay = State(initialValue: 1)
            _cronText = State(initialValue: cron)
        }
    }

    private static func dateAt(hour: Int, minute: Int) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps) ?? Date()
    }

    /// 自定义 cron 的极简校验：5 个字段。
    private var cronValid: Bool {
        cronText.split(separator: " ").count == 5
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (frequency != .custom || cronValid)
    }

    private var builtSchedule: NanoMuseTaskSchedule {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        let h = comps.hour ?? 9
        let m = comps.minute ?? 0
        switch frequency {
        case .hourly:
            return .hourly(minute: minute)
        case .daily:
            return .daily(hour: h, minute: m)
        case .weekly:
            return .weekly(weekday: weekday, hour: h, minute: m)
        case .monthly:
            return .monthly(day: monthDay, hour: h, minute: m)
        case .custom:
            return .custom(cron: cronText.trimmingCharacters(in: .whitespaces))
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section("基本信息") {
                    TextField("任务名称，如：每天早报", text: $name)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("执行内容")
                            .font(.subheadline)
                        TextEditor(text: $prompt)
                            .frame(minHeight: 90)
                    }
                    Text("触发时 agent 会按这段指令执行。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("执行周期") {
                    Picker("周期", selection: $frequency) {
                        ForEach(TaskFrequency.allCases) { f in
                            Text(f.title).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    switch frequency {
                    case .hourly:
                        Picker("分钟", selection: $minute) {
                            ForEach(0..<60, id: \.self) { m in
                                Text("\(m) 分").tag(m)
                            }
                        }
                    case .daily:
                        DatePicker("时间", selection: $time, displayedComponents: .hourAndMinute)
                    case .weekly:
                        Picker("星期", selection: $weekday) {
                            ForEach(1...7, id: \.self) { w in
                                Text(NanoMuseTaskSchedule.weekdayName(w)).tag(w)
                            }
                        }
                        DatePicker("时间", selection: $time, displayedComponents: .hourAndMinute)
                    case .monthly:
                        Picker("日期", selection: $monthDay) {
                            ForEach(1...28, id: \.self) { d in
                                Text("\(d) 日").tag(d)
                            }
                        }
                        DatePicker("时间", selection: $time, displayedComponents: .hourAndMinute)
                    case .custom:
                        TextField("分 时 日 月 周", text: $cronText)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)  // iOS 15 backport: .autocorrectionDisabled() is iOS 16+
                        Text("例如 30 9 * * 1 表示每周一 9:30。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if !cronText.isEmpty && !cronValid {
                            Text("格式不正确：需要 5 个字段。")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }

                    if frequency != .custom {
                        HStack {
                            Text("Cron")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(builtSchedule.cronExpression)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Toggle("启用", isOn: $isEnabled)
                }
            }
            .navigationTitle(existing == nil ? "新建任务" : "编辑任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if var t = existing {
            t.name = trimmedName
            t.prompt = prompt
            t.schedule = builtSchedule
            t.isEnabled = isEnabled
            store.update(t)
        } else {
            store.add(NanoMuseScheduledTask(
                name: trimmedName,
                prompt: prompt,
                schedule: builtSchedule,
                isEnabled: isEnabled
            ))
        }
        dismiss()
    }
}
