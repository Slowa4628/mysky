import func SwiftUI.__designTimeSelection

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
        let jd = julianDate(from: __designTimeSelection(date, "#8570.[5].[2].[0].value.arg[0].value"))
        // Use epoch reference 2451549.5 (2000 Jan 1.5)
        var daysSince = jd - __designTimeFloat("#8570_0", fallback: 2451549.5)
        // Normalize to [0, synodicMonth)
        var age = daysSince.truncatingRemainder(dividingBy: __designTimeSelection(synodicMonth, "#8570.[5].[2].[2].value.modifier[0].arg[0].value"))
        if age < __designTimeInteger("#8570_1", fallback: 0) { age += synodicMonth }
        let phase = age / synodicMonth // 0..1
        let phaseAngle = __designTimeFloat("#8570_2", fallback: 2.0) * Double.pi * phase
        let illumination = (__designTimeFloat("#8570_3", fallback: 1.0) - cos(__designTimeSelection(phaseAngle, "#8570.[5].[2].[6].value.[1]"))) / __designTimeFloat("#8570_4", fallback: 2.0)

        // distance placeholder
        let distanceKm: Double? = 384_400.0

        // phaseName will be selected in UI using localized naming logic
        return __designTimeSelection(MoonPhaseResult(date: __designTimeSelection(date, "#8570.[5].[2].[8].arg[0].value"), age: __designTimeSelection(age, "#8570.[5].[2].[8].arg[1].value"), phase: __designTimeSelection(phase, "#8570.[5].[2].[8].arg[2].value"), illumination: __designTimeSelection(illumination, "#8570.[5].[2].[8].arg[3].value"), distanceKm: __designTimeSelection(distanceKm, "#8570.[5].[2].[8].arg[4].value"), phaseName: nil), "#8570.[5].[2].[8]")
    }

    // Minimal Julian Date (UTC)
    private func julianDate(from date: Date) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(abbreviation: __designTimeString("#8570_5", fallback: "UTC"))!
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: __designTimeSelection(date, "#8570.[5].[3].[2].value.modifier[0].arg[1].value"))
        var Y = comps.year!
        var M = comps.month!
        let dayFraction = Double(comps.day!) + (Double(comps.hour ?? __designTimeInteger("#8570_6", fallback: 0)) / __designTimeFloat("#8570_7", fallback: 24.0)) + (Double(comps.minute ?? __designTimeInteger("#8570_8", fallback: 0)) / __designTimeFloat("#8570_9", fallback: 1440.0)) + (Double(comps.second ?? __designTimeInteger("#8570_10", fallback: 0)) / __designTimeFloat("#8570_11", fallback: 86400.0))
        if M <= __designTimeInteger("#8570_12", fallback: 2) { Y -= __designTimeInteger("#8570_13", fallback: 1); M += __designTimeInteger("#8570_14", fallback: 12) }
        let A = floor(Double(__designTimeSelection(Y, "#8570.[5].[3].[7].value.arg[0].value.[0]")) / __designTimeFloat("#8570_15", fallback: 100.0))
        let B = __designTimeInteger("#8570_16", fallback: 2) - A + floor(A / __designTimeFloat("#8570_17", fallback: 4.0))
        let jd = floor(__designTimeFloat("#8570_18", fallback: 365.25) * Double(Y + __designTimeInteger("#8570_19", fallback: 4716))) + floor(__designTimeFloat("#8570_20", fallback: 30.6001) * Double(M + __designTimeInteger("#8570_21", fallback: 1))) + dayFraction + B - __designTimeFloat("#8570_22", fallback: 1524.5)
        return __designTimeSelection(jd, "#8570.[5].[3].[10]")
    }
}

// MARK: - Repository

public final class MoonRepository {
    private let engine: MoonEngineProtocol
    public init(engine: MoonEngineProtocol = DefaultMoonEngine()) {
        self.engine = engine
    }

    public func moonData(for date: Date, coordinate: CLLocationCoordinate2D?) -> MoonPhaseResult {
        return __designTimeSelection(engine.calculate(for: __designTimeSelection(date, "#8570.[6].[2].[0].modifier[0].arg[0].value"), coordinate: __designTimeSelection(coordinate, "#8570.[6].[2].[0].modifier[0].arg[1].value")), "#8570.[6].[2].[0]")
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
    @Published var selectedDate: Date = Date() { didSet { __designTimeSelection(recalc(), "#8570.[8].[2].property.[0].[0]") } }
    @Published var coordinate: CLLocationCoordinate2D? = nil { didSet { __designTimeSelection(recalc(), "#8570.[8].[3].property.[0].[0]") } }
    @Published private(set) var result: MoonPhaseResult
    @Published var repository: MoonRepository

    // expose language
    var language: AppLanguage {
        get { AppLanguage(rawValue: __designTimeSelection(appLanguageRaw, "#8570.[8].[6].property.[0].[0].[0]")) ?? .en }
        set { appLanguageRaw = newValue.rawValue; __designTimeSelection(objectWillChange.send(), "#8570.[8].[6].property.[1].[1]") }
    }

    private init(repository: MoonRepository = MoonRepository()) {
        self.repository = repository
        // initial compute
        self.result = repository.moonData(for: __designTimeSelection(Date(), "#8570.[8].[7].[1].[0]"), coordinate: nil)
    }

    private func recalc() {
        result = repository.moonData(for: __designTimeSelection(selectedDate, "#8570.[8].[8].[0].[0]"), coordinate: __designTimeSelection(coordinate, "#8570.[8].[8].[0].[0]"))
        __designTimeSelection(publishToWidgetIfNeeded(__designTimeSelection(result, "#8570.[8].[8].[1].arg[0].value")), "#8570.[8].[8].[1]") // placeholder: writes to shared defaults for future widget
    }

    public func moonData(for date: Date) -> MoonPhaseResult {
        return __designTimeSelection(repository.moonData(for: __designTimeSelection(date, "#8570.[8].[9].[0].modifier[0].arg[0].value"), coordinate: __designTimeSelection(coordinate, "#8570.[8].[9].[0].modifier[0].arg[1].value")), "#8570.[8].[9].[0]")
    }

    // Save data for potential widget (App Group must be setup later)
    private func publishToWidgetIfNeeded(_ result: MoonPhaseResult) {
        // intentionally light: writes to standard UserDefaults for debugging
        let ud = UserDefaults.standard
        __designTimeSelection(ud.set(__designTimeSelection(result.illumination, "#8570.[8].[10].[1].modifier[0].arg[0].value"), forKey: __designTimeString("#8570_23", fallback: "MoonPhase_illum")), "#8570.[8].[10].[1]")
        __designTimeSelection(ud.set(__designTimeSelection(result.phase, "#8570.[8].[10].[2].modifier[0].arg[0].value"), forKey: __designTimeString("#8570_24", fallback: "MoonPhase_phase")), "#8570.[8].[10].[2]")
        __designTimeSelection(ud.set(__designTimeSelection(result.age, "#8570.[8].[10].[3].modifier[0].arg[0].value"), forKey: __designTimeString("#8570_25", fallback: "MoonPhase_age")), "#8570.[8].[10].[3]")
    }
}

// MARK: - Location Manager (simple wrapper)

final class LocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    private let manager = CLLocationManager()
    private var completion: ((CLLocationCoordinate2D?) -> Void)?

    private override init() {
        __designTimeSelection(super.init(), "#8570.[9].[3].[0]")
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation(completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        self.completion = completion
        __designTimeSelection(manager.requestWhenInUseAuthorization(), "#8570.[9].[4].[1]")
        __designTimeSelection(manager.requestLocation(), "#8570.[9].[4].[2]")
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        __designTimeSelection(completion?(__designTimeSelection(locations.first?.coordinate, "#8570.[9].[5].[0].[0]")), "#8570.[9].[5].[0]")
        completion = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        __designTimeSelection(completion?(nil), "#8570.[9].[6].[0]")
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
            return __designTimeSelection(key, "#8570.[10].[0].[0].[18].[0]")
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
        return __designTimeSelection(name, "#8570.[10].[1].[3]")
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
        __designTimeSelection(NavigationView {
            __designTimeSelection(VStack(spacing: __designTimeInteger("#8570_86", fallback: 16)) {
                __designTimeSelection(HStack {
                    __designTimeSelection(Text(__designTimeSelection(L10n.t(__designTimeString("#8570_87", fallback: "app_title"), lang: __designTimeSelection(store.language, "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[0].arg[0].value.[0].arg[0].value.arg[1].value")), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[0].arg[0].value.[0].arg[0].value"))
                        .font(.largeTitle).bold(), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[0].arg[0].value.[0]")
                    __designTimeSelection(Spacer(), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[0].arg[0].value.[1]")
                    __designTimeSelection(Button(action: { __designTimeSelection(showSettings.toggle(), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[0].arg[0].value.[2].arg[0].value.[0]") }) {
                        __designTimeSelection(Image(systemName: __designTimeString("#8570_88", fallback: "gearshape"))
                            .imageScale(.large), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[0].arg[0].value.[2].arg[1].value.[0]")
                    }
                    .buttonStyle(.plain), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[0].arg[0].value.[2]")
                }
                .padding(.horizontal), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[0]")

                // Moon graphic
                __designTimeSelection(MoonGraphicView(phase: __designTimeSelection(store.result.phase, "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[1].arg[0].value"))
                    .frame(maxWidth: __designTimeInteger("#8570_89", fallback: 320), maxHeight: __designTimeInteger("#8570_90", fallback: 320))
                    .padding(.vertical, __designTimeInteger("#8570_91", fallback: 6)), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[1]")

                // Stats
                __designTimeSelection(HStack(spacing: __designTimeInteger("#8570_92", fallback: 24)) {
                    __designTimeSelection(statBlock(value: __designTimeSelection(String(format: __designTimeString("#8570_93", fallback: "%.1f"), __designTimeSelection(store.result.age, "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[2].arg[1].value.[0].arg[0].value.arg[1].value")), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[2].arg[1].value.[0].arg[0].value"), label: __designTimeSelection(L10n.t(__designTimeString("#8570_94", fallback: "day"), lang: __designTimeSelection(store.language, "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[2].arg[1].value.[0].arg[1].value.arg[1].value")), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[2].arg[1].value.[0].arg[1].value")), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[2].arg[1].value.[0]")
                    __designTimeSelection(statBlock(value: __designTimeSelection(String(format: __designTimeString("#8570_95", fallback: "%.0f%%"), store.result.illumination * __designTimeFloat("#8570_96", fallback: 100.0)), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[2].arg[1].value.[1].arg[0].value"), label: __designTimeSelection(L10n.t(__designTimeString("#8570_97", fallback: "illum"), lang: __designTimeSelection(store.language, "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[2].arg[1].value.[1].arg[1].value.arg[1].value")), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[2].arg[1].value.[1].arg[1].value")), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[2].arg[1].value.[1]")
                }, "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[2]")

                // Date picker
                __designTimeSelection(VStack(spacing: __designTimeInteger("#8570_98", fallback: 8)) {
                    __designTimeSelection(HStack {
                        __designTimeSelection(Text(__designTimeSelection(L10n.t(__designTimeString("#8570_99", fallback: "date"), lang: __designTimeSelection(store.language, "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[3].arg[1].value.[0].arg[0].value.[0].arg[0].value.arg[1].value")), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[3].arg[1].value.[0].arg[0].value.[0].arg[0].value"))
                            .font(.subheadline).foregroundColor(.secondary), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[3].arg[1].value.[0].arg[0].value.[0]")
                        __designTimeSelection(Spacer(), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[3].arg[1].value.[0].arg[0].value.[1]")
                        __designTimeSelection(Button(__designTimeSelection(L10n.t(__designTimeString("#8570_100", fallback: "today"), lang: __designTimeSelection(store.language, "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[3].arg[1].value.[0].arg[0].value.[2].arg[0].value.arg[1].value")), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[3].arg[1].value.[0].arg[0].value.[2].arg[0].value")) {
                            store.selectedDate = Date()
                        }
                        .font(.subheadline), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[3].arg[1].value.[0].arg[0].value.[2]")
                    }, "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[3].arg[1].value.[0]")
                    __designTimeSelection(DatePicker(__designTimeString("#8570_101", fallback: ""), selection: __designTimeSelection($store.selectedDate, "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[3].arg[1].value.[1].arg[1].value"), displayedComponents: [.date])
                        .datePickerStyle(.compact)
                        .labelsHidden(), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[3].arg[1].value.[1]")
                }
                .padding(.horizontal), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[3]")

                // Open calendar
                __designTimeSelection(Button(action: { __designTimeSelection(showCalendar.toggle(), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[4].arg[0].value.[0]") }) {
                    __designTimeSelection(HStack {
                        __designTimeSelection(Image(systemName: __designTimeString("#8570_102", fallback: "calendar")), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[4].arg[1].value.[0].arg[0].value.[0]")
                        __designTimeSelection(Text(__designTimeSelection(L10n.t(__designTimeString("#8570_103", fallback: "open_calendar"), lang: __designTimeSelection(store.language, "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[4].arg[1].value.[0].arg[0].value.[1].arg[0].value.arg[1].value")), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[4].arg[1].value.[0].arg[0].value.[1].arg[0].value")), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[4].arg[1].value.[0].arg[0].value.[1]")
                    }
                    .frame(maxWidth: .infinity), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[4].arg[1].value.[0]")
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[4]")

                __designTimeSelection(Spacer(), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].arg[1].value.[5]")
            }
            .padding(.top)
            .sheet(isPresented: __designTimeSelection($showCalendar, "#8570.[12].[3].property.[0].[0].arg[0].value.[0].modifier[1].arg[0].value")) {
                __designTimeSelection(MonthCalendarView()
                    .environmentObject(__designTimeSelection(store, "#8570.[12].[3].property.[0].[0].arg[0].value.[0].modifier[1].arg[1].value.[0].modifier[0].arg[0].value")), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].modifier[1].arg[1].value.[0]")
            }
            .sheet(isPresented: __designTimeSelection($showSettings, "#8570.[12].[3].property.[0].[0].arg[0].value.[0].modifier[2].arg[0].value")) {
                __designTimeSelection(SettingsView()
                    .environmentObject(__designTimeSelection(store, "#8570.[12].[3].property.[0].[0].arg[0].value.[0].modifier[2].arg[1].value.[0].modifier[0].arg[0].value")), "#8570.[12].[3].property.[0].[0].arg[0].value.[0].modifier[2].arg[1].value.[0]")
            }
            .navigationBarHidden(__designTimeBoolean("#8570_104", fallback: true)), "#8570.[12].[3].property.[0].[0].arg[0].value.[0]")
        }, "#8570.[12].[3].property.[0].[0]")
    }

    @ViewBuilder
    private func statBlock(value: String, label: String) -> some View {
        __designTimeSelection(VStack {
            __designTimeSelection(Text(__designTimeSelection(value, "#8570.[12].[4].[0].arg[0].value.[0].arg[0].value")).font(.title2).bold(), "#8570.[12].[4].[0].arg[0].value.[0]")
            __designTimeSelection(Text(__designTimeSelection(label, "#8570.[12].[4].[0].arg[0].value.[1].arg[0].value")).font(.caption).foregroundColor(.secondary), "#8570.[12].[4].[0].arg[0].value.[1]")
        }
        .frame(minWidth: __designTimeInteger("#8570_105", fallback: 100)), "#8570.[12].[4].[0]")
    }
}

// Moon graphic (simple terminator mask)
struct MoonGraphicView: View {
    var phase: Double // 0..1

    var body: some View {
        __designTimeSelection(GeometryReader { geo in
            let size = min(__designTimeSelection(geo.size.width, "#8570.[13].[1].property.[0].[0].arg[0].value.[0].value.arg[0].value"), __designTimeSelection(geo.size.height, "#8570.[13].[1].property.[0].[0].arg[0].value.[0].value.arg[1].value"))
            __designTimeSelection(ZStack {
                __designTimeSelection(Circle()
                    .fill(__designTimeSelection(Color(.systemGray6), "#8570.[13].[1].property.[0].[0].arg[0].value.[1].arg[0].value.[0].modifier[0].arg[0].value"))
                    .frame(width: __designTimeSelection(size, "#8570.[13].[1].property.[0].[0].arg[0].value.[1].arg[0].value.[0].modifier[1].arg[0].value"), height: __designTimeSelection(size, "#8570.[13].[1].property.[0].[0].arg[0].value.[1].arg[0].value.[0].modifier[1].arg[1].value"))
                    .shadow(radius: __designTimeInteger("#8570_106", fallback: 6)), "#8570.[13].[1].property.[0].[0].arg[0].value.[1].arg[0].value.[0]")
                __designTimeSelection(TerminatorView(phase: __designTimeSelection(phase, "#8570.[13].[1].property.[0].[0].arg[0].value.[1].arg[0].value.[1].arg[0].value"))
                    .frame(width: __designTimeSelection(size, "#8570.[13].[1].property.[0].[0].arg[0].value.[1].arg[0].value.[1].modifier[0].arg[0].value"), height: __designTimeSelection(size, "#8570.[13].[1].property.[0].[0].arg[0].value.[1].arg[0].value.[1].modifier[0].arg[1].value"))
                    .blendMode(.destinationOut)
                    .compositingGroup(), "#8570.[13].[1].property.[0].[0].arg[0].value.[1].arg[0].value.[1]")
                __designTimeSelection(Circle()
                    .stroke(__designTimeSelection(Color(.systemGray3), "#8570.[13].[1].property.[0].[0].arg[0].value.[1].arg[0].value.[2].modifier[0].arg[0].value"), lineWidth: __designTimeFloat("#8570_107", fallback: 0.5))
                    .frame(width: __designTimeSelection(size, "#8570.[13].[1].property.[0].[0].arg[0].value.[1].arg[0].value.[2].modifier[1].arg[0].value"), height: __designTimeSelection(size, "#8570.[13].[1].property.[0].[0].arg[0].value.[1].arg[0].value.[2].modifier[1].arg[1].value")), "#8570.[13].[1].property.[0].[0].arg[0].value.[1].arg[0].value.[2]")
            }
            .frame(width: __designTimeSelection(size, "#8570.[13].[1].property.[0].[0].arg[0].value.[1].modifier[0].arg[0].value"), height: __designTimeSelection(size, "#8570.[13].[1].property.[0].[0].arg[0].value.[1].modifier[0].arg[1].value")), "#8570.[13].[1].property.[0].[0].arg[0].value.[1]")
        }
        .aspectRatio(__designTimeInteger("#8570_108", fallback: 1), contentMode: .fit)
        .padding(), "#8570.[13].[1].property.[0].[0]")
    }
}

struct TerminatorView: View {
    var phase: Double

    var body: some View {
        __designTimeSelection(GeometryReader { geo in
            let w = min(__designTimeSelection(geo.size.width, "#8570.[14].[1].property.[0].[0].arg[0].value.[0].value.arg[0].value"), __designTimeSelection(geo.size.height, "#8570.[14].[1].property.[0].[0].arg[0].value.[0].value.arg[1].value"))
            // offset maps phase (0..1) to ellipse offset
            let offset = CGFloat((phase - __designTimeFloat("#8570_109", fallback: 0.5)) * __designTimeFloat("#8570_110", fallback: 1.6)) * w
            __designTimeSelection(Ellipse()
                .frame(width: w * __designTimeFloat("#8570_111", fallback: 1.6), height: __designTimeSelection(w, "#8570.[14].[1].property.[0].[0].arg[0].value.[2].modifier[0].arg[1].value"))
                .offset(x: __designTimeSelection(offset, "#8570.[14].[1].property.[0].[0].arg[0].value.[2].modifier[1].arg[0].value"))
                .foregroundColor(.black), "#8570.[14].[1].property.[0].[0].arg[0].value.[2]")
        }, "#8570.[14].[1].property.[0].[0]")
    }
}

// Calendar month view (sheet)
struct MonthCalendarView: View {
    @EnvironmentObject var store: MoonStore
    @Environment(\.presentationMode) var presentation

    @State private var currentMonthDate: Date = Date()

    var body: some View {
        __designTimeSelection(NavigationView {
            __designTimeSelection(VStack {
                __designTimeSelection(HStack {
                    __designTimeSelection(Button(action: { __designTimeSelection(changeMonth(by: __designTimeInteger("#8570_112", fallback: -1)), "#8570.[15].[3].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[0]") }) { __designTimeSelection(Image(systemName: __designTimeString("#8570_113", fallback: "chevron.left")), "#8570.[15].[3].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[0].arg[1].value.[0]") }, "#8570.[15].[3].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[0]")
                    __designTimeSelection(Spacer(), "#8570.[15].[3].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[1]")
                    __designTimeSelection(Text(__designTimeSelection(monthTitle(for: __designTimeSelection(currentMonthDate, "#8570.[15].[3].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[2].arg[0].value.arg[0].value")), "#8570.[15].[3].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[2].arg[0].value"))
                        .font(.headline), "#8570.[15].[3].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[2]")
                    __designTimeSelection(Spacer(), "#8570.[15].[3].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[3]")
                    __designTimeSelection(Button(action: { __designTimeSelection(changeMonth(by: __designTimeInteger("#8570_114", fallback: 1)), "#8570.[15].[3].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[4].arg[0].value.[0]") }) { __designTimeSelection(Image(systemName: __designTimeString("#8570_115", fallback: "chevron.right")), "#8570.[15].[3].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[4].arg[1].value.[0]") }, "#8570.[15].[3].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[4]")
                }
                .padding(.horizontal), "#8570.[15].[3].property.[0].[0].arg[0].value.[0].arg[0].value.[0]")

                __designTimeSelection(CalendarGridView(centerDate: __designTimeSelection(currentMonthDate, "#8570.[15].[3].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[0].value"))
                    .environmentObject(__designTimeSelection(store, "#8570.[15].[3].property.[0].[0].arg[0].value.[0].arg[0].value.[1].modifier[0].arg[0].value")), "#8570.[15].[3].property.[0].[0].arg[0].value.[0].arg[0].value.[1]")

                __designTimeSelection(Spacer(), "#8570.[15].[3].property.[0].[0].arg[0].value.[0].arg[0].value.[2]")
            }
            .navigationTitle(__designTimeSelection(L10n.t(__designTimeString("#8570_116", fallback: "calendar"), lang: __designTimeSelection(store.language, "#8570.[15].[3].property.[0].[0].arg[0].value.[0].modifier[0].arg[0].value.arg[1].value")), "#8570.[15].[3].property.[0].[0].arg[0].value.[0].modifier[0].arg[0].value"))
            .toolbar {
                __designTimeSelection(ToolbarItem(placement: .confirmationAction) {
                    __designTimeSelection(Button(__designTimeSelection(L10n.t(__designTimeString("#8570_117", fallback: "done"), lang: __designTimeSelection(store.language, "#8570.[15].[3].property.[0].[0].arg[0].value.[0].modifier[1].arg[0].value.[0].arg[1].value.[0].arg[0].value.arg[1].value")), "#8570.[15].[3].property.[0].[0].arg[0].value.[0].modifier[1].arg[0].value.[0].arg[1].value.[0].arg[0].value")) {
                        __designTimeSelection(presentation.wrappedValue.dismiss(), "#8570.[15].[3].property.[0].[0].arg[0].value.[0].modifier[1].arg[0].value.[0].arg[1].value.[0].arg[1].value.[0]")
                    }, "#8570.[15].[3].property.[0].[0].arg[0].value.[0].modifier[1].arg[0].value.[0].arg[1].value.[0]")
                }, "#8570.[15].[3].property.[0].[0].arg[0].value.[0].modifier[1].arg[0].value.[0]")
            }, "#8570.[15].[3].property.[0].[0].arg[0].value.[0]")
        }, "#8570.[15].[3].property.[0].[0]")
    }

    private func changeMonth(by delta: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: __designTimeSelection(delta, "#8570.[15].[4].[0]"), to: __designTimeSelection(currentMonthDate, "#8570.[15].[4].[0]")) {
            currentMonthDate = next
        }
    }

    private func monthTitle(for date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: store.language == .ru ? __designTimeString("#8570_118", fallback: "ru_RU") : __designTimeString("#8570_119", fallback: "en_US"))
        df.dateFormat = __designTimeString("#8570_120", fallback: "LLLL yyyy")
        return __designTimeSelection(df.string(from: __designTimeSelection(date, "#8570.[15].[5].[3].[0]")).capitalized, "#8570.[15].[5].[3]")
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
        let comps = cal.dateComponents([.year, .month], from: __designTimeSelection(centerDate, "#8570.[16].[3].property.[0].[1].value.modifier[0].arg[1].value"))
        guard let startOfMonth = cal.date(from: __designTimeSelection(comps, "#8570.[16].[3].property.[0].[2]")),
              let range = cal.range(of: .day, in: .month, for: __designTimeSelection(centerDate, "#8570.[16].[3].property.[0].[2]")) else {
            return __designTimeSelection(AnyView(__designTimeSelection(Text(__designTimeString("#8570_121", fallback: "Ошибка календаря")), "#8570.[16].[3].property.[0].[2]")), "#8570.[16].[3].property.[0].[2]")
        }
        let firstWeekday = cal.component(.weekday, from: __designTimeSelection(startOfMonth, "#8570.[16].[3].property.[0].[3].value.modifier[0].arg[1].value")) // 1 = Sunday
        let pad = (firstWeekday + __designTimeInteger("#8570_122", fallback: 6)) % __designTimeInteger("#8570_123", fallback: 7) // convert to Monday start
        let days = Array(__designTimeSelection(range, "#8570.[16].[3].property.[0].[5].value.arg[0].value"))
        let padded = Array(repeating: __designTimeInteger("#8570_124", fallback: 0), count: __designTimeSelection(pad, "#8570.[16].[3].property.[0].[6].value.[1]")) + days

        return __designTimeSelection(AnyView(
            __designTimeSelection(VStack {
                __designTimeSelection(HStack {
                    __designTimeSelection(ForEach([__designTimeString("#8570_125", fallback: "Пн"),__designTimeString("#8570_126", fallback: "Вт"),__designTimeString("#8570_127", fallback: "Ср"),__designTimeString("#8570_128", fallback: "Чт"),__designTimeString("#8570_129", fallback: "Пт"),__designTimeString("#8570_130", fallback: "Сб"),__designTimeString("#8570_131", fallback: "Вс")], id: \.self) { d in
                        __designTimeSelection(Text(__designTimeSelection(d, "#8570.[16].[3].property.[0].[7].arg[0].value.arg[0].value.[0].arg[0].value.[0].arg[2].value.[0].arg[0].value")).font(.caption).frame(maxWidth: .infinity), "#8570.[16].[3].property.[0].[7].arg[0].value.arg[0].value.[0].arg[0].value.[0].arg[2].value.[0]")
                    }, "#8570.[16].[3].property.[0].[7].arg[0].value.arg[0].value.[0].arg[0].value.[0]")
                }, "#8570.[16].[3].property.[0].[7].arg[0].value.arg[0].value.[0]")
                __designTimeSelection(LazyVGrid(columns: __designTimeSelection(Array(repeating: __designTimeSelection(GridItem(__designTimeSelection(.flexible(), "#8570.[16].[3].property.[0].[7].arg[0].value.arg[0].value.[1].arg[0].value.arg[0].value.arg[0]")), "#8570.[16].[3].property.[0].[7].arg[0].value.arg[0].value.[1].arg[0].value.arg[0].value"), count: __designTimeInteger("#8570_132", fallback: 7)), "#8570.[16].[3].property.[0].[7].arg[0].value.arg[0].value.[1].arg[0].value"), spacing: __designTimeInteger("#8570_133", fallback: 8)) {
                    __designTimeSelection(ForEach(__designTimeSelection(padded.indices, "#8570.[16].[3].property.[0].[7].arg[0].value.arg[0].value.[1].arg[2].value.[0].arg[0].value"), id: \.self) { idx in
                        if padded[__designTimeSelection(idx, "#8570.[16].[3].property.[0].[7].arg[0].value.arg[0].value.[1].arg[2].value.[0].arg[2].value.[0]")] == __designTimeInteger("#8570_134", fallback: 0) {
                            __designTimeSelection(Color.clear.frame(height: __designTimeInteger("#8570_135", fallback: 72)), "#8570.[16].[3].property.[0].[7].arg[0].value.arg[0].value.[1].arg[2].value.[0].arg[2].value.[0].[0].[0]")
                        } else {
                            let day = padded[__designTimeSelection(idx, "#8570.[16].[3].property.[0].[7].arg[0].value.arg[0].value.[1].arg[2].value.[0].arg[2].value.[0].[1].[0].value.[0].value")]
                            let date = cal.date(byAdding: .day, value: day - __designTimeInteger("#8570_136", fallback: 1), to: __designTimeSelection(startOfMonth, "#8570.[16].[3].property.[0].[7].arg[0].value.arg[0].value.[1].arg[2].value.[0].arg[2].value.[0].[1].[1].value.[1]"))!
                            __designTimeSelection(CalendarDayCell(date: __designTimeSelection(date, "#8570.[16].[3].property.[0].[7].arg[0].value.arg[0].value.[1].arg[2].value.[0].arg[2].value.[0].[1].[2].arg[0].value"))
                                .environmentObject(__designTimeSelection(store, "#8570.[16].[3].property.[0].[7].arg[0].value.arg[0].value.[1].arg[2].value.[0].arg[2].value.[0].[1].[2].modifier[0].arg[0].value"))
                                .onTapGesture {
                                    store.selectedDate = date
                                }, "#8570.[16].[3].property.[0].[7].arg[0].value.arg[0].value.[1].arg[2].value.[0].arg[2].value.[0].[1].[2]")
                        }
                    }, "#8570.[16].[3].property.[0].[7].arg[0].value.arg[0].value.[1].arg[2].value.[0]")
                }
                .padding(.horizontal), "#8570.[16].[3].property.[0].[7].arg[0].value.arg[0].value.[1]")
            }, "#8570.[16].[3].property.[0].[7].arg[0].value")
        ), "#8570.[16].[3].property.[0].[7]")
    }
}

struct CalendarDayCell: View {
    @EnvironmentObject var store: MoonStore
    var date: Date

    var body: some View {
        let res = store.moonData(for: __designTimeSelection(date, "#8570.[17].[2].property.[0].[0].value.modifier[0].arg[0].value"))
        __designTimeSelection(VStack(spacing: __designTimeInteger("#8570_137", fallback: 6)) {
            __designTimeSelection(Text("\(__designTimeSelection(Calendar.current.component(.day, from: __designTimeSelection(date, "#8570.[17].[2].property.[0].[1].arg[1].value.[0].arg[0].value.[1].value.arg[0].value.modifier[0].arg[1].value")), "#8570.[17].[2].property.[0].[1].arg[1].value.[0].arg[0].value.[1].value.arg[0].value"))")
                .font(.caption), "#8570.[17].[2].property.[0].[1].arg[1].value.[0]")
            __designTimeSelection(MoonGraphicView(phase: __designTimeSelection(res.phase, "#8570.[17].[2].property.[0].[1].arg[1].value.[1].arg[0].value"))
                .frame(height: __designTimeInteger("#8570_138", fallback: 44)), "#8570.[17].[2].property.[0].[1].arg[1].value.[1]")
            __designTimeSelection(Text(__designTimeSelection(String(format: __designTimeString("#8570_139", fallback: "%.0f%%"), res.illumination * __designTimeFloat("#8570_140", fallback: 100.0)), "#8570.[17].[2].property.[0].[1].arg[1].value.[2].arg[0].value"))
                .font(.caption2)
                .foregroundColor(.secondary), "#8570.[17].[2].property.[0].[1].arg[1].value.[2]")
        }
        .padding(__designTimeInteger("#8570_141", fallback: 6))
        .background(__designTimeSelection(RoundedRectangle(cornerRadius: __designTimeInteger("#8570_142", fallback: 8)).fill(__designTimeSelection(Color(__designTimeSelection(UIColor.secondarySystemBackground, "#8570.[17].[2].property.[0].[1].modifier[1].arg[0].value.modifier[0].arg[0].value.arg[0].value")), "#8570.[17].[2].property.[0].[1].modifier[1].arg[0].value.modifier[0].arg[0].value")), "#8570.[17].[2].property.[0].[1].modifier[1].arg[0].value")), "#8570.[17].[2].property.[0].[1]")
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
        __designTimeSelection(NavigationView {
            __designTimeSelection(Form {
                __designTimeSelection(Section {
                    __designTimeSelection(Picker(selection: __designTimeSelection(Binding(get: { __designTimeSelection(store.language, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.arg[0].value.[0]") }, set: { store.language = $0 }), "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[0].arg[0].value"), label: __designTimeSelection(Text(__designTimeSelection(L10n.t(__designTimeString("#8570_143", fallback: "language"), lang: __designTimeSelection(store.language, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[0].arg[1].value.arg[0].value.arg[1].value")), "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[0].arg[1].value.arg[0].value")), "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[0].arg[1].value")) {
                        __designTimeSelection(Text(__designTimeSelection(L10n.t(__designTimeString("#8570_144", fallback: "language_ru"), lang: __designTimeSelection(store.language, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[0].arg[2].value.[0].arg[0].value.arg[1].value")), "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[0].arg[2].value.[0].arg[0].value")).tag(__designTimeSelection(AppLanguage.ru, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[0].arg[2].value.[0].modifier[0].arg[0].value")), "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[0].arg[2].value.[0]")
                        __designTimeSelection(Text(__designTimeSelection(L10n.t(__designTimeString("#8570_145", fallback: "language_en"), lang: __designTimeSelection(store.language, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[0].arg[2].value.[1].arg[0].value.arg[1].value")), "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[0].arg[2].value.[1].arg[0].value")).tag(__designTimeSelection(AppLanguage.en, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[0].arg[2].value.[1].modifier[0].arg[0].value")), "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[0].arg[2].value.[1]")
                    }, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[0].arg[0].value.[0]")
                }, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[0]")

                __designTimeSelection(Section(header: __designTimeSelection(Text(L10n.t(__designTimeString("#8570_146", fallback: "latitude"), lang: __designTimeSelection(store.language, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[0].value.arg[0].value.[1]")) + __designTimeString("#8570_147", fallback: " / ") + L10n.t(__designTimeString("#8570_148", fallback: "longitude"), lang: __designTimeSelection(store.language, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[0].value.arg[0].value.[3]"))), "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[0].value")) {
                    __designTimeSelection(Toggle(__designTimeSelection(L10n.t(__designTimeString("#8570_149", fallback: "use_device_location"), lang: __designTimeSelection(store.language, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[1].value.[0].arg[0].value.arg[1].value")), "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[1].value.[0].arg[0].value"), isOn: __designTimeSelection($useDeviceLocation, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[1].value.[0].arg[1].value"))
                        .onChange(of: __designTimeSelection(useDeviceLocation, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[1].value.[0].modifier[0].arg[0].value")) { newValue in
                            if newValue { __designTimeSelection(requestLocation(), "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[1].value.[0].modifier[0].arg[1].value.[0].[0].[0]") } else { store.coordinate = nil }
                        }, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[1].value.[0]")
                    __designTimeSelection(TextField(__designTimeSelection(L10n.t(__designTimeString("#8570_150", fallback: "latitude"), lang: __designTimeSelection(store.language, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[1].value.[1].arg[0].value.arg[1].value")), "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[1].value.[1].arg[0].value"), text: __designTimeSelection($latText, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[1].value.[1].arg[1].value"))
                        .keyboardType(.decimalPad), "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[1].value.[1]")
                    __designTimeSelection(TextField(__designTimeSelection(L10n.t(__designTimeString("#8570_151", fallback: "longitude"), lang: __designTimeSelection(store.language, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[1].value.[2].arg[0].value.arg[1].value")), "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[1].value.[2].arg[0].value"), text: __designTimeSelection($lonText, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[1].value.[2].arg[1].value"))
                        .keyboardType(.decimalPad), "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[1].value.[2]")
                    __designTimeSelection(Button(__designTimeSelection(L10n.t(__designTimeString("#8570_152", fallback: "save"), lang: __designTimeSelection(store.language, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[1].value.[3].arg[0].value.arg[1].value")), "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[1].value.[3].arg[0].value")) {
                        if let la = Double(__designTimeSelection(latText, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[1].value.[3].arg[1].value.[0]")), let lo = Double(__designTimeSelection(lonText, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[1].value.[3].arg[1].value.[0]")) {
                            store.coordinate = CLLocationCoordinate2D(latitude: __designTimeSelection(la, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[1].value.[3].arg[1].value.[0].[0].[0].[0]"), longitude: __designTimeSelection(lo, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[1].value.[3].arg[1].value.[0].[0].[0].[0]"))
                        }
                    }, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[1].value.[3]")
                    __designTimeSelection(Button(__designTimeSelection(L10n.t(__designTimeString("#8570_153", fallback: "reset_coords"), lang: __designTimeSelection(store.language, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[1].value.[4].arg[0].value.arg[1].value")), "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[1].value.[4].arg[0].value")) {
                        store.coordinate = nil
                        latText = __designTimeString("#8570_154", fallback: "")
                        lonText = __designTimeString("#8570_155", fallback: "")
                        useDeviceLocation = __designTimeBoolean("#8570_156", fallback: false)
                    }, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1].arg[1].value.[4]")
                }, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[1]")

                __designTimeSelection(Section {
                    __designTimeSelection(Button(__designTimeSelection(L10n.t(__designTimeString("#8570_157", fallback: "done"), lang: __designTimeSelection(store.language, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[2].arg[0].value.[0].arg[0].value.arg[1].value")), "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[2].arg[0].value.[0].arg[0].value")) {
                        __designTimeSelection(presentation.wrappedValue.dismiss(), "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[2].arg[0].value.[0].arg[1].value.[0]")
                    }, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[2].arg[0].value.[0]")
                }, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].arg[0].value.[2]")
            }
            .navigationTitle(__designTimeSelection(L10n.t(__designTimeString("#8570_158", fallback: "settings"), lang: __designTimeSelection(store.language, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].modifier[0].arg[0].value.arg[1].value")), "#8570.[18].[5].property.[0].[0].arg[0].value.[0].modifier[0].arg[0].value"))
            .onAppear {
                if let c = store.coordinate {
                    latText = String(format: __designTimeString("#8570_159", fallback: "%.6f"), __designTimeSelection(c.latitude, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].modifier[1].arg[0].value.[0].[0].[0].[1]"))
                    lonText = String(format: __designTimeString("#8570_160", fallback: "%.6f"), __designTimeSelection(c.longitude, "#8570.[18].[5].property.[0].[0].arg[0].value.[0].modifier[1].arg[0].value.[0].[0].[1].[1]"))
                } else {
                    latText = __designTimeString("#8570_161", fallback: "")
                    lonText = __designTimeString("#8570_162", fallback: "")
                }
            }, "#8570.[18].[5].property.[0].[0].arg[0].value.[0]")
        }, "#8570.[18].[5].property.[0].[0]")
    }

    private func requestLocation() {
        __designTimeSelection(LocationManager.shared.requestLocation { coord in
            __designTimeSelection(DispatchQueue.main.async {
                if let coord = coord {
                    store.coordinate = coord
                    latText = String(format: __designTimeString("#8570_163", fallback: "%.6f"), __designTimeSelection(coord.latitude, "#8570.[18].[6].[0].modifier[0].arg[0].value.[0].modifier[0].arg[0].value.[0].[0].[1].[1]"))
                    lonText = String(format: __designTimeString("#8570_164", fallback: "%.6f"), __designTimeSelection(coord.longitude, "#8570.[18].[6].[0].modifier[0].arg[0].value.[0].modifier[0].arg[0].value.[0].[0].[2].[1]"))
                } else {
                    // nothing found
                    // could show alert; keeping minimal
                }
            }, "#8570.[18].[6].[0].modifier[0].arg[0].value.[0]")
        }, "#8570.[18].[6].[0]")
    }
}

// MARK: - Preview

#if DEBUG
struct MoonPhaseAll_Previews: PreviewProvider {
    static var previews: some View {
        __designTimeSelection(ContentView().environmentObject(__designTimeSelection(MoonStore.shared, "#8570.[19].[0].[0].[0].property.[0].[0].modifier[0].arg[0].value")), "#8570.[19].[0].[0].[0].property.[0].[0]")
    }
}
#endif

// End of file
