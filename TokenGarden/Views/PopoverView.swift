import SwiftUI
import SwiftData

struct PopoverView: View {
    @EnvironmentObject var menuBarController: MenuBarController
    @EnvironmentObject var dataStore: TokenDataStore
    @Environment(OverviewViewModel.self) private var vm

    enum Tab { case overview, accounts }
    @State private var activeTab: Tab = .overview
    @State private var showSettings = false
    @State private var showProfiles = false

    @State private var cachedPathState: PathState = .unknown

    private enum PathState {
        case unknown
        case missing
        case unreadable
        case ok
    }

    private var emptyStateReason: EmptyStateReason? {
        switch cachedPathState {
        case .missing: return .noClaudeCode
        case .unreadable: return .noPermission
        case .ok, .unknown:
            // While the initial load is in flight we show a skeleton instead
            // of an "empty" message.
            if vm.isInitialLoading { return nil }
            return vm.snapshot.hasAnyData ? nil : .noData
        }
    }

    private func refreshPathState() {
        let logPath = UserDefaults.standard.string(forKey: "logPath") ?? "~/.claude/"
        let expandedPath = NSString(string: logPath).expandingTildeInPath
        if !FileManager.default.fileExists(atPath: expandedPath) {
            cachedPathState = .missing
        } else if !FileManager.default.isReadableFile(atPath: expandedPath) {
            cachedPathState = .unreadable
        } else {
            cachedPathState = .ok
        }
    }

    private var selectedDayLabel: String? {
        guard let date = vm.selectedDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "M/d (E)"
        return formatter.string(from: date)
    }

    var body: some View {
        @Bindable var vm = vm

        VStack(spacing: 0) {
            HStack {
                if showSettings || showProfiles {
                    Button(action: {
                        showSettings = false
                        showProfiles = false
                    }) {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    Text(showProfiles ? "Profiles" : "Settings")
                        .font(.headline)
                } else {
                    Text("Token Garden")
                        .font(.headline)
                }
                Spacer()
                if !showSettings && !showProfiles {
                    HStack(spacing: 12) {
                        Button(action: { activeTab = .overview }) {
                            Image(systemName: "chart.bar")
                                .foregroundStyle(activeTab == .overview ? .primary : .tertiary)
                        }
                        .buttonStyle(.plain)
                        Button(action: { activeTab = .accounts }) {
                            Image(systemName: "person.2")
                                .foregroundStyle(activeTab == .accounts ? .primary : .tertiary)
                        }
                        .buttonStyle(.plain)
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if !showSettings && !showProfiles && activeTab == .accounts {
                ProfileBannerView(onTap: { showProfiles = true })
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            if let reason = emptyStateReason {
                EmptyStateView(reason: reason)
                    .frame(minHeight: 200)
            } else if showSettings {
                SettingsView()
                    .transition(.identity)
            } else if showProfiles {
                ProfileListView()
            } else if activeTab == .accounts {
                ScrollView {
                    AccountsTabView()
                }
                .scrollIndicators(.never)
                .frame(height: tabContentHeight)
                .transition(.identity)
            } else {
                overviewContent(vm: $vm)
            }
        }
        .frame(width: 320)
        .animation(nil, value: showSettings)
        .animation(nil, value: showProfiles)
        .animation(nil, value: activeTab)
        .onAppear {
            refreshPathState()
        }
    }

    /// Fixed inner height for the Overview tab. The popover itself stays
    /// this size regardless of expanded/collapsed section state; overflow
    /// scrolls inside the ScrollView.
    private let tabContentHeight: CGFloat = 520

    @ViewBuilder
    private func overviewContent(vm: Bindable<OverviewViewModel>) -> some View {
        Group {
            if vm.wrappedValue.isInitialLoading {
                OverviewSkeleton()
                    .frame(maxWidth: .infinity, alignment: .top)
                    .transition(.opacity)
            } else {
                let snapshot = vm.wrappedValue.snapshot
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HeatmapView(
                            dailyUsages: snapshot.heatmapData.map { (date: $0.date, tokens: $0.tokens) },
                            selectedDate: vm.selectedDate
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                        if let date = vm.wrappedValue.selectedDate,
                           let cell = snapshot.heatmapData.first(where: {
                               Calendar.current.isDate($0.date, inSameDayAs: date)
                           }) {
                            HStack {
                                Text(selectedDayLabel ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(TokenFormatter.format(cell.tokens))
                                    .font(.caption.monospacedDigit())
                                    .fontWeight(.medium)
                            }
                            .padding(8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal, 12)
                        } else {
                            StatsView(
                                todayTokens: snapshot.todayTokens,
                                weekTokens: snapshot.weekTokens,
                                monthTokens: snapshot.monthTokens
                            )
                            .padding(.horizontal, 12)
                        }

                        HourlyChartView(
                            hourlyTokens: vm.wrappedValue.activeHourlyTokens,
                            isToday: vm.wrappedValue.selectedDate == nil
                                || Calendar.current.isDateInToday(vm.wrappedValue.selectedDate!)
                        )
                        .padding(.horizontal, 12)

                        ProjectListView(
                            todayProjects: snapshot.todayProjects.map { (name: $0.name, tokens: $0.tokens) },
                            weekProjects: snapshot.weekProjects.map { (name: $0.name, tokens: $0.tokens) },
                            monthProjects: snapshot.monthProjects.map { (name: $0.name, tokens: $0.tokens) },
                            selectedDayProjects: vm.wrappedValue.selectedDayProjects?.map {
                                (name: $0.name, tokens: $0.tokens)
                            },
                            selectedDayLabel: selectedDayLabel
                        )
                        .padding(.horizontal, 12)

                        SessionListView(sessions: snapshot.activeSessions)
                            .padding(.horizontal, 12)
                    }
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.never)
                .transition(.opacity)
            }
        }
        .frame(height: tabContentHeight)
    }
}
