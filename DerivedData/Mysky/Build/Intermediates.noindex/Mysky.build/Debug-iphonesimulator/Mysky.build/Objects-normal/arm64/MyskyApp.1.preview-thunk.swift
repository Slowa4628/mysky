import func SwiftUI.__designTimeFloat
import func SwiftUI.__designTimeString
import func SwiftUI.__designTimeInteger
import func SwiftUI.__designTimeBoolean

#sourceLocation(file: "/Users/a1/Desktop/prodjekt/Mysky/Mysky/MyskyApp.swift", line: 1)
//
//  MoonPhaseAll.swift
//  MoonPhase (single-file)
//
//  Created for user request: modular single-file SwiftUI app with RU/EN toggle.
//  - Simple (fast) moon phase engine (synodic month approximation).
//  - Calendar view, settings with language toggle, coordinate input, location request.
//  - Easy to swap engine implementation later.
//
//  Usage: Create new SwiftUI App project in Xcode, remove default files, add this file, Run.
//  Note: With free Apple ID provisioning app will need re-sign every 7 days.
//

import SwiftUI
import Combine
import CoreLocation

// MARK: - Models

public struct MoonPhaseResult: Equatable {
    public let date: Date
    public let age: Double         // days since new moon
    public let phase: Double       // 0..1 (0 new, 0.5 full)
    public let illumination: Double// 0..1
    public let distanceKm: Double? // optional placeholder
    public let phaseName: String?  // human readable name (localized externally)
}

// MARK: - Engine Protocol

public protocol MoonEngineProtocol {
    /// Calculate moon data for a given date and optional coordinate.
    func calculate(for date: Date, coordinate: CLLocationCoordinate2D?) -> MoonPhaseResult
}

// MARK: - Default (fast) Moon Engine (approximation)
// Synodic-month-based approximation. Fast and stable for UI (chosen option 1).

public final class DefaultMoonEngine: MoonEngineProtocol {
    private let synodicMonth = 29.53058867 // mean length

    public init() {}

    public func calculate(for date: Date, coordinate: CLLocationCoordinate2D?) -> MoonPhaseResult {
        let jd = julianDate(from: date)
        // Use epoch reference 2451549.5 (2000 Jan 1.5)
        var daysSince = jd - __designTimeFloat("#8570_0", fallback: 2451549.5)
        // Normalize to [0, synodicMonth)
        var age = daysSince.truncatingRemainder(dividingBy: synodicMonth)
        if age < __designTimeInteger("#8570_1", fallback: 0) { age += synodicMonth }
        let phase = age / synodicMonth // 0..1
        let phaseAngle = __designTimeFloat("#8570_2", fallback: 2.0) * Double.pi * phase
        let illumination = (__designTimeFloat("#8570_3", fallback: 1.0) - cos(phaseAngle)) / __designTimeFloat("#8570_4", fallback: 2.0)

        // distance placeholder
        let distanceKm: Double? = 384_400.0

        // phaseName will be selected in UI using localized naming logic
        return MoonPhaseResult(date: date, age: age, phase: phase, illumination: illumination, distanceKm: distanceKm, phaseName: nil)
    }

    // Minimal Julian Date (UTC)
    private func julianDate(from date: Date) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(abbreviation: __designTimeString("#8570_5", fallback: "UTC"))!
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        var Y = comps.year!
        var M = comps.month!
        let dayFraction = Double(comps.day!) + (Double(comps.hour ?? __designTimeInteger("#8570_6", fallback: 0)) / __designTimeFloat("#8570_7", fallback: 24.0)) + (Double(comps.minute ?? __designTimeInteger("#8570_8", fallback: 0)) / __designTimeFloat("#8570_9", fallback: 1440.0)) + (Double(comps.second ?? __designTimeInteger("#8570_10", fallback: 0)) / __designTimeFloat("#8570_11", fallback: 86400.0))
        if M <= __designTimeInteger("#8570_12", fallback: 2) { Y -= __designTimeInteger("#8570_13", fallback: 1); M += __designTimeInteger("#8570_14", fallback: 12) }
        let A = floor(Double(Y) / __designTimeFloat("#8570_15", fallback: 100.0))
        let B = __designTimeInteger("#8570_16", fallback: 2) - A + floor(A / __designTimeFloat("#8570_17", fallback: 4.0))
        let jd = floor(__designTimeFloat("#8570_18", fallback: 365.25) * Double(Y + __designTimeInteger("#8570_19", fallback: 4716))) + floor(__designTimeFloat("#8570_20", fallback: 30.6001) * Double(M + __designTimeInteger("#8570_21", fallback: 1))) + dayFraction + B - __designTimeFloat("#8570_22", fallback: 1524.5)
        return jd
    }
}

// MARK: - Repository

public final class MoonRepository {
    private let engine: MoonEngineProtocol
    public init(engine: MoonEngineProtocol = DefaultMoonEngine()) {
        self.engine = engine
    }

    public func moonData(for date: Date, coordinate: CLLocationCoordinate2D?) -> MoonPhaseResult {
        return engine.calculate(for: date, coordinate: coordinate)
    }
}

// MARK: - Store (ViewModel)

// App language enum
enum AppLanguage: String, CaseIterable {
    case ru = "ru"
    case en = "en"
}

final class MoonStore: ObservableObject {
    static let shared = MoonStore()

    // persisted UI language
    @AppStorage("appLanguage") var appLanguageRaw: String = Locale.current.languageCode ?? "en"

    // published
    @Published var selectedDate: Date = Date() { didSet { recalc() } }
    @Published var coordinate: CLLocationCoordinate2D? = nil { didSet { recalc() } }
    @Published private(set) var result: MoonPhaseResult
    @Published var repository: MoonRepository

    // expose language
    var language: AppLanguage {
        get { AppLanguage(rawValue: appLanguageRaw) ?? .en }
        set { appLanguageRaw = newValue.rawValue; objectWillChange.send() }
    }

    private init(repository: MoonRepository = MoonRepository()) {
        self.repository = repository
        // initial compute
        self.result = repository.moonData(for: Date(), coordinate: nil)
    }

    private func recalc() {
        result = repository.moonData(for: selectedDate, coordinate: coordinate)
        publishToWidgetIfNeeded(result) // placeholder: writes to shared defaults for future widget
    }

    public func moonData(for date: Date) -> MoonPhaseResult {
        return repository.moonData(for: date, coordinate: coordinate)
    }

    // Save data for potential widget (App Group must be setup later)
    private func publishToWidgetIfNeeded(_ result: MoonPhaseResult) {
        // intentionally light: writes to standard UserDefaults for debugging
        let ud = UserDefaults.standard
        ud.set(result.illumination, forKey: __designTimeString("#8570_23", fallback: "MoonPhase_illum"))
        ud.set(result.phase, forKey: __designTimeString("#8570_24", fallback: "MoonPhase_phase"))
        ud.set(result.age, forKey: __designTimeString("#8570_25", fallback: "MoonPhase_age"))
    }
}

// MARK: - Location Manager (simple wrapper)

final class LocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    private let manager = CLLocationManager()
    private var completion: ((CLLocationCoordinate2D?) -> Void)?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation(completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        self.completion = completion
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        completion?(locations.first?.coordinate)
        completion = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        completion?(nil)
        completion = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // no-op
    }
}

// MARK: - Localization helper (in-app, simple)

struct L10n {
    static func t(_ key: String, lang: AppLanguage) -> String {
        // keys used below; add new keys as needed
        switch key {
        case "app_title": return lang == .ru ? __designTimeString("#8570_26", fallback: "Луна") : __designTimeString("#8570_27", fallback: "Moon")
        case "day": return lang == .ru ? __designTimeString("#8570_28", fallback: "День") : __designTimeString("#8570_29", fallback: "Day")
        case "illum": return lang == .ru ? __designTimeString("#8570_30", fallback: "Освещ.") : __designTimeString("#8570_31", fallback: "Illum.")
        case "calendar": return lang == .ru ? __designTimeString("#8570_32", fallback: "Календарь") : __designTimeString("#8570_33", fallback: "Calendar")
        case "settings": return lang == .ru ? __designTimeString("#8570_34", fallback: "Настройки") : __designTimeString("#8570_35", fallback: "Settings")
        case "date": return lang == .ru ? __designTimeString("#8570_36", fallback: "Дата") : __designTimeString("#8570_37", fallback: "Date")
        case "latitude": return lang == .ru ? __designTimeString("#8570_38", fallback: "Широта") : __designTimeString("#8570_39", fallback: "Latitude")
        case "longitude": return lang == .ru ? __designTimeString("#8570_40", fallback: "Долгота") : __designTimeString("#8570_41", fallback: "Longitude")
        case "save": return lang == .ru ? __designTimeString("#8570_42", fallback: "Сохранить") : __designTimeString("#8570_43", fallback: "Save")
        case "use_device_location": return lang == .ru ? __designTimeString("#8570_44", fallback: "Использовать текущее местоположение") : __designTimeString("#8570_45", fallback: "Use device location")
        case "done": return lang == .ru ? __designTimeString("#8570_46", fallback: "Готово") : __designTimeString("#8570_47", fallback: "Done")
        case "language": return lang == .ru ? __designTimeString("#8570_48", fallback: "Язык") : __designTimeString("#8570_49", fallback: "Language")
        case "language_ru": return lang == .ru ? __designTimeString("#8570_50", fallback: "Русский") : __designTimeString("#8570_51", fallback: "Russian")
        case "language_en": return lang == .ru ? __designTimeString("#8570_52", fallback: "Английский") : __designTimeString("#8570_53", fallback: "English")
        case "reset_coords": return lang == .ru ? __designTimeString("#8570_54", fallback: "Сбросить координаты") : __designTimeString("#8570_55", fallback: "Reset coords")
        case "today": return lang == .ru ? __designTimeString("#8570_56", fallback: "Сегодня") : __designTimeString("#8570_57", fallback: "Today")
        case "open_calendar": return lang == .ru ? __designTimeString("#8570_58", fallback: "Открыть календарь") : __designTimeString("#8570_59", fallback: "Open calendar")
        case "no_location": return lang == .ru ? __designTimeString("#8570_60", fallback: "Местоположение не найдено") : __designTimeString("#8570_61", fallback: "Location not found")
        default:
            return key
        }
    }

    // Phase names (approx) by phase fraction
    static func phaseName(for phase: Double, lang: AppLanguage) -> String {
        // phase: 0..1 (0 new -> 0.25 first quarter -> 0.5 full -> 0.75 last quarter -> 1 new)
        let p = phase
        let name: String
        if p < __designTimeFloat("#8570_62", fallback: 0.03) || p > __designTimeFloat("#8570_63", fallback: 0.97) {
            name = (lang == .ru) ? __designTimeString("#8570_64", fallback: "Новолуние") : __designTimeString("#8570_65", fallback: "New Moon")
        } else if p < __designTimeFloat("#8570_66", fallback: 0.22) {
            name = (lang == .ru) ? __designTimeString("#8570_67", fallback: "Растущая луна") : __designTimeString("#8570_68", fallback: "Waxing Crescent")
        } else if p < __designTimeFloat("#8570_69", fallback: 0.28) {
            name = (lang == .ru) ? __designTimeString("#8570_70", fallback: "Первая четверть") : __designTimeString("#8570_71", fallback: "First Quarter")
        } else if p < __designTimeFloat("#8570_72", fallback: 0.47) {
            name = (lang == .ru) ? __designTimeString("#8570_73", fallback: "Растущая луна") : __designTimeString("#8570_74", fallback: "Waxing Gibbous")
        } else if p < __designTimeFloat("#8570_75", fallback: 0.53) {
            name = (lang == .ru) ? __designTimeString("#8570_76", fallback: "Полнолуние") : __designTimeString("#8570_77", fallback: "Full Moon")
        } else if p < __designTimeFloat("#8570_78", fallback: 0.72) {
            name = (lang == .ru) ? __designTimeString("#8570_79", fallback: "Убывающая луна") : __designTimeString("#8570_80", fallback: "Waning Gibbous")
        } else if p < __designTimeFloat("#8570_81", fallback: 0.78) {
            name = (lang == .ru) ? __designTimeString("#8570_82", fallback: "Последняя четверть") : __designTimeString("#8570_83", fallback: "Last Quarter")
        } else {
            name = (lang == .ru) ? __designTimeString("#8570_84", fallback: "Убывающий серп") : __designTimeString("#8570_85", fallback: "Waning Crescent")
        }
        return name
    }
}

// MARK: - Views (SwiftUI)

// Main App
@main
struct MoonPhaseApp: App {
    @StateObject private var store = MoonStore.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}

// ContentView: main screen
struct ContentView: View {
    @EnvironmentObject var store: MoonStore
    @State private var showCalendar = false
    @State private var showSettings = false

    var body: some View {
        NavigationView {
            VStack(spacing: __designTimeInteger("#8570_86", fallback: 16)) {
                HStack {
                    Text(L10n.t(__designTimeString("#8570_87", fallback: "app_title"), lang: store.language))
                        .font(.largeTitle).bold()
                    Spacer()
                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: __designTimeString("#8570_88", fallback: "gearshape"))
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)

                // Moon graphic
                MoonGraphicView(phase: store.result.phase)
                    .frame(maxWidth: __designTimeInteger("#8570_89", fallback: 320), maxHeight: __designTimeInteger("#8570_90", fallback: 320))
                    .padding(.vertical, __designTimeInteger("#8570_91", fallback: 6))

                // Stats
                HStack(spacing: __designTimeInteger("#8570_92", fallback: 24)) {
                    statBlock(value: String(format: __designTimeString("#8570_93", fallback: "%.1f"), store.result.age), label: L10n.t(__designTimeString("#8570_94", fallback: "day"), lang: store.language))
                    statBlock(value: String(format: __designTimeString("#8570_95", fallback: "%.0f%%"), store.result.illumination * __designTimeFloat("#8570_96", fallback: 100.0)), label: L10n.t(__designTimeString("#8570_97", fallback: "illum"), lang: store.language))
                }

                // Date picker
                VStack(spacing: __designTimeInteger("#8570_98", fallback: 8)) {
                    HStack {
                        Text(L10n.t(__designTimeString("#8570_99", fallback: "date"), lang: store.language))
                            .font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                        Button(L10n.t(__designTimeString("#8570_100", fallback: "today"), lang: store.language)) {
                            store.selectedDate = Date()
                        }
                        .font(.subheadline)
                    }
                    DatePicker(__designTimeString("#8570_101", fallback: ""), selection: $store.selectedDate, displayedComponents: [.date])
                        .datePickerStyle(.compact)
                        .labelsHidden()
                }
                .padding(.horizontal)

                // Open calendar
                Button(action: { showCalendar.toggle() }) {
                    HStack {
                        Image(systemName: __designTimeString("#8570_102", fallback: "calendar"))
                        Text(L10n.t(__designTimeString("#8570_103", fallback: "open_calendar"), lang: store.language))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
            .sheet(isPresented: $showCalendar) {
                MonthCalendarView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(store)
            }
            .navigationBarHidden(__designTimeBoolean("#8570_104", fallback: true))
        }
    }

    @ViewBuilder
    private func statBlock(value: String, label: String) -> some View {
        VStack {
            Text(value).font(.title2).bold()
            Text(label).font(.caption).foregroundColor(.secondary)
        }
        .frame(minWidth: __designTimeInteger("#8570_105", fallback: 100))
    }
}

// Moon graphic (simple terminator mask)
struct MoonGraphicView: View {
    var phase: Double // 0..1

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                Circle()
                    .fill(Color(.systemGray6))
                    .frame(width: size, height: size)
                    .shadow(radius: __designTimeInteger("#8570_106", fallback: 6))
                TerminatorView(phase: phase)
                    .frame(width: size, height: size)
                    .blendMode(.destinationOut)
                    .compositingGroup()
                Circle()
                    .stroke(Color(.systemGray3), lineWidth: __designTimeFloat("#8570_107", fallback: 0.5))
                    .frame(width: size, height: size)
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(__designTimeInteger("#8570_108", fallback: 1), contentMode: .fit)
        .padding()
    }
}

struct TerminatorView: View {
    var phase: Double

    var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width, geo.size.height)
            // offset maps phase (0..1) to ellipse offset
            let offset = CGFloat((phase - __designTimeFloat("#8570_109", fallback: 0.5)) * __designTimeFloat("#8570_110", fallback: 1.6)) * w
            Ellipse()
                .frame(width: w * __designTimeFloat("#8570_111", fallback: 1.6), height: w)
                .offset(x: offset)
                .foregroundColor(.black)
        }
    }
}

// Calendar month view (sheet)
struct MonthCalendarView: View {
    @EnvironmentObject var store: MoonStore
    @Environment(\.presentationMode) var presentation

    @State private var currentMonthDate: Date = Date()

    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    Button(action: { changeMonth(by: __designTimeInteger("#8570_112", fallback: -1)) }) { Image(systemName: __designTimeString("#8570_113", fallback: "chevron.left")) }
                    Spacer()
                    Text(monthTitle(for: currentMonthDate))
                        .font(.headline)
                    Spacer()
                    Button(action: { changeMonth(by: __designTimeInteger("#8570_114", fallback: 1)) }) { Image(systemName: __designTimeString("#8570_115", fallback: "chevron.right")) }
                }
                .padding(.horizontal)

                CalendarGridView(centerDate: currentMonthDate)
                    .environmentObject(store)

                Spacer()
            }
            .navigationTitle(L10n.t(__designTimeString("#8570_116", fallback: "calendar"), lang: store.language))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t(__designTimeString("#8570_117", fallback: "done"), lang: store.language)) {
                        presentation.wrappedValue.dismiss()
                    }
                }
            }
        }
    }

    private func changeMonth(by delta: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: delta, to: currentMonthDate) {
            currentMonthDate = next
        }
    }

    private func monthTitle(for date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: store.language == .ru ? __designTimeString("#8570_118", fallback: "ru_RU") : __designTimeString("#8570_119", fallback: "en_US"))
        df.dateFormat = __designTimeString("#8570_120", fallback: "LLLL yyyy")
        return df.string(from: date).capitalized
    }
}

struct CalendarGridView: View {
    @EnvironmentObject var store: MoonStore
    var centerDate: Date

    init(centerDate: Date) {
        self.centerDate = centerDate
    }

    var body: some View {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: centerDate)
        guard let startOfMonth = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: centerDate) else {
            return AnyView(Text(__designTimeString("#8570_121", fallback: "Ошибка календаря")))
        }
        let firstWeekday = cal.component(.weekday, from: startOfMonth) // 1 = Sunday
        let pad = (firstWeekday + __designTimeInteger("#8570_122", fallback: 6)) % __designTimeInteger("#8570_123", fallback: 7) // convert to Monday start
        let days = Array(range)
        let padded = Array(repeating: __designTimeInteger("#8570_124", fallback: 0), count: pad) + days

        return AnyView(
            VStack {
                HStack {
                    ForEach([__designTimeString("#8570_125", fallback: "Пн"),__designTimeString("#8570_126", fallback: "Вт"),__designTimeString("#8570_127", fallback: "Ср"),__designTimeString("#8570_128", fallback: "Чт"),__designTimeString("#8570_129", fallback: "Пт"),__designTimeString("#8570_130", fallback: "Сб"),__designTimeString("#8570_131", fallback: "Вс")], id: \.self) { d in
                        Text(d).font(.caption).frame(maxWidth: .infinity)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: __designTimeInteger("#8570_132", fallback: 7)), spacing: __designTimeInteger("#8570_133", fallback: 8)) {
                    ForEach(padded.indices, id: \.self) { idx in
                        if padded[idx] == __designTimeInteger("#8570_134", fallback: 0) {
                            Color.clear.frame(height: __designTimeInteger("#8570_135", fallback: 72))
                        } else {
                            let day = padded[idx]
                            let date = cal.date(byAdding: .day, value: day - __designTimeInteger("#8570_136", fallback: 1), to: startOfMonth)!
                            CalendarDayCell(date: date)
                                .environmentObject(store)
                                .onTapGesture {
                                    store.selectedDate = date
                                }
                        }
                    }
                }
                .padding(.horizontal)
            }
        )
    }
}

struct CalendarDayCell: View {
    @EnvironmentObject var store: MoonStore
    var date: Date

    var body: some View {
        let res = store.moonData(for: date)
        VStack(spacing: __designTimeInteger("#8570_137", fallback: 6)) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.caption)
            MoonGraphicView(phase: res.phase)
                .frame(height: __designTimeInteger("#8570_138", fallback: 44))
            Text(String(format: __designTimeString("#8570_139", fallback: "%.0f%%"), res.illumination * __designTimeFloat("#8570_140", fallback: 100.0)))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(__designTimeInteger("#8570_141", fallback: 6))
        .background(RoundedRectangle(cornerRadius: __designTimeInteger("#8570_142", fallback: 8)).fill(Color(UIColor.secondarySystemBackground)))
    }
}

// Settings view
struct SettingsView: View {
    @EnvironmentObject var store: MoonStore
    @Environment(\.presentationMode) var presentation

    @State private var latText: String = ""
    @State private var lonText: String = ""
    @State private var useDeviceLocation: Bool = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker(selection: Binding(get: { store.language }, set: { store.language = $0 }), label: Text(L10n.t(__designTimeString("#8570_143", fallback: "language"), lang: store.language))) {
                        Text(L10n.t(__designTimeString("#8570_144", fallback: "language_ru"), lang: store.language)).tag(AppLanguage.ru)
                        Text(L10n.t(__designTimeString("#8570_145", fallback: "language_en"), lang: store.language)).tag(AppLanguage.en)
                    }
                }

                Section(header: Text(L10n.t(__designTimeString("#8570_146", fallback: "latitude"), lang: store.language) + __designTimeString("#8570_147", fallback: " / ") + L10n.t(__designTimeString("#8570_148", fallback: "longitude"), lang: store.language))) {
                    Toggle(L10n.t(__designTimeString("#8570_149", fallback: "use_device_location"), lang: store.language), isOn: $useDeviceLocation)
                        .onChange(of: useDeviceLocation) { newValue in
                            if newValue { requestLocation() } else { store.coordinate = nil }
                        }
                    TextField(L10n.t(__designTimeString("#8570_150", fallback: "latitude"), lang: store.language), text: $latText)
                        .keyboardType(.decimalPad)
                    TextField(L10n.t(__designTimeString("#8570_151", fallback: "longitude"), lang: store.language), text: $lonText)
                        .keyboardType(.decimalPad)
                    Button(L10n.t(__designTimeString("#8570_152", fallback: "save"), lang: store.language)) {
                        if let la = Double(latText), let lo = Double(lonText) {
                            store.coordinate = CLLocationCoordinate2D(latitude: la, longitude: lo)
                        }
                    }
                    Button(L10n.t(__designTimeString("#8570_153", fallback: "reset_coords"), lang: store.language)) {
                        store.coordinate = nil
                        latText = __designTimeString("#8570_154", fallback: "")
                        lonText = __designTimeString("#8570_155", fallback: "")
                        useDeviceLocation = __designTimeBoolean("#8570_156", fallback: false)
                    }
                }

                Section {
                    Button(L10n.t(__designTimeString("#8570_157", fallback: "done"), lang: store.language)) {
                        presentation.wrappedValue.dismiss()
                    }
                }
            }
            .navigationTitle(L10n.t(__designTimeString("#8570_158", fallback: "settings"), lang: store.language))
            .onAppear {
                if let c = store.coordinate {
                    latText = String(format: __designTimeString("#8570_159", fallback: "%.6f"), c.latitude)
                    lonText = String(format: __designTimeString("#8570_160", fallback: "%.6f"), c.longitude)
                } else {
                    latText = __designTimeString("#8570_161", fallback: "")
                    lonText = __designTimeString("#8570_162", fallback: "")
                }
            }
        }
    }

    private func requestLocation() {
        LocationManager.shared.requestLocation { coord in
            DispatchQueue.main.async {
                if let coord = coord {
                    store.coordinate = coord
                    latText = String(format: __designTimeString("#8570_163", fallback: "%.6f"), coord.latitude)
                    lonText = String(format: __designTimeString("#8570_164", fallback: "%.6f"), coord.longitude)
                } else {
                    // nothing found
                    // could show alert; keeping minimal
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct MoonPhaseAll_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environmentObject(MoonStore.shared)
    }
}
#endif

// End of file
