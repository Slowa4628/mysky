// MoonPhaseAll.swift
import SwiftUI
import Combine
import CoreLocation
import WidgetKit

// MARK: - Models

public struct MoonPhaseResult: Equatable {
    public let date: Date
    public let age: Double
    public let illumination: Double
    public let phase: Double
    public let distanceKm: Double?
    public let phaseName: String?
    public let moonrise: Date?
    public let moonset: Date?
}

// MARK: - Cache

final class MoonCache {
    static let shared = MoonCache()
    
    private let cache = NSCache<NSString, CachedMoonResult>()
    private let calendar = Calendar.current
    private let queue = DispatchQueue(label: "moon.cache", attributes: .concurrent)
    
    private class CachedMoonResult {
        let result: MoonPhaseResult
        let coordinate: CLLocationCoordinate2D?
        let timestamp: Date
        
        init(result: MoonPhaseResult, coordinate: CLLocationCoordinate2D?, timestamp: Date) {
            self.result = result
            self.coordinate = coordinate
            self.timestamp = timestamp
        }
    }
    
    private init() {
        cache.countLimit = 100 // Ограничиваем размер кеша
    }
    
    func get(for date: Date, coordinate: CLLocationCoordinate2D?) -> MoonPhaseResult? {
        let normalizedDate = normalizeDate(date)
        let cacheKey = cacheKey(for: normalizedDate, coordinate: coordinate)
        
        return queue.sync {
            guard let cached = cache.object(forKey: cacheKey) else {
                return nil
            }
            
            // Проверяем актуальность кеша (кешируем на 1 час)
            let cacheAge = Date().timeIntervalSince(cached.timestamp)
            guard cacheAge < 3600 else {
                cache.removeObject(forKey: cacheKey)
                return nil
            }
            
            return cached.result
        }
    }
    
    func set(_ result: MoonPhaseResult, for date: Date, coordinate: CLLocationCoordinate2D?) {
        let normalizedDate = normalizeDate(date)
        let cacheKey = cacheKey(for: normalizedDate, coordinate: coordinate)
        
        queue.async(flags: .barrier) {
            let cachedResult = CachedMoonResult(
                result: result,
                coordinate: coordinate,
                timestamp: Date()
            )
            self.cache.setObject(cachedResult, forKey: cacheKey)
        }
    }
    
    func clear() {
        queue.async(flags: .barrier) {
            self.cache.removeAllObjects()
        }
    }
    
    private func normalizeDate(_ date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: components) ?? date
    }
    
    private func cacheKey(for date: Date, coordinate: CLLocationCoordinate2D?) -> NSString {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        
        if let coordinate = coordinate {
            return "\(dateString)_\(coordinate.latitude)_\(coordinate.longitude)" as NSString
        } else {
            return dateString as NSString
        }
    }
}

// MARK: - Engine Protocol & Default Engine

public protocol MoonEngineProtocol {
    func calculate(for date: Date, coordinate: CLLocationCoordinate2D?) -> MoonPhaseResult
}

public final class DefaultMoonEngine: MoonEngineProtocol {
    private let synodicMonth = 29.53058867

    public init() {}

    public func calculate(for date: Date, coordinate: CLLocationCoordinate2D?) -> MoonPhaseResult {
        let jd = julianDate(from: date)
        
        // Более точное вычисление фазы Луны
        let daysSinceKnownNewMoon = jd - 2451549.5 // известное новолуние около J2000
        var age = daysSinceKnownNewMoon.truncatingRemainder(dividingBy: synodicMonth)
        if age < 0 { age += synodicMonth }
        
        let phase = age / synodicMonth
        let phaseAngle = 2.0 * Double.pi * phase
        let illumination = 0.5 * (1.0 - cos(phaseAngle))
        
        // Упрощенное вычисление расстояния для производительности
        let distanceKm = calculateMoonDistance(julianDate: jd)
        
        let phaseName = L10n.phaseName(for: phase, lang: .en) // базовое значение
        
        // Расчет времени восхода и захода Луны
        let (moonrise, moonset) = calculateMoonRiseSet(for: date, coordinate: coordinate)

        return MoonPhaseResult(
            date: date,
            age: age,
            illumination: illumination,
            phase: phase,
            distanceKm: distanceKm,
            phaseName: phaseName,
            moonrise: moonrise,
            moonset: moonset
        )
    }

    private func calculateMoonDistance(julianDate: Double) -> Double {
        let T = (julianDate - 2451545.0) / 36525.0
        let D = deg2rad(297.8501921 + 445267.1114034 * T)
        let M = deg2rad(357.5291092 + 35999.0502909 * T)
        let Mp = deg2rad(134.9633964 + 477198.8675055 * T)
        
        return 385000.56 - 20905.355 * cos(Mp)
    }
    
    private func calculateMoonRiseSet(for date: Date, coordinate: CLLocationCoordinate2D?) -> (moonrise: Date?, moonset: Date?) {
        guard let coordinate = coordinate else {
            return (nil, nil)
        }
        
        let calendar = Calendar.current
        let timeZone = TimeZone.current
        
        // Используем точный алгоритм с астрономическими расчетами
        let jd = julianDate(from: date)
        
        // Вычисляем для текущего дня и следующего
        let riseSetToday = calculateAccurateMoonRiseSet(jd: jd, latitude: coordinate.latitude, longitude: coordinate.longitude, timeZone: timeZone)
        let riseSetTomorrow = calculateAccurateMoonRiseSet(jd: jd + 1.0, latitude: coordinate.latitude, longitude: coordinate.longitude, timeZone: timeZone)
        
        // Комбинируем результаты
        var moonrise: Date?
        var moonset: Date?
        
        if let rise = riseSetToday.moonrise {
            moonrise = rise
        } else if let rise = riseSetTomorrow.moonrise, isSameCalendarDay(date1: date, date2: rise, timeZone: timeZone) {
            moonrise = rise
        }
        
        if let set = riseSetToday.moonset {
            moonset = set
        } else if let set = riseSetTomorrow.moonset, isSameCalendarDay(date1: date, date2: set, timeZone: timeZone) {
            moonset = set
        }
        
        return (moonrise, moonset)
    }
    
    private func calculateAccurateMoonRiseSet(jd: Double, latitude: Double, longitude: Double, timeZone: TimeZone) -> (moonrise: Date?, moonset: Date?) {
        let latRad = deg2rad(latitude)
        let lonRad = deg2rad(longitude)
        
        var moonrise: Date?
        var moonset: Date?
        
        // Проверяем 24 часа с шагом в 1 час
        for hour in 0..<24 {
            let currentJD = jd + Double(hour) / 24.0
            let nextJD = jd + Double(hour + 1) / 24.0
            
            let alt1 = calculateMoonAltitude(jd: currentJD, latitude: latRad, longitude: lonRad)
            let alt2 = calculateMoonAltitude(jd: nextJD, latitude: latRad, longitude: lonRad)
            
            // Проверяем пересечение горизонта (восход)
            if alt1 <= 0 && alt2 > 0 {
                if let riseTime = findCrossingTime(startJD: currentJD, endJD: nextJD, latitude: latRad, longitude: lonRad, isRise: true) {
                    moonrise = dateFromJulianDate(riseTime)
                }
            }
            
            // Проверяем пересечение горизонта (заход)
            if alt1 > 0 && alt2 <= 0 {
                if let setTime = findCrossingTime(startJD: currentJD, endJD: nextJD, latitude: latRad, longitude: lonRad, isRise: false) {
                    moonset = dateFromJulianDate(setTime)
                }
            }
        }
        
        return (moonrise, moonset)
    }
    
    private func findCrossingTime(startJD: Double, endJD: Double, latitude: Double, longitude: Double, isRise: Bool) -> Double? {
        let tolerance = 0.000001 // ~0.1 секунды
        var low = startJD
        var high = endJD
        
        for _ in 0..<20 { // Максимум 20 итераций
            let mid = (low + high) / 2.0
            let altitude = calculateMoonAltitude(jd: mid, latitude: latitude, longitude: longitude)
            
            if abs(altitude) < tolerance {
                return mid
            }
            
            if (isRise && altitude > 0) || (!isRise && altitude < 0) {
                high = mid
            } else {
                low = mid
            }
        }
        
        return (low + high) / 2.0
    }
    
    private func calculateMoonAltitude(jd: Double, latitude: Double, longitude: Double) -> Double {
        let (ra, dec) = calculateMoonPosition(jd: jd)
        let lst = calculateLocalSiderealTime(jd: jd, longitude: longitude)
        
        let hourAngle = lst - ra
        let sinAlt = sin(latitude) * sin(dec) + cos(latitude) * cos(dec) * cos(hourAngle)
        
        // Корректировка для рефракции
        let altitude = asin(sinAlt)
        return altitude - deg2rad(0.5667)
    }
    
    private func calculateMoonPosition(jd: Double) -> (ra: Double, dec: Double) {
        // Вычисляем время в юлианских столетиях от эпохи J2000.0
        let T = (jd - 2451545.0) / 36525.0
        
        // Средние элементы орбиты Луны
        let Lp = deg2rad(218.3164477 + 481267.88123421 * T - 0.0015786 * T * T + T * T * T / 538841.0 - T * T * T * T / 65194000.0)
        let D = deg2rad(297.8501921 + 445267.1114034 * T - 0.0018819 * T * T + T * T * T / 545868.0 - T * T * T * T / 113065000.0)
        let M = deg2rad(357.5291092 + 35999.0502909 * T - 0.0001536 * T * T + T * T * T / 24490000.0)
        let Mp = deg2rad(134.9633964 + 477198.8675055 * T + 0.0087414 * T * T + T * T * T / 69699.0 - T * T * T * T / 14712000.0)
        let F = deg2rad(93.2720950 + 483202.0175233 * T - 0.0036539 * T * T - T * T * T / 3526000.0 + T * T * T * T / 863310000.0)
        
        // Долгота Луны с учетом возмущений
        var longitude = Lp + deg2rad(
            6.288774 * sin(Mp) +
            1.274027 * sin(2 * D - Mp) +
            0.658314 * sin(2 * D) +
            0.213618 * sin(2 * Mp) -
            0.185116 * sin(M) -
            0.114332 * sin(2 * F) +
            0.058793 * sin(2 * D - 2 * Mp) +
            0.057066 * sin(2 * D - M - Mp) +
            0.053322 * sin(2 * D + Mp) +
            0.045758 * sin(2 * D - M) +
            0.041024 * sin(Mp - M) -
            0.034718 * sin(D) -
            0.030383 * sin(Mp + M) +
            0.015326 * sin(2 * D - 2 * F) -
            0.012528 * sin(2 * F + Mp) -
            0.01098 * sin(2 * F - Mp) +
            0.010674 * sin(4 * D - Mp) +
            0.010034 * sin(3 * Mp) +
            0.008548 * sin(4 * D - 2 * Mp)
        )
        
        // Широта Луны
        let latitude = deg2rad(
            5.128122 * sin(F) +
            0.280602 * sin(Mp + F) +
            0.277693 * sin(Mp - F) +
            0.173238 * sin(2 * D - F) +
            0.055413 * sin(2 * D + F - Mp) +
            0.046272 * sin(2 * D + F - Mp) +
            0.032573 * sin(2 * D + F) +
            0.017198 * sin(2 * Mp + F) +
            0.009267 * sin(2 * D + Mp - F) +
            0.008823 * sin(2 * Mp - F) +
            0.008247 * sin(2 * D - M - F) +
            0.004323 * sin(2 * D - M - Mp + F) +
            0.0042 * sin(2 * D + F + Mp) +
            0.003372 * sin(F - M - 2 * D) +
            0.002472 * sin(2 * D + F - M - Mp) +
            0.002222 * sin(2 * D + F - M) +
            0.002072 * sin(2 * D + F - Mp - Mp) +
            0.001877 * sin(F - M + Mp) +
            0.001828 * sin(4 * D - F - Mp) +
            0.001803 * sin(F + M) +
            0.00175 * sin(3 * F) +
            0.00157 * sin(Mp - M - F) +
            0.001487 * sin(F + D) +
            0.001481 * sin(F + M + Mp) +
            0.001417 * sin(F - M - Mp) +
            0.00135 * sin(F - M) +
            0.00133 * sin(F - D) +
            0.001106 * sin(F + 3 * Mp) +
            0.00102 * sin(4 * D - F) +
            0.000833 * sin(F + 4 * D - Mp) +
            0.000781 * sin(Mp - 3 * F) +
            0.00067 * sin(F + 4 * D - 2 * Mp) +
            0.000606 * sin(2 * D - 3 * F) +
            0.000597 * sin(2 * D + 2 * Mp - F) +
            0.000492 * sin(2 * D + Mp - F - M) +
            0.00045 * sin(2 * Mp - F - 2 * D) +
            0.000439 * sin(3 * Mp - F) +
            0.000423 * sin(F + 2 * D + 2 * Mp) +
            0.000422 * sin(2 * D - F - 3 * Mp) +
            0.000421 * sin(F + 3 * Mp - 2 * D) +
            0.000381 * sin(2 * D + Mp - F - M)
        )
        
        // Расстояние до Луны в километрах
        let distance = 385000.56 -
            20905.355 * cos(Mp) -
            3699.11 * cos(2 * D - Mp) -
            2955.97 * cos(2 * D) -
            569.92 * cos(2 * Mp) +
            246.16 * cos(2 * D - 2 * Mp) -
            205.96 * cos(2 * D - M - Mp) -
            171.3 * cos(2 * D + Mp) -
            152.53 * cos(2 * D - M)
        
        // Наклон эклиптики
        let eclipticObliquity = deg2rad(23.43929111 - 0.013004167 * T - 1.638888e-07 * T * T + 5.036111e-07 * T * T * T)
        
        // Преобразование в экваториальные координаты
        let sinE = sin(eclipticObliquity)
        let cosE = cos(eclipticObliquity)
        
        let ra = atan2(sin(longitude) * cosE - tan(latitude) * sinE, cos(longitude))
        let dec = asin(sin(latitude) * cosE + cos(latitude) * sinE * sin(longitude))
        
        return (ra, dec)
    }
    
    private func calculateLocalSiderealTime(jd: Double, longitude: Double) -> Double {
        let T = (jd - 2451545.0) / 36525.0
        
        // Среднее звездное время в Гринвиче (в градусах)
        let GMST = 280.46061837 +
                   360.98564736629 * (jd - 2451545.0) +
                   0.000387933 * T * T -
                   T * T * T / 38710000.0
        
        // Местное звездное время (в радианах)
        let lst = deg2rad(GMST + longitude)
        
        // Нормализуем до диапазона 0-2π
        return lst.truncatingRemainder(dividingBy: 2 * Double.pi)
    }
    
    private func dateFromJulianDate(_ jd: Double) -> Date {
        let timeInterval = (jd - 2440587.5) * 86400.0
        return Date(timeIntervalSince1970: timeInterval)
    }
    
    private func isSameCalendarDay(date1: Date, date2: Date, timeZone: TimeZone) -> Bool {
        let calendar = Calendar.current
        let components1 = calendar.dateComponents(in: timeZone, from: date1)
        let components2 = calendar.dateComponents(in: timeZone, from: date2)
        
        return components1.year == components2.year &&
               components1.month == components2.month &&
               components1.day == components2.day
    }

    private func deg2rad(_ x: Double) -> Double { x * .pi / 180.0 }
    private func rad2deg(_ x: Double) -> Double { x * 180.0 / .pi }
    
    private func normDeg(_ x: Double) -> Double {
        var v = x.truncatingRemainder(dividingBy: 360.0)
        if v < 0 { v += 360.0 }
        return v
    }

    private func julianDate(from date: Date) -> Double {
        let timeInterval = date.timeIntervalSince1970
        return timeInterval / 86400.0 + 2440587.5
    }
}

// MARK: - Repository

public final class MoonRepository {
    private let engine: MoonEngineProtocol
    private let cache = MoonCache.shared
    
    public init(engine: MoonEngineProtocol = DefaultMoonEngine()) {
        self.engine = engine
    }
    
    public func moonData(for date: Date, coordinate: CLLocationCoordinate2D?) -> MoonPhaseResult {
        // Пробуем получить из кеша
        if let cachedResult = cache.get(for: date, coordinate: coordinate) {
            return cachedResult
        }
        
        // Если нет в кеше, вычисляем
        let result = engine.calculate(for: date, coordinate: coordinate)
        
        // Сохраняем в кеш
        cache.set(result, for: date, coordinate: coordinate)
        
        return result
    }
    
    public func clearCache() {
        cache.clear()
    }
}

// MARK: - Seeded Random Generator

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

// MARK: - Themes & Store

enum AppLanguage: String, CaseIterable {
    case ru = "ru"
    case en = "en"
}

protocol MoonTheme {
    var name: String { get }
    var backgroundColor: Color { get }
    var accentColor: Color { get }
    var textColor: Color { get }
    var moonShadow: Color { get }
    var backgroundImageName: String? { get }
    var isDark: Bool { get }
}

extension MoonTheme {
    var backgroundImageName: String? { nil }
    var isDark: Bool { false }
}

struct ClassicDarkTheme: MoonTheme {
    let name = "Classic Dark"
    let backgroundColor = Color.black
    let accentColor = Color.blue.opacity(0.9)
    let textColor = Color.white
    let moonShadow = Color.black.opacity(0.95)
    let backgroundImageName: String? = nil
    let isDark = true
}

struct OceanLightTheme: MoonTheme {
    let name = "Ocean Light"
    let backgroundColor = Color(.systemBackground)
    let accentColor = Color.cyan
    let textColor = Color.primary
    let moonShadow = Color.black.opacity(0.9)
    let backgroundImageName: String? = "ocean_light_bg"
    let isDark = false
}

struct LunarSilverTheme: MoonTheme {
    let name = "Lunar Silver"
    let backgroundColor = Color.gray.opacity(0.12)
    let accentColor = Color.purple.opacity(0.6)
    let textColor = Color.white
    let moonShadow = Color.black.opacity(0.92)
    let backgroundImageName: String? = "lunar_silver_bg"
    let isDark = true
}

struct DeepSpaceTheme: MoonTheme {
    let name = "Deep Space"
    let backgroundColor = Color(red: 0.03, green: 0.02, blue: 0.08)
    let accentColor = Color.indigo
    let textColor = Color.white
    let moonShadow = Color.black.opacity(0.97)
    let backgroundImageName: String? = nil
    let isDark = true
}

struct StarryNightTheme: MoonTheme {
    let name = "Starry Night"
    let backgroundColor = Color(red: 0.02, green: 0.02, blue: 0.06)
    let accentColor = Color(red: 0.8, green: 0.9, blue: 1.0)
    let textColor = Color.white
    let moonShadow = Color.black.opacity(0.98)
    let backgroundImageName: String? = "starry_night_bg"
    let isDark = true
}

struct CosmicPurpleTheme: MoonTheme {
    let name = "Cosmic Purple"
    let backgroundColor = Color(red: 0.08, green: 0.03, blue: 0.15)
    let accentColor = Color.purple.opacity(0.8)
    let textColor = Color.white
    let moonShadow = Color.black.opacity(0.95)
    let backgroundImageName: String? = nil
    let isDark = true
}

let availableThemes: [MoonTheme] = [
    ClassicDarkTheme(),
    OceanLightTheme(),
    LunarSilverTheme(),
    DeepSpaceTheme(),
    StarryNightTheme(),
    CosmicPurpleTheme()
]

final class MoonStore: ObservableObject {
    static let shared = MoonStore()
    private let calculationQueue = DispatchQueue(label: "moon.calculation", qos: .userInitiated)
    
    @AppStorage("appLanguage") var appLanguageRaw: String = Locale.current.languageCode ?? "en"
    @AppStorage("selectedTheme") var selectedThemeName: String = availableThemes.first?.name ?? "Classic Dark" {
        didSet {
            saveThemeToAppGroup()
            updateWidgets()
            objectWillChange.send()
        }
    }
    @AppStorage("savedLatitude") private var savedLatitude: Double = 0
    @AppStorage("savedLongitude") private var savedLongitude: Double = 0
    @AppStorage("hasSavedCoordinates") private var hasSavedCoordinates: Bool = false

    @Published var selectedDate: Date = Date() { didSet { recalc() } }
    @Published var coordinate: CLLocationCoordinate2D? = nil {
        didSet {
            saveCoordinates()
            clearCache() // Очищаем кеш при изменении координат
            recalc()
        }
    }
    @Published private(set) var result: MoonPhaseResult
    @Published var repository: MoonRepository

    private let appGroup = "group.com.yourapp.moonphase" // ЗАМЕНИТЕ НА ВАШ APP GROUP ID

    var language: AppLanguage {
        get { AppLanguage(rawValue: appLanguageRaw) ?? .en }
        set {
            appLanguageRaw = newValue.rawValue
            saveLanguageToAppGroup(newValue)
            updateWidgets() // ОБНОВЛЯЕМ ВИДЖЕТЫ
            objectWillChange.send()
        }
    }

    var currentTheme: MoonTheme {
        availableThemes.first(where: { $0.name == selectedThemeName }) ?? availableThemes[0]
    }

    private init(repository: MoonRepository = MoonRepository()) {
        self.repository = repository
        self.result = repository.moonData(for: Date(), coordinate: nil)
        restoreCoordinates()
        restoreLanguageFromAppGroup()
        restoreThemeFromAppGroup()
    }

    private func recalc() {
        calculationQueue.async { [weak self] in
            guard let self = self else { return }
            
            let newResult = self.repository.moonData(for: self.selectedDate, coordinate: self.coordinate)
            
            DispatchQueue.main.async {
                self.result = newResult
                self.publishToUserDefaults(newResult)
            }
        }
    }

    func moonData(for date: Date) -> MoonPhaseResult {
        return repository.moonData(for: date, coordinate: coordinate)
    }
    
    func clearCache() {
        repository.clearCache()
    }

    private func publishToUserDefaults(_ result: MoonPhaseResult) {
        let ud = UserDefaults.standard
        ud.set(result.illumination, forKey: "MoonPhase_illum")
        ud.set(result.phase, forKey: "MoonPhase_phase")
        ud.set(result.age, forKey: "MoonPhase_age")
    }
    
    private func saveCoordinates() {
        if let coordinate = coordinate {
            savedLatitude = coordinate.latitude
            savedLongitude = coordinate.longitude
            hasSavedCoordinates = true
        } else {
            hasSavedCoordinates = false
        }
    }
    
    private func restoreCoordinates() {
        if hasSavedCoordinates {
            coordinate = CLLocationCoordinate2D(latitude: savedLatitude, longitude: savedLongitude)
        }
    }
    
    private func saveLanguageToAppGroup(_ language: AppLanguage) {
        guard let sharedDefaults = UserDefaults(suiteName: appGroup) else { return }
        sharedDefaults.set(language.rawValue, forKey: "appLanguage")
        sharedDefaults.synchronize()
        print("Saved language to app group: \(language.rawValue)") // Для отладки
    }
    
    private func restoreLanguageFromAppGroup() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroup),
              let savedLanguage = sharedDefaults.string(forKey: "appLanguage") else {
            print("No saved language in app group") // Для отладки
            return
        }
        appLanguageRaw = savedLanguage
        print("Restored language from app group: \(savedLanguage)") // Для отладки
    }
    
    private func saveThemeToAppGroup() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroup) else { return }
        sharedDefaults.set(selectedThemeName, forKey: "selectedTheme")
        sharedDefaults.synchronize()
        print("Saved theme to app group: \(selectedThemeName)") // Для отладки
    }
    
    private func restoreThemeFromAppGroup() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroup),
              let savedTheme = sharedDefaults.string(forKey: "selectedTheme") else {
            print("No saved theme in app group") // Для отладки
            return
        }
        selectedThemeName = savedTheme
        print("Restored theme from app group: \(savedTheme)") // Для отладки
    }
    
    private func updateWidgets() {
        #if os(iOS)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

// MARK: - Location Manager

enum LocationError: LocalizedError {
    case denied, failed, timeout
    
    var errorDescription: String? {
        switch self {
        case .denied: return "Location access denied"
        case .failed: return "Failed to get location"
        case .timeout: return "Location request timed out"
        }
    }
}

final class LocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    private let manager = CLLocationManager()
    private var locationRequestContinuation: CheckedContinuation<CLLocationCoordinate2D?, Error>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() async throws -> CLLocationCoordinate2D? {
        return try await withCheckedThrowingContinuation { continuation in
            locationRequestContinuation = continuation
            
            DispatchQueue.main.async {
                switch self.manager.authorizationStatus {
                case .notDetermined:
                    self.manager.requestWhenInUseAuthorization()
                case .denied, .restricted:
                    continuation.resume(throwing: LocationError.denied)
                    return
                case .authorizedWhenInUse, .authorizedAlways:
                    self.manager.requestLocation()
                @unknown default:
                    continuation.resume(throwing: LocationError.failed)
                }
            }
            
            // Таймаут на 15 секунд
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                if let self = self, self.locationRequestContinuation != nil {
                    self.locationRequestContinuation?.resume(throwing: LocationError.timeout)
                    self.locationRequestContinuation = nil
                }
            }
        }
    }

    // Старый метод для обратной совместимости
    func requestLocation(completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        Task {
            do {
                let coordinate = try await requestLocation()
                completion(coordinate)
            } catch {
                completion(nil)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.first {
            locationRequestContinuation?.resume(returning: location.coordinate)
        } else {
            locationRequestContinuation?.resume(returning: nil)
        }
        locationRequestContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationRequestContinuation?.resume(throwing: LocationError.failed)
        locationRequestContinuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            locationRequestContinuation?.resume(throwing: LocationError.denied)
            locationRequestContinuation = nil
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }
}

// MARK: - Localization helper

struct L10n {
    private static var cachedLocalizations: [String: [AppLanguage: String]] = [
        "app_title": [.ru: "Луна", .en: "Moon"],
        "day": [.ru: "День", .en: "Day"],
        "illum": [.ru: "Освещение", .en: "Illumination"],
        "calendar": [.ru: "Календарь", .en: "Calendar"],
        "settings": [.ru: "Настройки", .en: "Settings"],
        "date": [.ru: "Дата", .en: "Date"],
        "latitude": [.ru: "Широта", .en: "Latitude"],
        "longitude": [.ru: "Долгота", .en: "Longitude"],
        "save": [.ru: "Сохранить", .en: "Save"],
        "use_device_location": [.ru: "Использовать текущее местоположение", .en: "Use device location"],
        "done": [.ru: "Готово", .en: "Done"],
        "language": [.ru: "Язык", .en: "Language"],
        "language_ru": [.ru: "Русский", .en: "Russian"],
        "language_en": [.ru: "Английский", .en: "English"],
        "reset_coords": [.ru: "Сбросить координаты", .en: "Reset coords"],
        "today": [.ru: "Сегодня", .en: "Today"],
        "open_calendar": [.ru: "Открыть календарь", .en: "Open calendar"],
        "no_location": [.ru: "Местоположение не найдено", .en: "Location not found"],
        "theme": [.ru: "Тема", .en: "Theme"],
        "distance": [.ru: "Расстояние", .en: "Distance"],
        "moonrise": [.ru: "Восход", .en: "Moonrise"],
        "moonset": [.ru: "Заход", .en: "Moonset"],
        "location_permission_denied": [.ru: "Доступ к местоположению запрещен", .en: "Location access denied"],
        "location_error": [.ru: "Ошибка получения местоположения", .en: "Location error"],
        "no_moon_today": [.ru: "Луны не видно", .en: "No moon today"]
    ]

    static func t(_ key: String, lang: AppLanguage) -> String {
        return cachedLocalizations[key]?[lang] ?? key
    }

    static func phaseName(for phase: Double, lang: AppLanguage) -> String {
        let names: [(range: ClosedRange<Double>, ru: String, en: String)] = [
            (0.0...0.03, "Новолуние", "New Moon"),
            (0.03...0.22, "Растущий серп", "Waxing Crescent"),
            (0.22...0.28, "Первая четверть", "First Quarter"),
            (0.28...0.47, "Растущая луна", "Waxing Gibbous"),
            (0.47...0.53, "Полнолуние", "Full Moon"),
            (0.53...0.72, "Убывающая луна", "Waning Gibbous"),
            (0.72...0.78, "Последняя четверть", "Last Quarter"),
            (0.78...1.0, "Убывающий серп", "Waning Crescent")
        ]
        
        let normalizedPhase = phase > 0.97 ? 0.0 : phase // Обработка перехода через новолуние
        
        for name in names {
            if name.range.contains(normalizedPhase) {
                return lang == .ru ? name.ru : name.en
            }
        }
        
        return lang == .ru ? "Новолуние" : "New Moon"
    }
}

// MARK: - Date Navigation Helper

extension Date {
    func isWithinOneYear(from referenceDate: Date) -> Bool {
        let calendar = Calendar.current
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: referenceDate)!
        let oneYearLater = calendar.date(byAdding: .year, value: 1, to: referenceDate)!
        return self >= oneYearAgo && self <= oneYearLater
    }
    
    func addingDays(_ days: Int) -> Date? {
        Calendar.current.date(byAdding: .day, value: days, to: self)
    }
}

// MARK: - Date Formatter Helper

struct TimeFormatter {
    static func timeString(from date: Date?) -> String {
        guard let date = date else {
            return "—"
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Starry Night Background View

struct StarryNightBackground: View {
    @State private var stars: [Star] = []
    
    struct Star {
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let brightness: Double
        let twinkleSpeed: Double
    }
    
    init() {
        // Создаем звезды при инициализации
        var starsArray: [Star] = []
        for _ in 0..<150 {
            starsArray.append(Star(
                x: CGFloat.random(in: 0...1),
                y: CGFloat.random(in: 0...1),
                size: CGFloat.random(in: 0.5...2.5),
                brightness: Double.random(in: 0.3...1.0),
                twinkleSpeed: Double.random(in: 1...3)
            ))
        }
        _stars = State(initialValue: starsArray)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Основной градиент ночного неба
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.02, green: 0.02, blue: 0.08),
                        Color(red: 0.05, green: 0.03, blue: 0.15),
                        Color(red: 0.08, green: 0.04, blue: 0.22)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // Создаем звезды
                ForEach(0..<stars.count, id: \.self) { index in
                    StarView(star: stars[index], geometry: geometry)
                }
                
                // Добавляем туманность
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color.purple.opacity(0.1),
                                Color.blue.opacity(0.05),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: geometry.size.width * 0.4
                        )
                    )
                    .position(x: geometry.size.width * 0.7, y: geometry.size.height * 0.3)
                    .blur(radius: 50)
                
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color.blue.opacity(0.08),
                                Color.purple.opacity(0.05),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: geometry.size.width * 0.3
                        )
                    )
                    .position(x: geometry.size.width * 0.3, y: geometry.size.height * 0.7)
                    .blur(radius: 40)
            }
        }
        .ignoresSafeArea()
    }
}

struct StarView: View {
    let star: StarryNightBackground.Star
    let geometry: GeometryProxy
    @State private var opacity: Double = 1.0
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        Circle()
            .fill(Color.white)
            .frame(width: star.size, height: star.size)
            .position(
                x: geometry.size.width * star.x,
                y: geometry.size.height * star.y
            )
            .opacity(opacity * star.brightness)
            .scaleEffect(scale)
            .onAppear {
                // Анимация мерцания звезд
                withAnimation(Animation.easeInOut(duration: star.twinkleSpeed).repeatForever(autoreverses: true)) {
                    opacity = Double.random(in: 0.3...0.8)
                    scale = CGFloat.random(in: 0.8...1.2)
                }
            }
    }
}

// MARK: - Ocean Light Background View

struct OceanLightBackground: View {
    @State private var waveOffset: CGFloat = 0
    @State private var cloudOffset: CGFloat = 0
    @State private var sunRotation: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Основной градиент неба
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.7, green: 0.9, blue: 1.0),
                        Color(red: 0.8, green: 0.95, blue: 1.0),
                        Color(red: 0.9, green: 0.98, blue: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // Солнце
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color.yellow.opacity(0.8),
                                Color.orange.opacity(0.4),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 120, height: 120)
                    .position(x: geometry.size.width * 0.8, y: geometry.size.height * 0.2)
                    .rotationEffect(.degrees(sunRotation))
                
                // Облака
                ForEach(0..<4, id: \.self) { index in
                    CloudView()
                        .position(
                            x: geometry.size.width * CGFloat.random(in: 0.1...0.9) + cloudOffset,
                            y: geometry.size.height * CGFloat(0.15 + Double(index) * 0.1)
                        )
                        .opacity(0.6 - Double(index) * 0.1)
                }
                
                // Океан
                VStack {
                    Spacer()
                    
                    ZStack {
                        // Глубокий океан
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.1, green: 0.4, blue: 0.7),
                                Color(red: 0.2, green: 0.5, blue: 0.8),
                                Color(red: 0.3, green: 0.6, blue: 0.9)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        
                        // Волны
                        ForEach(0..<3, id: \.self) { index in
                            WaveView(offset: waveOffset + CGFloat(index) * 50, speed: Double(index + 1) * 0.5)
                                .opacity(0.3 + Double(index) * 0.2)
                        }
                        
                        // Блики на воде
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.1),
                                Color.clear
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .frame(height: geometry.size.height * 0.4)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(Animation.linear(duration: 8).repeatForever(autoreverses: false)) {
                waveOffset = 360
            }
            
            withAnimation(Animation.linear(duration: 20).repeatForever(autoreverses: false)) {
                cloudOffset = -400
            }
            
            withAnimation(Animation.linear(duration: 30).repeatForever(autoreverses: false)) {
                sunRotation = 360
            }
        }
    }
}

struct CloudView: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 60, height: 40)
                .offset(x: -20, y: 0)
            
            Circle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 70, height: 50)
                .offset(x: 0, y: -10)
            
            Circle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 60, height: 40)
                .offset(x: 20, y: 0)
        }
        .frame(width: 120, height: 60)
        .blur(radius: 5)
    }
}

struct WaveView: View {
    var offset: CGFloat
    var speed: Double
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                let midHeight = height * 0.5
                
                path.move(to: CGPoint(x: 0, y: midHeight))
                
                for x in stride(from: 0, through: width, by: 1) {
                    let relativeX = x / width
                    let y = sin((relativeX * 4 * .pi) + offset * .pi / 180) * 10 + midHeight
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                
                path.addLine(to: CGPoint(x: width, y: height))
                path.addLine(to: CGPoint(x: 0, y: height))
                path.closeSubpath()
            }
            .fill(Color.white.opacity(0.3))
        }
    }
}

// MARK: - Lunar Silver Background View

struct LunarSilverBackground: View {
    @State private var shimmerOffset: CGFloat = 0
    @State private var particleRotation: Double = 0
    @State private var glowIntensity: Double = 0.3
    @State private var floatingOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Основной градиент серебристой темы
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.15, green: 0.15, blue: 0.25),
                        Color(red: 0.25, green: 0.25, blue: 0.35),
                        Color(red: 0.35, green: 0.35, blue: 0.45)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Блестящие частицы
                ForEach(0..<80, id: \.self) { index in
                    SilverParticle(index: index, geometry: geometry)
                }
                
                // Переливающийся слой
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.05),
                                Color.white.opacity(0.02),
                                Color.clear
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .offset(x: shimmerOffset)
                    .blur(radius: 20)
                
                // Серебристые волны
                ForEach(0..<3, id: \.self) { index in
                    SilverWave(index: index, offset: shimmerOffset + CGFloat(index) * 100)
                        .opacity(0.1 + Double(index) * 0.05)
                }
                
                // Светящиеся сферы
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color.purple.opacity(0.1),
                                Color.blue.opacity(0.05),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: geometry.size.width * 0.3
                        )
                    )
                    .frame(width: geometry.size.width * 0.6)
                    .position(x: geometry.size.width * 0.3, y: geometry.size.height * 0.2)
                    .blur(radius: 40)
                    .offset(floatingOffset)
                
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color.blue.opacity(0.08),
                                Color.purple.opacity(0.05),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: geometry.size.width * 0.2
                        )
                    )
                    .frame(width: geometry.size.width * 0.4)
                    .position(x: geometry.size.width * 0.7, y: geometry.size.height * 0.8)
                    .blur(radius: 30)
                    .offset(floatingOffset)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            // Анимация перелива
            withAnimation(Animation.linear(duration: 8).repeatForever(autoreverses: false)) {
                shimmerOffset = 200
            }
            
            // Анимация вращения частиц
            withAnimation(Animation.linear(duration: 15).repeatForever(autoreverses: false)) {
                particleRotation = 360
            }
            
            // Анимация пульсации свечения
            withAnimation(Animation.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                glowIntensity = 0.6
            }
            
            // Плавающая анимация
            withAnimation(Animation.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                floatingOffset = CGSize(width: 10, height: 10)
            }
        }
    }
}

struct SilverParticle: View {
    let index: Int
    let geometry: GeometryProxy
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.0
    
    var body: some View {
        let x = CGFloat.random(in: 0...geometry.size.width)
        let y = CGFloat.random(in: 0...geometry.size.height)
        let size = CGFloat.random(in: 1...3)
        let delay = Double.random(in: 0...2)
        
        Circle()
            .fill(Color.white)
            .frame(width: size, height: size)
            .position(x: x, y: y)
            .rotationEffect(.degrees(rotation))
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                // Задержка перед появлением
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                        opacity = Double.random(in: 0.3...0.8)
                        scale = CGFloat.random(in: 0.8...1.5)
                    }
                    
                    withAnimation(Animation.linear(duration: Double.random(in: 5...10)).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
            }
    }
}

struct SilverWave: View {
    let index: Int
    let offset: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                let midHeight = height * 0.5
                
                path.move(to: CGPoint(x: 0, y: midHeight))
                
                for x in stride(from: 0, through: width, by: 1) {
                    let relativeX = x / width
                    let y = sin((relativeX * 6 * .pi) + offset * .pi / 180) * 15 + midHeight
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                
                path.addLine(to: CGPoint(x: width, y: height))
                path.addLine(to: CGPoint(x: 0, y: height))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.1),
                        Color.white.opacity(0.05),
                        Color.clear
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

// MARK: - Cosmic Purple Background View

struct CosmicPurpleBackground: View {
    @State private var cometOffset: CGFloat = -200
    @State private var planetRotation: Double = 0
    @State private var nebulaPulse: Double = 0.3
    @State private var starTwinkle: Double = 1.0
    @State private var particleRotation: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Основной градиент космического пурпура
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.08, green: 0.03, blue: 0.15),
                        Color(red: 0.12, green: 0.05, blue: 0.22),
                        Color(red: 0.15, green: 0.07, blue: 0.28)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // Дальние звезды
                ForEach(0..<200, id: \.self) { index in
                    DistantStar(index: index, geometry: geometry)
                }
                
                // Туманности
                NebulaView()
                    .position(x: geometry.size.width * 0.3, y: geometry.size.height * 0.2)
                    .scaleEffect(1.0 + nebulaPulse * 0.2)
                    .opacity(0.4)
                
                NebulaView()
                    .position(x: geometry.size.width * 0.7, y: geometry.size.height * 0.7)
                    .scaleEffect(1.0 + nebulaPulse * 0.1)
                    .opacity(0.3)
                    .rotationEffect(.degrees(45))
                
                // Планеты в далеке
                DistantPlanet()
                    .position(x: geometry.size.width * 0.2, y: geometry.size.height * 0.8)
                    .rotationEffect(.degrees(planetRotation))
                
                DistantPlanet()
                    .position(x: geometry.size.width * 0.85, y: geometry.size.height * 0.3)
                    .rotationEffect(.degrees(planetRotation * 0.7))
                    .scaleEffect(0.8)
                
                // Анимированная комета
                CometView()
                    .offset(x: cometOffset, y: geometry.size.height * 0.3)
                    .rotationEffect(.degrees(-15))
                
                // Космические частицы
                ForEach(0..<50, id: \.self) { index in
                    SpaceParticle(index: index, geometry: geometry)
                }
                
                // Светящиеся элементы
                GlowingOrbs(geometry: geometry)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            // Анимация кометы
            withAnimation(Animation.linear(duration: 12).repeatForever(autoreverses: false)) {
                cometOffset = geometryWidth * 1.5
            }
            
            // Анимация вращения планет
            withAnimation(Animation.linear(duration: 40).repeatForever(autoreverses: false)) {
                planetRotation = 360
            }
            
            // Анимация пульсации туманности
            withAnimation(Animation.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                nebulaPulse = 0.8
            }
            
            // Анимация мерцания звезд
            withAnimation(Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                starTwinkle = 0.5
            }
            
            // Анимация вращения частиц
            withAnimation(Animation.linear(duration: 20).repeatForever(autoreverses: false)) {
                particleRotation = 360
            }
        }
    }
    
    private var geometryWidth: CGFloat {
        #if os(iOS)
        return UIScreen.main.bounds.width
        #else
        return 800
        #endif
    }
}

struct DistantStar: View {
    let index: Int
    let geometry: GeometryProxy
    @State private var opacity: Double = 1.0
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        let x = CGFloat.random(in: 0...geometry.size.width)
        let y = CGFloat.random(in: 0...geometry.size.height)
        let size = CGFloat.random(in: 0.5...1.5)
        let brightness = Double.random(in: 0.2...0.8)
        let twinkleSpeed = Double.random(in: 2...5)
        
        Circle()
            .fill(Color.white)
            .frame(width: size, height: size)
            .position(x: x, y: y)
            .opacity(opacity * brightness)
            .scaleEffect(scale)
            .onAppear {
                // Случайная задержка для мерцания
                let delay = Double.random(in: 0...twinkleSpeed)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(Animation.easeInOut(duration: twinkleSpeed).repeatForever(autoreverses: true)) {
                        opacity = Double.random(in: 0.3...0.9)
                        scale = CGFloat.random(in: 0.8...1.2)
                    }
                }
            }
    }
}

struct NebulaView: View {
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.purple.opacity(0.3),
                            Color.blue.opacity(0.2),
                            Color.indigo.opacity(0.1),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 100
                    )
                )
                .frame(width: 200, height: 200)
                .blur(radius: 30)
            
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.pink.opacity(0.2),
                            Color.purple.opacity(0.15),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)
                .blur(radius: 20)
                .rotationEffect(.degrees(rotation))
        }
        .onAppear {
            withAnimation(Animation.linear(duration: 25).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

struct DistantPlanet: View {
    @State private var glowIntensity: Double = 0.3
    
    var body: some View {
        ZStack {
            // Планета
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.4, green: 0.2, blue: 0.6),
                            Color(red: 0.3, green: 0.1, blue: 0.5),
                            Color(red: 0.2, green: 0.05, blue: 0.4)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 25
                    )
                )
                .frame(width: 50, height: 50)
                .overlay(
                    Circle()
                        .stroke(Color.purple.opacity(0.5), lineWidth: 2)
                        .blur(radius: 2)
                )
            
            // Атмосфера/кольца
            Circle()
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.purple.opacity(0.4),
                            Color.blue.opacity(0.3),
                            Color.clear
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 3
                )
                .frame(width: 70, height: 70)
                .blur(radius: 1)
            
            // Свечение
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.purple.opacity(0.2),
                            Color.blue.opacity(0.1),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 40
                    )
                )
                .frame(width: 80, height: 80)
                .blur(radius: 10)
                .scaleEffect(1.0 + glowIntensity * 0.3)
        }
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                glowIntensity = 0.6
            }
        }
    }
}

struct CometView: View {
    @State private var tailLength: CGFloat = 1.0
    @State private var glowIntensity: Double = 0.5
    
    var body: some View {
        ZStack {
            // Хвост кометы
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: -80, y: 0))
            }
            .stroke(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.8),
                        Color.blue.opacity(0.6),
                        Color.purple.opacity(0.4),
                        Color.clear
                    ]),
                    startPoint: .trailing,
                    endPoint: .leading
                ),
                lineWidth: 3
            )
            .scaleEffect(x: tailLength, y: 1.0)
            .blur(radius: 2)
            
            // Ядро кометы
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white,
                            Color.blue.opacity(0.8),
                            Color.purple.opacity(0.6)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 8
                    )
                )
                .frame(width: 16, height: 16)
                .shadow(color: .blue.opacity(0.5), radius: 10, x: 0, y: 0)
                .scaleEffect(1.0 + glowIntensity * 0.3)
            
            // Свечение вокруг кометы
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.blue.opacity(0.3),
                            Color.purple.opacity(0.2),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 20
                    )
                )
                .frame(width: 40, height: 40)
                .blur(radius: 5)
        }
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                tailLength = 1.5
                glowIntensity = 0.8
            }
        }
    }
}

struct SpaceParticle: View {
    let index: Int
    let geometry: GeometryProxy
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.0
    
    var body: some View {
        let x = CGFloat.random(in: 0...geometry.size.width)
        let y = CGFloat.random(in: 0...geometry.size.height)
        let size = CGFloat.random(in: 0.3...1.0)
        let delay = Double.random(in: 0...3)
        
        Circle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.purple.opacity(0.8),
                        Color.blue.opacity(0.6)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .position(x: x, y: y)
            .rotationEffect(.degrees(rotation))
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                        opacity = Double.random(in: 0.2...0.6)
                        scale = CGFloat.random(in: 0.8...1.5)
                    }
                    
                    withAnimation(Animation.linear(duration: Double.random(in: 10...20)).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
            }
    }
}

struct GlowingOrbs: View {
    let geometry: GeometryProxy
    @State private var pulse: Double = 0.3
    
    var body: some View {
        ZStack {
            // Большие светящиеся сферы
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.purple.opacity(0.15),
                            Color.blue.opacity(0.1),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: geometry.size.width * 0.2
                    )
                )
                .frame(width: geometry.size.width * 0.4)
                .position(x: geometry.size.width * 0.2, y: geometry.size.height * 0.2)
                .blur(radius: 30)
                .scaleEffect(1.0 + pulse * 0.2)
            
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.blue.opacity(0.1),
                            Color.purple.opacity(0.08),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: geometry.size.width * 0.15
                    )
                )
                .frame(width: geometry.size.width * 0.3)
                .position(x: geometry.size.width * 0.8, y: geometry.size.height * 0.7)
                .blur(radius: 25)
                .scaleEffect(1.0 + pulse * 0.15)
        }
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                pulse = 0.7
            }
        }
    }
}

// MARK: - Улучшенная маска Луны с мягкими тенями

struct EnhancedRectangleMoonMask: View {
    var phase: Double
    var theme: MoonTheme
    
    private var visiblePercentage: CGFloat {
        if phase <= 0.5 {
            return CGFloat(phase / 0.5)
        } else {
            return CGFloat(1.0 - (phase - 0.5) / 0.5)
        }
    }
    
    private var shadowIntensity: Double {
        // Более мягкая тень с градиентом
        return 0.85
    }
    
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let maskWidth = size * 1.0
            
            ZStack {
                // Основная прямоугольная маска с мягкими краями
                HStack(spacing: 0) {
                    if phase <= 0.5 {
                        // Растущая луна
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        theme.moonShadow.opacity(shadowIntensity),
                                        theme.moonShadow.opacity(shadowIntensity * 0.7),
                                        theme.moonShadow.opacity(shadowIntensity * 0.3)
                                    ]),
                                    startPoint: .trailing,
                                    endPoint: .leading
                                )
                            )
                            .frame(width: maskWidth * (1.0 - visiblePercentage), height: size)
                        
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: maskWidth * visiblePercentage, height: size)
                    } else {
                        // Убывающая луна
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: maskWidth * visiblePercentage, height: size)
                        
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        theme.moonShadow.opacity(shadowIntensity * 0.3),
                                        theme.moonShadow.opacity(shadowIntensity * 0.7),
                                        theme.moonShadow.opacity(shadowIntensity)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: maskWidth * (1.0 - visiblePercentage), height: size)
                    }
                }
                .frame(width: maskWidth, height: size)
                
                // Добавляем мягкое свечение на границе тени
                if !isFullMoon && !isNewMoon {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.1),
                                    Color.blue.opacity(0.05),
                                    Color.clear
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: maskWidth, height: size)
                        .blur(radius: 1)
                }
            }
            .frame(width: maskWidth, height: size)
        }
    }
    
    private var isFullMoon: Bool {
        phase >= 0.47 && phase <= 0.53
    }
    
    private var isNewMoon: Bool {
        phase <= 0.03 || phase >= 0.97
    }
}

// MARK: - Улучшенный слой кратеров с мягкими тенями

struct EnhancedCraterLayer: View {
    let seed: Int
    let phase: Double
    let size: CGFloat

    var body: some View {
        Canvas { context, _ in
            var rng = SeededGenerator(seed: UInt64(seed))
            
            let baseCount = Int(max(8, (size / 20)))
            let craterCount = baseCount * 2
            
            for _ in 0..<craterCount {
                let angle = Double.random(in: 0...(2.0 * .pi), using: &rng)
                let distance = Double.random(in: 0...0.8, using: &rng)
                
                let visible = isCraterVisible(angle: angle, phase: phase)
                if !visible { continue }
                
                let x = size * 0.5 + CGFloat(cos(angle)) * size * 0.5 * distance
                let y = size * 0.5 + CGFloat(sin(angle)) * size * 0.5 * distance
                
                let craterSize = CGFloat.random(in: max(1, size*0.005)...max(3, size*0.02), using: &rng)
                let intensity = craterIntensity(at: CGPoint(x: x, y: y), phase: phase)
                
                // Мягкие тени для кратеров
                let shadowOpacity = 0.12 * intensity
                let highlightOpacity = 0.08 * intensity
                
                // Тень кратера
                let shadowRect = CGRect(x: x - craterSize/2, y: y - craterSize/2,
                                      width: craterSize, height: craterSize)
                context.fill(Path(ellipseIn: shadowRect),
                           with: .color(Color.black.opacity(shadowOpacity)))
                
                // Световой блик на кратере
                let highlightSize = craterSize * 0.4
                let highlightRect = CGRect(x: x - craterSize/4 - highlightSize/2,
                                         y: y - craterSize/4 - highlightSize/2,
                                         width: highlightSize, height: highlightSize)
                context.fill(Path(ellipseIn: highlightRect),
                           with: .color(Color.white.opacity(highlightOpacity)))
            }
        }
    }
    
    private func isCraterVisible(angle: Double, phase: Double) -> Bool {
        let terminatorAngle = phase * 2.0 * .pi
        if phase <= 0.5 {
            return angle >= (terminatorAngle - .pi) && angle <= terminatorAngle
        } else {
            return angle <= (terminatorAngle - .pi) || angle >= terminatorAngle
        }
    }
    
    private func craterIntensity(at point: CGPoint, phase: Double) -> Double {
        let center = CGPoint(x: size * 0.5, y: size * 0.5)
        let terminatorX = center.x + (CGFloat(phase) * 2.0 - 1.0) * size * 0.5 * 0.9
        let distanceToTerminator = abs(point.x - terminatorX)
        
        return min(1.0, distanceToTerminator / (size * 0.3))
    }
}

// MARK: - Улучшенное основное вью Луны

struct BeautifulMoonView: View {
    var phase: Double
    @EnvironmentObject private var store: MoonStore
    
    private var moonGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(white: 0.98),
                Color(white: 0.92),
                Color(white: 0.85),
                Color(white: 0.78)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var isFullMoon: Bool {
        phase >= 0.47 && phase <= 0.53
    }
    
    private var isNewMoon: Bool {
        phase <= 0.03 || phase >= 0.97
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            
            ZStack {
                // 1. Основной диск с улучшенным градиентом
                Circle()
                    .fill(moonGradient)
                    .frame(width: size, height: size)
                    .shadow(
                        color: Color.black.opacity(0.6),
                        radius: size * 0.04,
                        x: 3,
                        y: 6
                    )
                    .shadow(
                        color: store.currentTheme.accentColor.opacity(0.3),
                        radius: size * 0.03,
                        x: -2,
                        y: -2
                    )
                
                // 2. Внутреннее свечение
                Circle()
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.1),
                                Color.clear
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: size * 0.015
                    )
                    .frame(width: size, height: size)
                
                // 3. Текстура поверхности
                baseTextureView(size: size)
                
                // 4. Улучшенный слой кратеров
                EnhancedCraterLayer(seed: 42, phase: phase, size: size)
                    .blendMode(.multiply)
                
                // 5. Улучшенная маска с мягкими тенями
                if !isFullMoon && !isNewMoon {
                    EnhancedRectangleMoonMask(phase: phase, theme: store.currentTheme)
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } else if isNewMoon {
                    // В новолуние - мягкая тень
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    store.currentTheme.moonShadow.opacity(0.9),
                                    store.currentTheme.moonShadow.opacity(0.7),
                                    store.currentTheme.moonShadow.opacity(0.5)
                                ]),
                                startPoint: .center,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: size, height: size)
                }
                
                // 6. Внешнее свечение
                Circle()
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.2),
                                Color.blue.opacity(0.1),
                                Color.purple.opacity(0.05),
                                Color.clear
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: size * 0.005
                    )
                    .frame(width: size * 1.05, height: size * 1.05)
                    .blur(radius: 1)
            }
            .frame(width: size, height: size)
        }
    }
    
    @ViewBuilder
    private func baseTextureView(size: CGFloat) -> some View {
        if UIImage(named: "moon_texture") != nil {
            Image("moon_texture")
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.05),
                                    Color.clear
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: size * 0.008
                        )
                        .blendMode(.overlay)
                )
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.1), lineWidth: size * 0.003)
                        .blur(radius: 1)
                        .offset(x: 1, y: 1)
                        .blendMode(.multiply)
                )
        } else {
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [
                        Color(white: 0.96),
                        Color(white: 0.89),
                        Color(white: 0.82),
                        Color(white: 0.76)
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.5
                ))
                .overlay(
                    MoonNoiseTexture(seed: 123, intensity: 0.08)
                        .frame(width: size, height: size)
                        .blendMode(.multiply)
                        .opacity(0.4)
                )
        }
    }
}

// Текстура шума для fallback
struct MoonNoiseTexture: View {
    let seed: Int
    let intensity: Double
    
    var body: some View {
        GeometryReader { geo in
            let size = max(geo.size.width, geo.size.height)
            Canvas { context, _ in
                var rng = SeededGenerator(seed: UInt64(seed))
                let pointCount = Int(size * 0.5)
                
                for _ in 0..<pointCount {
                    let x = CGFloat.random(in: 0...size, using: &rng)
                    let y = CGFloat.random(in: 0...size, using: &rng)
                    let alpha = CGFloat.random(in: 0.02...0.08, using: &rng) * intensity
                    
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)),
                        with: .color(Color.black.opacity(alpha))
                    )
                }
            }
        }
    }
}

// MARK: - Enhanced Realistic Moon View with Beautiful Effects

struct GorgeousRealisticMoonView: View {
    var phase: Double
    @EnvironmentObject private var store: MoonStore
    
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var floatingOffset: CGSize = .zero
    @State private var horizontalRotation: Double = 0
    @State private var glowIntensity: Double = 0.4
    @State private var pulseScale: CGFloat = 1.0
    @State private var forwardBackOffset: CGFloat = 0
    @State private var ambientGlowRotation: Double = 0
    @State private var particleScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                // Улучшенное космическое свечение
                CosmicGlowEffect(phase: phase)
                    .frame(width: 320, height: 320)
                    .scaleEffect(1.0 + glowIntensity * 0.15)
                    .opacity(glowIntensity)
                    .rotationEffect(.degrees(ambientGlowRotation))
                
                // Основная луна с эффектами
                ZStack {
                    // Внешнее сияние
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    store.currentTheme.accentColor.opacity(0.3),
                                    store.currentTheme.accentColor.opacity(0.15),
                                    store.currentTheme.accentColor.opacity(0.05),
                                    Color.clear
                                ]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 140
                            )
                        )
                        .frame(width: 280, height: 280)
                        .blur(radius: 25)
                        .scaleEffect(particleScale)
                    
                    // Красивая луна
                    BeautifulMoonView(phase: phase)
                        .frame(width: 223, height: 223)
                        .rotation3DEffect(
                            Angle(degrees: horizontalRotation),
                            axis: (x: 0, y: 1, z: 0)
                        )
                        .scaleEffect(pulseScale)
                        .offset(x: dragOffset + floatingOffset.width + forwardBackOffset,
                               y: floatingOffset.height)
                        .shadow(
                            color: store.currentTheme.accentColor.opacity(0.4),
                            radius: 25,
                            x: 0,
                            y: 0
                        )
                        .shadow(
                            color: Color.black.opacity(0.5),
                            radius: 15,
                            x: 8,
                            y: 12
                        )
                        .gesture(dragGesture)
                    
                    // Индикаторы навигации с улучшенным дизайном
                    navigationIndicators
                }
                .frame(width: 223, height: 223)
                .onAppear {
                    startBeautifulAnimations()
                }
            }
            .frame(width: 223, height: 223)

            // Навигационные кнопки с улучшенным дизайном
            navigationButtons
            
            // ИНДИКАТОР ФАЗЫ С УМЕНЬШЕННОЙ ПОЛОСКОЙ ВДВОЕ
            phaseIndicator
        }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isDragging = true
                dragOffset = value.translation.width
                withAnimation(.spring(response: 0.3)) {
                    glowIntensity = 0.7
                    pulseScale = 1.06
                    particleScale = 1.1
                }
            }
            .onEnded { value in
                isDragging = false
                let threshold: CGFloat = 50
                
                if value.translation.width < -threshold {
                    navigateToNextDay()
                } else if value.translation.width > threshold {
                    navigateToPreviousDay()
                }
                
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    dragOffset = 0
                    glowIntensity = 0.4
                    pulseScale = 1.0
                    particleScale = 1.0
                }
            }
    }
    
    private var navigationIndicators: some View {
        HStack {
            Image(systemName: "chevron.left.circle.fill")
                .font(.title2)
                .foregroundColor(.white.opacity(0.8))
                .padding(8)
                .background(Circle().fill(Color.black.opacity(0.4)))
                .shadow(color: .black.opacity(0.3), radius: 3, x: 2, y: 2)
                .opacity(isDragging && dragOffset < 0 ? 1 : 0)
                .scaleEffect(isDragging && dragOffset < 0 ? 1.2 : 1.0)
            
            Spacer()
            
            Image(systemName: "chevron.right.circle.fill")
                .font(.title2)
                .foregroundColor(.white.opacity(0.8))
                .padding(8)
                .background(Circle().fill(Color.black.opacity(0.4)))
                .shadow(color: .black.opacity(0.3), radius: 3, x: 2, y: 2)
                .opacity(isDragging && dragOffset > 0 ? 1 : 0)
                .scaleEffect(isDragging && dragOffset > 0 ? 1.2 : 1.0)
        }
        .padding(.horizontal, 30)
    }
    
    private var navigationButtons: some View {
        HStack(spacing: 24) {
            Button(action: navigateToPreviousDay) {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(14)
                    .background(Circle().fill(Color.white.opacity(0.25)))
                    .shadow(color: .black.opacity(0.3), radius: 5, x: 2, y: 2)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!canNavigateToPreviousDay())
            .accessibilityLabel("Previous day")
            
            Spacer()
                .frame(width: 70)
            
            Button(action: navigateToNextDay) {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(14)
                    .background(Circle().fill(Color.white.opacity(0.25)))
                    .shadow(color: .black.opacity(0.3), radius: 5, x: 2, y: 2)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!canNavigateToNextDay())
            .accessibilityLabel("Next day")
        }
        .padding(.horizontal, 30)
    }
    
    private var phaseIndicator: some View {
        let (label, percent) = waxingWaningPercent(phase: phase, lang: store.language)
        
        return VStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
                .padding(.top, 4)
            
            // УМЕНЬШЕННЫЙ ПРОГРЕСС-БАР ВДВОЕ
            ZStack(alignment: .leading) {
                // Фон прогресс-бара
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 4) // Уменьшено с 8 до 4
                
                // Заполнение
                Capsule()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                store.currentTheme.accentColor.opacity(0.8),
                                store.currentTheme.accentColor.opacity(0.6)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: CGFloat(percent) * 1.2, height: 4) // Уменьшено с 2.4 до 1.2
                    .shadow(color: store.currentTheme.accentColor.opacity(0.5), radius: 2, x: 0, y: 0)
                
                // Светящаяся точка на конце
                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8) // Уменьшено с 12 до 8
                    .offset(x: CGFloat(percent) * 1.2 - 4) // Уменьшено с 2.4 до 1.2 и с 6 до 4
                    .shadow(color: store.currentTheme.accentColor, radius: 3, x: 0, y: 0) // Уменьшено с 4 до 3
            }
            .frame(width: 120) // Уменьшено с 240 до 120
            
            Text(String(format: "%.0f%%", percent))
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
                .padding(.bottom, 4)
        }
    }
    
    private func startBeautifulAnimations() {
        // Плавающая анимация
        withAnimation(Animation.easeInOut(duration: 4.2).repeatForever(autoreverses: true)) {
            floatingOffset = CGSize(width: 0, height: -10)
        }
        
        // Пульсация
        withAnimation(Animation.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
            pulseScale = 1.03
        }
        
        // Вращение
        withAnimation(Animation.easeInOut(duration: 8.0).repeatForever(autoreverses: true)) {
            horizontalRotation = 4
        }
        
        // Движение вперед-назад
        withAnimation(Animation.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
            forwardBackOffset = 3
        }
        
        // Вращение свечения
        withAnimation(Animation.linear(duration: 20).repeatForever(autoreverses: false)) {
            ambientGlowRotation = 360
        }
        
        // Пульсация частиц
        withAnimation(Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            particleScale = 1.05
        }
    }
    
    private func navigateToPreviousDay() {
        guard let previousDate = Calendar.current.date(byAdding: .day, value: -1, to: store.selectedDate),
              previousDate.isWithinOneYear(from: Date()) else { return }
        
        withAnimation(.easeInOut(duration: 0.4)) {
            store.selectedDate = previousDate
        }
    }
    
    private func navigateToNextDay() {
        guard let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: store.selectedDate),
              nextDate.isWithinOneYear(from: Date()) else { return }
        
        withAnimation(.easeInOut(duration: 0.4)) {
            store.selectedDate = nextDate
        }
    }
    
    private func canNavigateToPreviousDay() -> Bool {
        guard let previousDate = Calendar.current.date(byAdding: .day, value: -1, to: store.selectedDate) else { return false }
        return previousDate.isWithinOneYear(from: Date())
    }
    
    private func canNavigateToNextDay() -> Bool {
        guard let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: store.selectedDate) else { return false }
        return nextDate.isWithinOneYear(from: Date())
    }
}

// Эффект космического свечения
struct CosmicGlowEffect: View {
    var phase: Double
    @State private var glowPhase: Double = 0

    var body: some View {
        ZStack {
            // Основное свечение
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: glowColors),
                        center: .center,
                        startRadius: 0,
                        endRadius: 160
                    )
                )
                .blur(radius: 30)
            
            // Дополнительные слои свечения
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: glowColors),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 200 + CGFloat(index) * 40, height: 200 + CGFloat(index) * 40)
                    .blur(radius: 5 + Double(index) * 3)
                    .opacity(0.3 - Double(index) * 0.1)
            }
        }
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                glowPhase = 1.0
            }
        }
    }
    
    private var glowColors: [Color] {
        [
            Color.blue.opacity(0.4),
            Color.purple.opacity(0.3),
            Color.indigo.opacity(0.2),
            Color.clear
        ]
    }
}

// MARK: - Enhanced Simple Moon View for Calendar
struct BeautifulSimpleMoonView: View {
    var phase: Double
    @EnvironmentObject private var store: MoonStore
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(white: 0.95),
                            Color(white: 0.85),
                            Color(white: 0.75)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 31, height: 31)
                .shadow(
                    color: Color.black.opacity(0.3),
                    radius: 2,
                    x: 1,
                    y: 2
                )
                .shadow(
                    color: store.currentTheme.accentColor.opacity(0.2),
                    radius: 1,
                    x: -1,
                    y: -1
                )
            
            // Упрощенная маска для маленького размера
            if !isFullMoon && !isNewMoon {
                HStack(spacing: 0) {
                    if phase <= 0.5 {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.black.opacity(0.8),
                                        Color.black.opacity(0.4)
                                    ]),
                                    startPoint: .trailing,
                                    endPoint: .leading
                                )
                            )
                            .frame(width: 31 * CGFloat(1.0 - visiblePercentage), height: 31)
                        
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 31 * visiblePercentage, height: 31)
                    } else {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 31 * visiblePercentage, height: 31)
                        
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.black.opacity(0.4),
                                        Color.black.opacity(0.8)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 31 * CGFloat(1.0 - visiblePercentage), height: 31)
                    }
                }
                .frame(width: 31, height: 31)
                .clipShape(Circle())
            } else if isNewMoon {
                Circle()
                    .fill(Color.black.opacity(0.7))
                    .frame(width: 31, height: 31)
            }
            
            // Легкая текстура
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                .frame(width: 31, height: 31)
        }
    }
    
    private var visiblePercentage: CGFloat {
        if phase <= 0.5 {
            return CGFloat(phase / 0.5)
        } else {
            return CGFloat(1.0 - (phase - 0.5) / 0.5)
        }
    }
    
    private var isFullMoon: Bool {
        phase >= 0.47 && phase <= 0.53
    }
    
    private var isNewMoon: Bool {
        phase <= 0.03 || phase >= 0.97
    }
}

// MARK: - Realistic Moon View для календаря
struct CalendarRealisticMoonView: View {
    var phase: Double
    @EnvironmentObject private var store: MoonStore
    
    private var moonGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(white: 0.98),
                Color(white: 0.92),
                Color(white: 0.85),
                Color(white: 0.78)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var isFullMoon: Bool {
        phase >= 0.47 && phase <= 0.53
    }
    
    private var isNewMoon: Bool {
        phase <= 0.03 || phase >= 0.97
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            
            ZStack {
                // 1. Основной диск с улучшенным градиентом
                Circle()
                    .fill(moonGradient)
                    .frame(width: size, height: size)
                    .shadow(
                        color: Color.black.opacity(0.3),
                        radius: size * 0.02,
                        x: 1,
                        y: 2
                    )
                
                // 2. Текстура поверхности
                baseTextureView(size: size)
                
                // 3. Упрощенный слой кратеров для маленького размера
                SimpleCraterLayer(seed: 42, phase: phase, size: size)
                    .blendMode(.multiply)
                
                // 4. Упрощенная маска с мягкими тенями
                if !isFullMoon && !isNewMoon {
                    SimpleRectangleMoonMask(phase: phase, theme: store.currentTheme)
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } else if isNewMoon {
                    // В новолуние - мягкая тень
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    store.currentTheme.moonShadow.opacity(0.9),
                                    store.currentTheme.moonShadow.opacity(0.7),
                                    store.currentTheme.moonShadow.opacity(0.5)
                                ]),
                                startPoint: .center,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: size, height: size)
                }
            }
            .frame(width: size, height: size)
        }
    }
    
    @ViewBuilder
    private func baseTextureView(size: CGFloat) -> some View {
        if UIImage(named: "moon_texture") != nil {
            Image("moon_texture")
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: size * 0.003)
                        .blendMode(.overlay)
                )
        } else {
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [
                        Color(white: 0.96),
                        Color(white: 0.89),
                        Color(white: 0.82)
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.5
                ))
                .overlay(
                    SimpleMoonNoiseTexture(seed: 123, intensity: 0.06)
                        .frame(width: size, height: size)
                        .blendMode(.multiply)
                        .opacity(0.3)
                )
        }
    }
}

// Упрощенный слой кратеров для маленького размера
struct SimpleCraterLayer: View {
    let seed: Int
    let phase: Double
    let size: CGFloat

    var body: some View {
        Canvas { context, _ in
            var rng = SeededGenerator(seed: UInt64(seed))
            
            let craterCount = Int(max(4, (size / 25)))
            
            for _ in 0..<craterCount {
                let angle = Double.random(in: 0...(2.0 * .pi), using: &rng)
                let distance = Double.random(in: 0...0.7, using: &rng)
                
                let visible = isCraterVisible(angle: angle, phase: phase)
                if !visible { continue }
                
                let x = size * 0.5 + CGFloat(cos(angle)) * size * 0.5 * distance
                let y = size * 0.5 + CGFloat(sin(angle)) * size * 0.5 * distance
                
                let craterSize = CGFloat.random(in: max(0.5, size*0.008)...max(1.5, size*0.015), using: &rng)
                let intensity = craterIntensity(at: CGPoint(x: x, y: y), phase: phase)
                
                // Упрощенные тени для кратеров
                let shadowOpacity = 0.15 * intensity
                
                // Тень кратера
                let shadowRect = CGRect(x: x - craterSize/2, y: y - craterSize/2,
                                      width: craterSize, height: craterSize)
                context.fill(Path(ellipseIn: shadowRect),
                           with: .color(Color.black.opacity(shadowOpacity)))
            }
        }
    }
    
    private func isCraterVisible(angle: Double, phase: Double) -> Bool {
        let terminatorAngle = phase * 2.0 * .pi
        if phase <= 0.5 {
            return angle >= (terminatorAngle - .pi) && angle <= terminatorAngle
        } else {
            return angle <= (terminatorAngle - .pi) || angle >= terminatorAngle
        }
    }
    
    private func craterIntensity(at point: CGPoint, phase: Double) -> Double {
        let center = CGPoint(x: size * 0.5, y: size * 0.5)
        let terminatorX = center.x + (CGFloat(phase) * 2.0 - 1.0) * size * 0.5 * 0.9
        let distanceToTerminator = abs(point.x - terminatorX)
        
        return min(1.0, distanceToTerminator / (size * 0.3))
    }
}

// Упрощенная маска для маленького размера
struct SimpleRectangleMoonMask: View {
    var phase: Double
    var theme: MoonTheme
    
    private var visiblePercentage: CGFloat {
        if phase <= 0.5 {
            return CGFloat(phase / 0.5)
        } else {
            return CGFloat(1.0 - (phase - 0.5) / 0.5)
        }
    }
    
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let maskWidth = size * 1.0
            
            HStack(spacing: 0) {
                if phase <= 0.5 {
                    // Растущая луна
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    theme.moonShadow.opacity(0.8),
                                    theme.moonShadow.opacity(0.5)
                                ]),
                                startPoint: .trailing,
                                endPoint: .leading
                            )
                        )
                        .frame(width: maskWidth * (1.0 - visiblePercentage), height: size)
                    
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: maskWidth * visiblePercentage, height: size)
                } else {
                    // Убывающая луна
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: maskWidth * visiblePercentage, height: size)
                    
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    theme.moonShadow.opacity(0.5),
                                    theme.moonShadow.opacity(0.8)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: maskWidth * (1.0 - visiblePercentage), height: size)
                }
            }
            .frame(width: maskWidth, height: size)
        }
    }
}

// Упрощенная текстура шума для маленького размера
struct SimpleMoonNoiseTexture: View {
    let seed: Int
    let intensity: Double
    
    var body: some View {
        GeometryReader { geo in
            let size = max(geo.size.width, geo.size.height)
            Canvas { context, _ in
                var rng = SeededGenerator(seed: UInt64(seed))
                let pointCount = Int(size * 0.3) // Меньше точек для маленького размера
                
                for _ in 0..<pointCount {
                    let x = CGFloat.random(in: 0...size, using: &rng)
                    let y = CGFloat.random(in: 0...size, using: &rng)
                    let alpha = CGFloat.random(in: 0.01...0.05, using: &rng) * intensity
                    
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 0.5, height: 0.5)),
                        with: .color(Color.black.opacity(alpha))
                    )
                }
            }
        }
    }
}

// MARK: - Pressable Button Style

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Optimized Theme Preview Card

struct ThemePreviewCard: View {
    var theme: MoonTheme
    var isSelected: Bool
    var previewPhase: Double // ✅ Получаем фазу извне
    @EnvironmentObject private var store: MoonStore

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                backgroundView(for: theme)
                    .frame(width: 120, height: 90)
                    .cornerRadius(8)
                    .drawingGroup() // ✅ Критически важно для анимаций
                
                // Используем переданную фазу без вычислений
                BeautifulSimpleMoonView(phase: previewPhase)
                    .frame(width: 37, height: 37)
                    .padding(8)
            }
            .frame(width: 120, height: 90)
            .clipped()
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? theme.accentColor : Color.clear, lineWidth: 2)
            )

            Text(theme.name)
                .font(.caption)
                .foregroundColor(Color.primary)
        }
        .frame(width: 120)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Theme: \(theme.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    
    @ViewBuilder
    private func backgroundView(for theme: MoonTheme) -> some View {
        if theme.name == "Starry Night" {
            StarryNightBackground()
        } else if theme.name == "Ocean Light" {
            OceanLightBackground()
        } else if theme.name == "Lunar Silver" {
            LunarSilverBackground()
        } else if theme.name == "Cosmic Purple" {
            CosmicPurpleBackground()
        } else if let name = theme.backgroundImageName, UIImage(named: name) != nil {
            Image(name)
                .resizable()
                .scaledToFill()
        } else {
            theme.backgroundColor
        }
    }
}

// MARK: - Optimized Settings View

struct SettingsView: View {
    @EnvironmentObject var store: MoonStore
    @Environment(\.presentationMode) var presentation
    @State private var latText: String = ""
    @State private var lonText: String = ""
    @State private var useDeviceLocation: Bool = false
    @State private var showLocationAlert = false
    @State private var locationAlertMessage = ""
    
    // Кешируем данные для превью тем
    @State private var previewPhases: [String: Double] = [:]

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker(selection: Binding(get: { store.language }, set: { store.language = $0 }), label: Text(L10n.t("language", lang: store.language))) {
                        Text(L10n.t("language_ru", lang: store.language)).tag(AppLanguage.ru)
                        Text(L10n.t("language_en", lang: store.language)).tag(AppLanguage.en)
                    }
                }

                Section(header: Text(L10n.t("theme", lang: store.language))) {
                    Picker(selection: $store.selectedThemeName, label: Text(L10n.t("theme", lang: store.language))) {
                        ForEach(availableThemes, id: \.name) { theme in
                            Text(theme.name).tag(theme.name)
                        }
                    }
                    .pickerStyle(.menu)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) { // ✅ LazyHStack для горизонтального скролла
                            ForEach(availableThemes, id: \.name) { theme in
                                ThemePreviewCard(
                                    theme: theme,
                                    isSelected: theme.name == store.selectedThemeName,
                                    previewPhase: previewPhases[theme.name] ?? 0.5
                                )
                                .environmentObject(store)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) { // ✅ Упрощенная анимация
                                        store.selectedThemeName = theme.name
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section(header: Text(L10n.t("latitude", lang: store.language) + " / " + L10n.t("longitude", lang: store.language))) {
                    Toggle(L10n.t("use_device_location", lang: store.language), isOn: $useDeviceLocation)
                        .onChange(of: useDeviceLocation) { newValue in
                            if newValue {
                                requestLocation()
                            } else {
                                store.coordinate = nil
                                updateTextFieldsFromCoordinate()
                            }
                        }
                    TextField(L10n.t("latitude", lang: store.language), text: $latText)
                        .keyboardType(.decimalPad)
                        .onChange(of: latText) { _ in
                            updateUseDeviceLocationToggle()
                        }
                    TextField(L10n.t("longitude", lang: store.language), text: $lonText)
                        .keyboardType(.decimalPad)
                        .onChange(of: lonText) { _ in
                            updateUseDeviceLocationToggle()
                        }
                    Button(L10n.t("save", lang: store.language)) {
                        if let la = Double(latText), let lo = Double(lonText) {
                            store.coordinate = CLLocationCoordinate2D(latitude: la, longitude: lo)
                        }
                    }
                    .buttonStyle(PressableButtonStyle())
                    
                    Button(L10n.t("reset_coords", lang: store.language)) {
                        store.coordinate = nil
                        latText = ""
                        lonText = ""
                        useDeviceLocation = false
                    }
                    .buttonStyle(PressableButtonStyle())
                }

                Section {
                    Button(L10n.t("done", lang: store.language)) {
                        presentation.wrappedValue.dismiss()
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .navigationTitle(L10n.t("settings", lang: store.language))
            .onAppear {
                updateTextFieldsFromCoordinate()
                updateUseDeviceLocationToggle()
                precalculatePreviewPhases()
            }
            .onReceive(store.$coordinate) { coordinate in
                // ✅ АВТОМАТИЧЕСКОЕ ЗАПОЛНЕНИЕ ПОЛЕЙ ПРИ ИЗМЕНЕНИИ КООРДИНАТ
                if let coordinate = coordinate {
                    latText = String(format: "%.6f", coordinate.latitude)
                    lonText = String(format: "%.6f", coordinate.longitude)
                    useDeviceLocation = true
                } else {
                    latText = ""
                    lonText = ""
                    useDeviceLocation = false
                }
            }
            .alert("Location Error", isPresented: $showLocationAlert) {
                Button("OK") { }
            } message: {
                Text(locationAlertMessage)
            }
        }
        .transaction { transaction in
            // ✅ Оптимизируем анимации перехода
            transaction.animation = transaction.animation?.speed(1.2)
        }
    }
    
    private func updateTextFieldsFromCoordinate() {
        if let c = store.coordinate {
            latText = String(format: "%.6f", c.latitude)
            lonText = String(format: "%.6f", c.longitude)
            useDeviceLocation = true
        } else {
            latText = ""
            lonText = ""
            useDeviceLocation = false
        }
    }
    
    private func updateUseDeviceLocationToggle() {
        if !latText.isEmpty || !lonText.isEmpty {
            if let currentCoord = store.coordinate {
                let enteredLat = Double(latText) ?? 0
                let enteredLon = Double(lonText) ?? 0
                if abs(enteredLat - currentCoord.latitude) > 0.0001 || abs(enteredLon - currentCoord.longitude) > 0.0001 {
                    useDeviceLocation = false
                }
            } else {
                useDeviceLocation = false
            }
        }
    }

    private func requestLocation() {
        Task {
            do {
                let coordinate = try await LocationManager.shared.requestLocation()
                await MainActor.run {
                    if let coordinate = coordinate {
                        store.coordinate = coordinate
                        // ✅ ПОЛЯ АВТОМАТИЧЕСКИ ЗАПОЛНЯТСЯ ЧЕРЕЗ onReceive
                    } else {
                        locationAlertMessage = "Failed to get location coordinates"
                        showLocationAlert = true
                        useDeviceLocation = false
                    }
                }
            } catch {
                await MainActor.run {
                    locationAlertMessage = error.localizedDescription
                    showLocationAlert = true
                    useDeviceLocation = false
                }
            }
        }
    }
    
    private func precalculatePreviewPhases() {
        let date = Date()
        for theme in availableThemes {
            previewPhases[theme.name] = store.moonData(for: date).phase
        }
    }
}

// MARK: - Main App & Content View

@main
struct MoonPhaseApp: App {
    @StateObject private var store = MoonStore.shared
    
    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem {
                        Image(systemName: "moon")
                        Text("Луна")
                    }
                    .tag(0)
                
                MonthCalendarView()
                    .tabItem {
                        Image(systemName: "calendar")
                        Text("Календарь")
                    }
                    .tag(1)
            }
            .environmentObject(store)
            .accentColor(store.currentTheme.accentColor)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: MoonStore
    @State private var showSettings = false
    @State private var isSettingsPressed = false
    @State private var showLocationAlert = false
    @State private var locationAlertMessage = ""

    var body: some View {
        NavigationView {
            ZStack {
                backgroundView(for: store.currentTheme)
                VStack(spacing: 0) {
                    HStack {
                        Text(L10n.t("app_title", lang: store.language))
                            .font(.largeTitle).bold()
                            .foregroundColor(store.currentTheme.textColor)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        
                        Button(action: {
                            showSettings.toggle()
                        }) {
                            Image(systemName: "gearshape")
                                .imageScale(.large)
                                .foregroundColor(store.currentTheme.accentColor)
                                .scaleEffect(isSettingsPressed ? 0.8 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSettingsPressed)
                        }
                        .buttonStyle(SettingsButtonStyle(isPressed: $isSettingsPressed))
                        .accessibilityLabel(L10n.t("settings", lang: store.language))
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    
                    Spacer()
                        .frame(height: 38)
                    
                    VStack(spacing: 16) {
                        GorgeousRealisticMoonView(phase: store.result.phase)
                            .frame(width: 223, height: 223)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)

                        // ИНФОРМАЦИЯ О ДНЕ И ОСВЕЩЕНИИ СДВИНУТА НИЖЕ
                        HStack(spacing: 24) {
                            statBlock(value: String(format: "%.1f", store.result.age), label: L10n.t("day", lang: store.language), theme: store.currentTheme)
                            statBlock(value: String(format: "%.0f%%", store.result.illumination * 100.0), label: L10n.t("illum", lang: store.language), theme: store.currentTheme)
                        }
                        .padding(.top, 30) // УВЕЛИЧЕНО С 14 ДО 30

                        // Новая секция с временем восхода и захода Луны
                        VStack(spacing: 8) {
                            HStack {
                                // Восход Луны (слева)
                                VStack(spacing: 4) {
                                    Image(systemName: "moon.stars.fill")
                                        .font(.caption)
                                        .foregroundColor(store.currentTheme.accentColor)
                                    Text(L10n.t("moonrise", lang: store.language))
                                        .font(.caption2)
                                        .foregroundColor(store.currentTheme.textColor.opacity(0.8))
                                    Text(TimeFormatter.timeString(from: store.result.moonrise))
                                        .font(.system(.body, design: .monospaced))
                                        .bold()
                                        .foregroundColor(store.currentTheme.textColor)
                                }
                                
                                Spacer()
                                
                                // Заход Луны (справа)
                                VStack(spacing: 4) {
                                    Image(systemName: "moon.fill")
                                        .font(.caption)
                                        .foregroundColor(store.currentTheme.accentColor)
                                    Text(L10n.t("moonset", lang: store.language))
                                        .font(.caption2)
                                        .foregroundColor(store.currentTheme.textColor.opacity(0.8))
                                    Text(TimeFormatter.timeString(from: store.result.moonset))
                                        .font(.system(.body, design: .monospaced))
                                        .bold()
                                        .foregroundColor(store.currentTheme.textColor)
                                }
                            }
                            .padding(.horizontal, 40)
                            
                            // Информация о местоположении
                            if store.coordinate != nil {
                                Text(getLocationStatusText())
                                    .font(.caption2)
                                    .foregroundColor(store.currentTheme.textColor.opacity(0.6))
                                    .multilineTextAlignment(.center)
                            } else {
                                Button(action: {
                                    requestLocation()
                                }) {
                                    Text(L10n.t("use_device_location", lang: store.language))
                                        .font(.caption2)
                                        .foregroundColor(store.currentTheme.accentColor)
                                }
                                .buttonStyle(PressableButtonStyle())
                            }
                        }
                        .padding(.top, 8)

                        // СДВИНУТЫЙ ВНИЗ БЛОК С ИНФОРМАЦИЕЙ
                        VStack(spacing: 6) {
                            HStack {
                                Text(L10n.t("date", lang: store.language))
                                    .font(.subheadline)
                                    .foregroundColor(store.currentTheme.accentColor)
                                Spacer()
                                Button(L10n.t("today", lang: store.language)) {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        store.selectedDate = Date()
                                    }
                                }
                                .font(.subheadline)
                                .foregroundColor(store.currentTheme.accentColor)
                                .buttonStyle(PressableButtonStyle())
                                .accessibilityLabel("Go to today")
                            }
                            
                            DatePicker("", selection: $store.selectedDate, in: dateRange, displayedComponents: [.date])
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .accentColor(store.currentTheme.accentColor)
                                .colorScheme(.dark)
                                .accessibilityLabel("Select date")
                        }
                        .padding(.horizontal)
                        .padding(.top, 40) // УВЕЛИЧЕННЫЙ ОТСТУП СВЕРХУ ДЛЯ СДВИГА ВНИЗ

                        Spacer()
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(store)
        }
        .alert("Location Error", isPresented: $showLocationAlert) {
            Button("OK") { }
        } message: {
            Text(locationAlertMessage)
        }
    }
    
    private var dateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: Date())!
        let oneYearLater = calendar.date(byAdding: .year, value: 1, to: Date())!
        return oneYearAgo...oneYearLater
    }
    
    private func getLocationStatusText() -> String {
        guard let coordinate = store.coordinate else {
            return L10n.t("no_location", lang: store.language)
        }
        
        let lat = String(format: "%.2f", coordinate.latitude)
        let lon = String(format: "%.2f", coordinate.longitude)
        
        return "📍 \(lat)°, \(lon)°"
    }
    
    private func requestLocation() {
        Task {
            do {
                let coordinate = try await LocationManager.shared.requestLocation()
                await MainActor.run {
                    if let coordinate = coordinate {
                        store.coordinate = coordinate
                    } else {
                        locationAlertMessage = "Failed to get location coordinates"
                        showLocationAlert = true
                    }
                }
            } catch {
                await MainActor.run {
                    locationAlertMessage = error.localizedDescription
                    showLocationAlert = true
                }
            }
        }
    }

    @ViewBuilder
    private func backgroundView(for theme: MoonTheme) -> some View {
        if theme.name == "Starry Night" {
            // Используем кастомное звездное небо для темы Starry Night
            StarryNightBackground()
        } else if theme.name == "Ocean Light" {
            // Используем кастомный океанский фон для темы Ocean Light
            OceanLightBackground()
        } else if theme.name == "Lunar Silver" {
            // Используем кастомный серебристый фон для темы Lunar Silver
            LunarSilverBackground()
        } else if theme.name == "Cosmic Purple" {
            // Используем кастомный космический пурпурный фон для темы Cosmic Purple
            CosmicPurpleBackground()
        } else if let name = theme.backgroundImageName, UIImage(named: name) != nil {
            Image(name)
                .resizable()
                .scaledToFill()
                .overlay(LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0.25), Color.black.opacity(0.0)]), startPoint: .bottom, endPoint: .top))
                .ignoresSafeArea()
        } else {
            theme.backgroundColor
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func statBlock(value: String, label: String, theme: MoonTheme) -> some View {
        VStack {
            Text(value).font(.title2).bold().foregroundColor(theme.textColor)
            Text(label).font(.caption).foregroundColor(theme.textColor.opacity(0.8))
        }
        .frame(minWidth: 100)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

struct SettingsButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 50, height: 50)
            .contentShape(Rectangle())
            .background(
                Circle()
                    .fill(configuration.isPressed ? Color.gray.opacity(0.2) : Color.clear)
                    .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
            )
            .onChange(of: configuration.isPressed) { newValue in
                isPressed = newValue
            }
    }
}

// MARK: - Calendar and Day Detail

struct MonthCalendarView: View {
    @EnvironmentObject var store: MoonStore
    @State private var currentMonthDate: Date = Date()
    @State private var selectedDetailDate: Date = Date()
    @State private var showDetail: Bool = false

    var body: some View {
        NavigationView {
            ZStack {
                backgroundView(for: store.currentTheme)
                VStack {
                    HStack {
                        Button(action: { changeMonth(by: -1) }) {
                            Image(systemName: "chevron.left")
                                .foregroundColor(store.currentTheme.isDark ? .white : .primary)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("Previous month")
                        Spacer()
                        Text(monthTitle(for: currentMonthDate))
                            .font(.headline)
                            .foregroundColor(store.currentTheme.isDark ? .white : .primary)
                        Spacer()
                        Button(action: { changeMonth(by: 1) }) {
                            Image(systemName: "chevron.right")
                                .foregroundColor(store.currentTheme.isDark ? .white : .primary)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("Next month")
                    }
                    .padding(.horizontal)

                    CalendarGridWithIcons(centerDate: currentMonthDate,
                                          onSelectDay: { date in
                                              selectedDetailDate = date
                                              store.selectedDate = date
                                              showDetail = true
                                          })
                        .environmentObject(store)

                    Spacer()
                }
            }
            .navigationBarTitle(L10n.t("calendar", lang: store.language), displayMode: .large)
            .onAppear {
                // Устанавливаем правильный цвет для заголовка навигационной панели
                let appearance = UINavigationBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = UIColor.clear
                appearance.titleTextAttributes = [.foregroundColor: store.currentTheme.isDark ? UIColor.white : UIColor.label]
                appearance.largeTitleTextAttributes = [.foregroundColor: store.currentTheme.isDark ? UIColor.white : UIColor.label]
                
                UINavigationBar.appearance().standardAppearance = appearance
                UINavigationBar.appearance().scrollEdgeAppearance = appearance
            }
            .sheet(isPresented: $showDetail) {
                CalendarDayDetailView(date: selectedDetailDate)
                    .environmentObject(store)
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
        df.locale = Locale(identifier: store.language == .ru ? "ru_RU" : "en_US")
        df.dateFormat = "LLLL yyyy"
        return df.string(from: date).capitalized
    }
    
    @ViewBuilder
    private func backgroundView(for theme: MoonTheme) -> some View {
        if theme.name == "Starry Night" {
            // Используем кастомное звездное небо для темы Starry Night
            StarryNightBackground()
        } else if theme.name == "Ocean Light" {
            // Используем кастомный океанский фон для темы Ocean Light
            OceanLightBackground()
        } else if theme.name == "Lunar Silver" {
            // Используем кастомный серебристый фон для темы Lunar Silver
            LunarSilverBackground()
        } else if theme.name == "Cosmic Purple" {
            // Используем кастомный космический пурпурный фон для темы Cosmic Purple
            CosmicPurpleBackground()
        } else if let name = theme.backgroundImageName, UIImage(named: name) != nil {
            Image(name)
                .resizable()
                .scaledToFill()
                .overlay(LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0.25), Color.black.opacity(0.0)]), startPoint: .bottom, endPoint: .top))
                .ignoresSafeArea()
        } else {
            theme.backgroundColor
                .ignoresSafeArea()
        }
    }
}

struct CalendarDayDetailView: View {
    @EnvironmentObject var store: MoonStore
    @Environment(\.presentationMode) var presentation
    var date: Date

    @State private var animateIn: Bool = false

    private var moonResult: MoonPhaseResult {
        store.moonData(for: store.selectedDate)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    Button(action: { presentation.wrappedValue.dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(store.currentTheme.isDark ? .white : store.currentTheme.accentColor)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .padding(.top, 10)
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal)

                Spacer()
                    .frame(height: 76)

                VStack(spacing: 8) {
                    Text(dateLongString(store.selectedDate))
                        .font(.title2)
                        .bold()
                        .foregroundColor(store.currentTheme.textColor)
                        .accessibilityAddTraits(.isHeader)
                        .multilineTextAlignment(.center)
                        .padding(.top, -84)
                    
                    Text(L10n.phaseName(for: moonResult.phase, lang: store.language))
                        .font(.headline)
                        .foregroundColor(store.currentTheme.textColor)
                        .multilineTextAlignment(.center)
                        .padding(.top, -38)
                }
                .padding(.horizontal)

                VStack(spacing: 20) {
                    GorgeousRealisticMoonView(phase: moonResult.phase)
                        .frame(width: 195, height: 195)
                        .frame(maxWidth: .infinity)
                        .scaleEffect(animateIn ? 1.0 : 0.6)
                        .opacity(animateIn ? 1.0 : 0.0)
                        .onAppear {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                                animateIn = true
                            }
                        }
                        .padding(.top, 27)

                    // Время восхода и захода разнесены по краям
                    VStack(spacing: 12) {
                        HStack {
                            // Восход Луны (слева)
                            VStack(spacing: 6) {
                                Image(systemName: "moon.stars.fill")
                                    .font(.title3)
                                    .foregroundColor(store.currentTheme.accentColor)
                                Text(L10n.t("moonrise", lang: store.language))
                                    .font(.caption)
                                    .foregroundColor(store.currentTheme.textColor.opacity(0.8))
                                Text(TimeFormatter.timeString(from: moonResult.moonrise))
                                    .font(.title3)
                                    .bold()
                                    .foregroundColor(store.currentTheme.textColor)
                            }
                            
                            Spacer()
                            
                            // Заход Луны (справа)
                            VStack(spacing: 6) {
                                Image(systemName: "moon.fill")
                                    .font(.title3)
                                    .foregroundColor(store.currentTheme.accentColor)
                                Text(L10n.t("moonset", lang: store.language))
                                    .font(.caption)
                                    .foregroundColor(store.currentTheme.textColor.opacity(0.8))
                                Text(TimeFormatter.timeString(from: moonResult.moonset))
                                    .font(.title3)
                                    .bold()
                                    .foregroundColor(store.currentTheme.textColor)
                            }
                        }
                        .padding(.horizontal, 40)
                        
                        if store.coordinate != nil {
                            Text(getLocationStatusText())
                                .font(.caption)
                                .foregroundColor(store.currentTheme.textColor.opacity(0.6))
                        }
                    }
                    .padding(.top, 20)

                    VStack(spacing: 16) {
                        HStack(spacing: 28) {
                            VStack {
                                Text(String(format: "%.1f", moonResult.age))
                                    .font(.title3)
                                    .bold()
                                    .foregroundColor(store.currentTheme.textColor)
                                Text(L10n.t("day", lang: store.language))
                                    .font(.caption)
                                    .foregroundColor(store.currentTheme.isDark ? .white : .secondary)
                            }
                            VStack {
                                Text(String(format: "%.0f%%", moonResult.illumination*100))
                                    .font(.title3)
                                    .bold()
                                    .foregroundColor(store.currentTheme.textColor)
                                Text(L10n.t("illum", lang: store.language))
                                    .font(.caption)
                                    .foregroundColor(store.currentTheme.isDark ? .white : .secondary)
                            }
                            VStack {
                                Text(moonResult.distanceKm != nil ? String(format: "%.0f km", moonResult.distanceKm!) : "—")
                                    .font(.title3)
                                    .bold()
                                    .foregroundColor(store.currentTheme.textColor)
                                Text(L10n.t("distance", lang: store.language))
                                    .font(.caption)
                                    .foregroundColor(store.currentTheme.isDark ? .white : .secondary)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.top, 20)
                }
                .padding(.top, 38)

                Spacer()
                    .frame(height: 50)
            }
        }
        .background(backgroundView(for: store.currentTheme))
    }

    private func dateLongString(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: store.language == .ru ? "ru_RU" : "en_US")
        df.dateStyle = .full
        return df.string(from: d)
    }
    
    private func getLocationStatusText() -> String {
        guard let coordinate = store.coordinate else {
            return L10n.t("no_location", lang: store.language)
        }
        
        let lat = String(format: "%.4f", coordinate.latitude)
        let lon = String(format: "%.4f", coordinate.longitude)
        
        return "📍 Ш: \(lat)° Д: \(lon)°"
    }

    @ViewBuilder
    private func backgroundView(for theme: MoonTheme) -> some View {
        if theme.name == "Starry Night" {
            // Используем кастомное звездное небо для темы Starry Night
            StarryNightBackground()
        } else if theme.name == "Ocean Light" {
            // Используем кастомный океанский фон для темы Ocean Light
            OceanLightBackground()
        } else if theme.name == "Lunar Silver" {
            // Используем кастомный серебристый фон для темы Lunar Silver
            LunarSilverBackground()
        } else if theme.name == "Cosmic Purple" {
            // Используем кастомный космический пурпурный фон для темы Cosmic Purple
            CosmicPurpleBackground()
        } else if let name = theme.backgroundImageName, UIImage(named: name) != nil {
            Image(name)
                .resizable()
                .scaledToFill()
                .overlay(LinearGradient(gradient: Gradient(colors: [Color.black.opacity(0.25), Color.black.opacity(0.0)]), startPoint: .bottom, endPoint: .top))
                .ignoresSafeArea()
        } else {
            theme.backgroundColor
                .ignoresSafeArea()
        }
    }
}

// КАЛЕНДАРНАЯ СЕТКА

struct CalendarGridWithIcons: View {
    @EnvironmentObject var store: MoonStore
    var centerDate: Date
    var onSelectDay: (Date) -> Void

    var body: some View {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: centerDate)
        
        if let startOfMonth = cal.date(from: comps),
           let range = cal.range(of: .day, in: .month, for: centerDate) {
            
            let firstWeekday = cal.component(.weekday, from: startOfMonth)
            let pad = (firstWeekday + 6) % 7
            let days = Array(range)
            let padded = Array(repeating: 0, count: pad) + days
            
            let weekdays = store.language == .ru ?
                ["Пн","Вт","Ср","Чт","Пт","Сб","Вс"] :
                ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
            
            VStack {
                HStack {
                    ForEach(weekdays, id: \.self) { d in
                        Text(d).font(.caption)
                            .foregroundColor(store.currentTheme.isDark ? .white : .primary)
                            .frame(maxWidth: .infinity)
                    }
                }
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                    ForEach(padded.indices, id: \.self) { idx in
                        if padded[idx] == 0 {
                            Color.clear.frame(height: 72)
                        } else {
                            let day = padded[idx]
                            let date = cal.date(byAdding: .day, value: day - 1, to: startOfMonth)!
                            CalendarDayIcon(date: date, onTap: {
                                onSelectDay(date)
                            })
                            .environmentObject(store)
                        }
                    }
                }
                .padding(.horizontal)
            }
        } else {
            Text("Calendar error")
                .font(.headline)
                .padding()
        }
    }
}

struct CalendarDayIcon: View {
    @EnvironmentObject var store: MoonStore
    var date: Date
    var onTap: () -> Void

    private var moonResult: MoonPhaseResult {
        store.moonData(for: date)
    }

    var body: some View {
        VStack(spacing: 2) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.black) // ИЗМЕНЕНИЕ: черный цвет для числа
                .zIndex(1)
            
            // ЗАМЕНА: Используем реалистичную луну вместо упрощенной
            CalendarRealisticMoonView(phase: moonResult.phase)
                .frame(width: 31, height: 31)
            
            Text(String(format: "%.0f%%", moonResult.illumination * 100.0))
                .font(.caption2)
                .foregroundColor(.black) // ИЗМЕНЕНИЕ: черный цвет для процента
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(store.currentTheme.isDark ? Color(UIColor.secondarySystemBackground) : Color(UIColor.systemBackground)))
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Day \(Calendar.current.component(.day, from: date)), Moon phase \(String(format: "%.0f%%", moonResult.illumination * 100.0)) illuminated")
    }
}

// MARK: - Helper Functions

func waxingWaningPercent(phase: Double, lang: AppLanguage) -> (label: String, percent: Double) {
    let p = phase
    if p <= 0.5 {
        let percent = (p / 0.5) * 100.0
        let label = (lang == .ru) ? "Растёт" : "Waxing"
        return (label, percent)
    } else {
        let percent = ((p - 0.5) / 0.5) * 100.0
        let label = (lang == .ru) ? "Убывает" : "Waning"
        return (label, percent)
    }
}

// MARK: - Preview

#if DEBUG
struct MoonPhaseAll_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView().environmentObject(MoonStore.shared)
            SettingsView().environmentObject(MoonStore.shared)
            MonthCalendarView().environmentObject(MoonStore.shared)
        }
    }
}
#endif
