import WidgetKit
import SwiftUI
import CoreLocation

// MARK: - Models
public struct MoonPhaseResult: Equatable, Codable {
    public let date: Date
    public let age: Double
    public let illumination: Double
    public let phase: Double
    public let distanceKm: Double?
    public let phaseName: String?
    public let moonrise: Date?
    public let moonset: Date?
    
    public init(date: Date, age: Double, illumination: Double, phase: Double, distanceKm: Double? = nil, phaseName: String? = nil, moonrise: Date? = nil, moonset: Date? = nil) {
        self.date = date
        self.age = age
        self.illumination = illumination
        self.phase = phase
        self.distanceKm = distanceKm
        self.phaseName = phaseName
        self.moonrise = moonrise
        self.moonset = moonset
    }
}

// MARK: - Moon Cache
struct MoonPhaseCache {
    private static let appGroup = "group.com.yourapp.moonphase"
    private static let cacheKey = "moonPhaseCache"
    private static let cacheTimestampKey = "moonPhaseCacheTimestamp"
    private static let cacheExpiration: TimeInterval = 3600 // 1 час
    
    static func save(_ result: MoonPhaseResult) {
        guard let sharedDefaults = UserDefaults(suiteName: appGroup) else { return }
        
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(result) {
            sharedDefaults.set(encoded, forKey: cacheKey)
            sharedDefaults.set(Date().timeIntervalSince1970, forKey: cacheTimestampKey)
        }
    }
    
    static func load() -> MoonPhaseResult? {
        guard let sharedDefaults = UserDefaults(suiteName: appGroup),
              let savedData = sharedDefaults.data(forKey: cacheKey),
              let timestamp = sharedDefaults.value(forKey: cacheTimestampKey) as? TimeInterval else {
            return nil
        }
        
        // Проверяем не устарели ли данные
        let now = Date().timeIntervalSince1970
        if now - timestamp > cacheExpiration {
            return nil
        }
        
        let decoder = JSONDecoder()
        return try? decoder.decode(MoonPhaseResult.self, from: savedData)
    }
    
    static func clear() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroup) else { return }
        sharedDefaults.removeObject(forKey: cacheKey)
        sharedDefaults.removeObject(forKey: cacheTimestampKey)
    }
}

// MARK: - Theme Definitions for Widget
enum WidgetTheme {
    case oceanLight
    case lunarSilver
    case defaultDark
    
    var backgroundColor: Color {
        switch self {
        case .oceanLight:
            return Color(red: 0.9, green: 0.95, blue: 1.0) // Бело-синий
        case .lunarSilver:
            return Color(white: 0.6).opacity(0.6) // Еще более темный серый
        case .defaultDark:
            return Color(red: 0.02, green: 0.02, blue: 0.06)
        }
    }
    
    var gradientColors: [Color] {
        switch self {
        case .oceanLight:
            return [
                Color(red: 0.9, green: 0.95, blue: 1.0),
                Color(red: 0.8, green: 0.9, blue: 1.0)
            ]
        case .lunarSilver:
            return [
                Color(white: 0.6).opacity(0.6),  // Еще более темный серый
                Color(white: 0.5).opacity(0.6)   // Самый темный
            ]
        case .defaultDark:
            return [
                Color(red: 0.02, green: 0.02, blue: 0.06),
                Color(red: 0.05, green: 0.03, blue: 0.15)
            ]
        }
    }
    
    var textColor: Color {
        switch self {
        case .oceanLight:
            return Color(red: 0.1, green: 0.2, blue: 0.4) // Темно-синий для контраста
        case .lunarSilver:
            return Color(white: 0.35) // Еще более темный серый для контраста
        case .defaultDark:
            return Color.white
        }
    }
    
    var accentColor: Color {
        switch self {
        case .oceanLight:
            return Color.blue
        case .lunarSilver:
            return Color.purple
        case .defaultDark:
            return Color.blue
        }
    }
}

// MARK: - Widget Theme Detection
struct WidgetThemeHelper {
    private static let appGroup = "group.com.yourapp.moonphase" // Тот же App Group ID
    
    static func currentTheme() -> WidgetTheme {
        guard let sharedDefaults = UserDefaults(suiteName: appGroup),
              let savedTheme = sharedDefaults.string(forKey: "selectedTheme") else {
            return .defaultDark
        }
        
        if savedTheme == "Ocean Light" {
            return .oceanLight
        } else if savedTheme == "Lunar Silver" {
            return .lunarSilver
        } else {
            return .defaultDark
        }
    }
}

// MARK: - Localization
struct WidgetL10n {
    private static let appGroup = "group.com.yourapp.moonphase" // Тот же App Group ID
    
    static func currentLanguage() -> String {
        guard let sharedDefaults = UserDefaults(suiteName: appGroup),
              let savedLanguage = sharedDefaults.string(forKey: "appLanguage") else {
            // Fallback на системный язык
            let systemLang = Locale.current.languageCode ?? "en"
            return systemLang
        }
        return savedLanguage
    }
    
    static func t(_ key: String) -> String {
        let language = currentLanguage()
        let isRussian = language == "ru"
        
        let localizations: [String: [String: String]] = [
            "moon": ["en": "Moon", "ru": "Луна"],
            "moon_phase": ["en": "Moon Phase", "ru": "Фаза Луны"],
            "lunar_day": ["en": "Lunar Day", "ru": "Лунные сутки"],
            "illumination": ["en": "Illumination", "ru": "Освещение"],
            "phase": ["en": "Phase", "ru": "Фаза"],
            "waxing": ["en": "Waxing", "ru": "Растёт"],
            "waning": ["en": "Waning", "ru": "Убывает"],
            "new_moon": ["en": "New Moon", "ru": "Новолуние"],
            "waxing_crescent": ["en": "Waxing Crescent", "ru": "Растущий серп"],
            "first_quarter": ["en": "First Quarter", "ru": "Первая четверть"],
            "waxing_gibbous": ["en": "Waxing Gibbous", "ru": "Растущая луна"],
            "full_moon": ["en": "Full Moon", "ru": "Полнолуние"],
            "waning_gibbous": ["en": "Waning Gibbous", "ru": "Убывающая луна"],
            "last_quarter": ["en": "Last Quarter", "ru": "Последняя четверть"],
            "waning_crescent": ["en": "Waning Crescent", "ru": "Убывающий серп"],
            "distance": ["en": "Distance", "ru": "Расстояние"],
            "next_phase": ["en": "Next Phase", "ru": "Следующая фаза"],
            "in_days": ["en": "in days", "ru": "через дней"]
        ]
        
        return localizations[key]?[isRussian ? "ru" : "en"] ?? key
    }
    
    static func phaseName(for phase: Double) -> String {
        let language = currentLanguage()
        let isRussian = language == "ru"
        
        let names: [(range: ClosedRange<Double>, en: String, ru: String)] = [
            (0.0...0.03, "New Moon", "Новолуние"),
            (0.03...0.22, "Waxing Crescent", "Растущий серп"),
            (0.22...0.28, "First Quarter", "Первая четверть"),
            (0.28...0.47, "Waxing Gibbous", "Растущая луна"),
            (0.47...0.53, "Full Moon", "Полнолуние"),
            (0.53...0.72, "Waning Gibbous", "Убывающая луна"),
            (0.72...0.78, "Last Quarter", "Последняя четверть"),
            (0.78...1.0, "Waning Crescent", "Убывающий серп")
        ]
        
        let normalizedPhase = phase > 0.97 ? 0.0 : phase
        
        for name in names {
            if name.range.contains(normalizedPhase) {
                return isRussian ? name.ru : name.en
            }
        }
        return isRussian ? "Новолуние" : "New Moon"
    }
}

// MARK: - Engine
public final class DefaultMoonEngine {
    private let synodicMonth = 29.53058867

    public init() {}

    public func calculate(for date: Date, coordinate: CLLocationCoordinate2D?) -> MoonPhaseResult {
        let jd = julianDate(from: date)
        
        let daysSinceKnownNewMoon = jd - 2451549.5
        var age = daysSinceKnownNewMoon.truncatingRemainder(dividingBy: synodicMonth)
        if age < 0 { age += synodicMonth }
        
        let phase = age / synodicMonth
        let phaseAngle = 2.0 * Double.pi * phase
        let illumination = 0.5 * (1.0 - cos(phaseAngle))
        
        let distanceKm = calculateMoonDistance(julianDate: jd)
        let phaseName = WidgetL10n.phaseName(for: phase)
        
        // Расчет следующей фазы
        let nextNewMoon = calculateNextMajorPhase(currentPhase: phase, currentDate: date)
        
        return MoonPhaseResult(
            date: date,
            age: age,
            illumination: illumination,
            phase: phase,
            distanceKm: distanceKm,
            phaseName: phaseName,
            moonrise: nextNewMoon
        )
    }

    private func calculateMoonDistance(julianDate: Double) -> Double {
        let T = (julianDate - 2451545.0) / 36525.0
        let Mp = deg2rad(134.9633964 + 477198.8675055 * T)
        return 385000.56 - 20905.355 * cos(Mp)
    }
    
    private func calculateNextMajorPhase(currentPhase: Double, currentDate: Date) -> Date? {
        let synodicMonth = 29.53058867
        let calendar = Calendar.current
        
        // Определяем следующую главную фазу
        let nextPhaseDays: Double
        if currentPhase < 0.25 {
            nextPhaseDays = (0.25 - currentPhase) * synodicMonth
        } else if currentPhase < 0.5 {
            nextPhaseDays = (0.5 - currentPhase) * synodicMonth
        } else if currentPhase < 0.75 {
            nextPhaseDays = (0.75 - currentPhase) * synodicMonth
        } else {
            nextPhaseDays = (1.0 - currentPhase) * synodicMonth
        }
        
        return calendar.date(byAdding: .day, value: Int(ceil(nextPhaseDays)), to: currentDate)
    }

    private func julianDate(from date: Date) -> Double {
        let timeInterval = date.timeIntervalSince1970
        return timeInterval / 86400.0 + 2440587.5
    }
    
    private func deg2rad(_ x: Double) -> Double { x * .pi / 180.0 }
}

// MARK: - Repository
public final class MoonRepository {
    private let engine: DefaultMoonEngine
    
    public init() {
        self.engine = DefaultMoonEngine()
    }
    
    public func moonData(for date: Date, coordinate: CLLocationCoordinate2D?) -> MoonPhaseResult {
        return engine.calculate(for: date, coordinate: coordinate)
    }
}

// MARK: - Timeline Provider
struct Provider: TimelineProvider {
    private let repository = MoonRepository()
    
    func placeholder(in context: Context) -> MoonPhaseEntry {
        MoonPhaseEntry(date: Date(), result: repository.moonData(for: Date(), coordinate: nil))
    }

    func getSnapshot(in context: Context, completion: @escaping (MoonPhaseEntry) -> ()) {
        // Для snapshot используем кеш или текущие данные
        if let cached = MoonPhaseCache.load() {
            let entry = MoonPhaseEntry(date: Date(), result: cached)
            completion(entry)
        } else {
            let result = repository.moonData(for: Date(), coordinate: nil)
            MoonPhaseCache.save(result)
            let entry = MoonPhaseEntry(date: Date(), result: result)
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let currentDate = Date()
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: currentDate)! // Чаще обновляем
        
        var result: MoonPhaseResult
        
        // Пробуем загрузить из кеша
        if let cached = MoonPhaseCache.load() {
            result = cached
        } else {
            // Вычисляем и кешируем
            result = repository.moonData(for: currentDate, coordinate: nil)
            MoonPhaseCache.save(result)
        }
        
        let entries = [MoonPhaseEntry(date: currentDate, result: result)]
        let timeline = Timeline(entries: entries, policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct MoonPhaseEntry: TimelineEntry {
    let date: Date
    let result: MoonPhaseResult
}

// MARK: - Real Moon View with Image
struct RealMoonView: View {
    let phase: Double
    let size: CGFloat
    private let widgetTheme = WidgetThemeHelper.currentTheme()
    
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
    
    var body: some View {
        ZStack {
            // Реальное изображение луны
            if UIImage(named: "moon_texture") != nil {
                Image("moon_texture")
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                // Fallback - градиентный круг если изображения нет
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(white: widgetTheme == .oceanLight ? 0.98 : 0.95),
                                Color(white: widgetTheme == .oceanLight ? 0.92 : 0.85),
                                Color(white: widgetTheme == .oceanLight ? 0.88 : 0.75)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
            }
            
            // Маска для фазы луны - ПРАВИЛЬНАЯ логика (не зеркальная)
            if !isFullMoon && !isNewMoon {
                HStack(spacing: 0) {
                    if phase <= 0.5 {
                        // Растущая луна - тень слева (правильно)
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.black.opacity(0.95),
                                        Color.black.opacity(0.85),
                                        Color.black.opacity(0.7)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: size * CGFloat(1.0 - visiblePercentage), height: size)
                        Spacer()
                    } else {
                        // Убывающая луна - тень справа (правильно)
                        Spacer()
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.black.opacity(0.7),
                                        Color.black.opacity(0.85),
                                        Color.black.opacity(0.95)
                                    ]),
                                    startPoint: .trailing,
                                    endPoint: .leading
                                )
                            )
                            .frame(width: size * CGFloat(1.0 - visiblePercentage), height: size)
                    }
                }
                .frame(width: size, height: size)
            } else if isNewMoon {
                // Новолуние - полная тень
                Circle()
                    .fill(Color.black.opacity(0.9))
                    .frame(width: size, height: size)
            }
            // Полнолуние - без тени
        }
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(widgetTheme.textColor.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(widgetTheme == .oceanLight ? 0.2 : 0.3), radius: 3, x: 2, y: 2)
    }
}

// MARK: - Widget Views
struct MoonPhaseWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallMoonWidget(entry: entry)
        case .systemMedium:
            MediumMoonWidget(entry: entry)
        case .systemLarge:
            LargeMoonWidget(entry: entry)
        default:
            SmallMoonWidget(entry: entry)
        }
    }
}

struct SmallMoonWidget: View {
    var entry: MoonPhaseEntry
    private let widgetTheme = WidgetThemeHelper.currentTheme()
    
    private var waxingWaning: String {
        entry.result.phase <= 0.5 ? WidgetL10n.t("waxing") : WidgetL10n.t("waning")
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Заголовок
            Text(WidgetL10n.t("moon"))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(widgetTheme.textColor.opacity(0.8))
            
            // Реальное изображение луны с фазой
            RealMoonView(phase: entry.result.phase, size: 45)
            
            // Лунные сутки
            Text("\(WidgetL10n.t("lunar_day")) \(String(format: "%.1f", entry.result.age))")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(widgetTheme.textColor)
                .multilineTextAlignment(.center)
            
            // Процент освещенности
            Text("\(Int(entry.result.illumination * 100))%")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(widgetTheme.textColor.opacity(0.9))
            
            // Статус (растущая/убывающая)
            Text(waxingWaning)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(widgetTheme.textColor.opacity(0.7))
        }
        .padding(8)
        .containerBackground(for: .widget) {
            LinearGradient(
                gradient: Gradient(colors: widgetTheme.gradientColors),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct MediumMoonWidget: View {
    var entry: MoonPhaseEntry
    private let widgetTheme = WidgetThemeHelper.currentTheme()
    
    private var waxingWaning: String {
        entry.result.phase <= 0.5 ? WidgetL10n.t("waxing") : WidgetL10n.t("waning")
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Левая часть - реальное изображение луны
            VStack(spacing: 8) {
                Text(WidgetL10n.t("moon_phase"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(widgetTheme.textColor)
                
                RealMoonView(phase: entry.result.phase, size: 70)
                
                // Статус растущая/убывающая
                Text(waxingWaning)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(widgetTheme.textColor.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(
                                waxingWaning == WidgetL10n.t("waxing") ?
                                Color.green.opacity(widgetTheme == .oceanLight ? 0.4 : 0.3) :
                                Color.blue.opacity(widgetTheme == .oceanLight ? 0.4 : 0.3)
                            )
                    )
            }
            
            // Правая часть - информация
            VStack(alignment: .leading, spacing: 6) {
                Text(WidgetL10n.t("lunar_day"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(widgetTheme.textColor.opacity(0.8))
                
                Text("\(String(format: "%.1f", entry.result.age))")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(widgetTheme.textColor)
                
                Divider()
                    .background(widgetTheme.textColor.opacity(0.3))
                
                Text(WidgetL10n.t("illumination"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(widgetTheme.textColor.opacity(0.8))
                
                Text("\(Int(entry.result.illumination * 100))%")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(widgetTheme.textColor)
                
                Divider()
                    .background(widgetTheme.textColor.opacity(0.3))
                
                Text(WidgetL10n.t("phase"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(widgetTheme.textColor.opacity(0.8))
                
                Text(entry.result.phaseName ?? WidgetL10n.t("moon"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(widgetTheme.textColor.opacity(0.9))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            
            Spacer()
        }
        .padding(16)
        .containerBackground(for: .widget) {
            LinearGradient(
                gradient: Gradient(colors: widgetTheme.gradientColors),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct LargeMoonWidget: View {
    var entry: MoonPhaseEntry
    private let widgetTheme = WidgetThemeHelper.currentTheme()
    
    private var waxingWaning: String {
        entry.result.phase <= 0.5 ? WidgetL10n.t("waxing") : WidgetL10n.t("waning")
    }
    
    private func daysUntilNextPhase() -> Int {
        guard let nextPhaseDate = entry.result.moonrise else { return 0 }
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: nextPhaseDate)
        return max(components.day ?? 0, 0)
    }
    
    var body: some View {
        VStack(spacing: 10) {
            // Заголовок - УВЕЛИЧИВАЕМ ПРОСТРАНСТВО ДЛЯ ТЕКСТА
            HStack {
                Text(WidgetL10n.t("moon_phase"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(widgetTheme.textColor)
                Spacer(minLength: 2)
                Text(entry.result.phaseName ?? WidgetL10n.t("moon"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(widgetTheme.textColor.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .padding(.horizontal, 2)
            
            // Основной контент
            HStack(spacing: 12) {
                // Левая часть - большая луна
                VStack(spacing: 8) {
                    RealMoonView(phase: entry.result.phase, size: 90)
                    
                    // Статус и прогресс
                    VStack(spacing: 4) {
                        Text(waxingWaning)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(widgetTheme.textColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(
                                        waxingWaning == WidgetL10n.t("waxing") ?
                                        Color.green.opacity(widgetTheme == .oceanLight ? 0.4 : 0.3) :
                                        Color.blue.opacity(widgetTheme == .oceanLight ? 0.4 : 0.3)
                                    )
                            )
                        
                        // Прогресс-бар фазы
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Фон прогресс-бара
                                Capsule()
                                    .fill(widgetTheme.textColor.opacity(0.2))
                                    .frame(height: 4)
                                
                                // Заполнение
                                Capsule()
                                    .fill(widgetTheme.accentColor)
                                    .frame(width: geometry.size.width * CGFloat(entry.result.phase), height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                }
                .frame(width: 100)
                
                // Правая часть - детальная информация
                VStack(alignment: .leading, spacing: 8) {
                    // Лунные сутки и освещение
                    InfoRow(
                        title: WidgetL10n.t("lunar_day"),
                        value: "\(String(format: "%.1f", entry.result.age))",
                        theme: widgetTheme
                    )
                    
                    InfoRow(
                        title: WidgetL10n.t("illumination"),
                        value: "\(Int(entry.result.illumination * 100))%",
                        theme: widgetTheme
                    )
                    
                    // Расстояние
                    if let distance = entry.result.distanceKm {
                        DistanceRow(
                            title: WidgetL10n.t("distance"),
                            value: "\(Int(distance))",
                            unit: "km",
                            theme: widgetTheme
                        )
                    }
                    
                    Divider()
                        .background(widgetTheme.textColor.opacity(0.3))
                    
                    // Следующая фаза
                    VStack(alignment: .leading, spacing: 4) {
                        Text(WidgetL10n.t("next_phase"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(widgetTheme.textColor.opacity(0.8))
                        
                        HStack {
                            Text(WidgetL10n.phaseName(for: getNextPhase(current: entry.result.phase)))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(widgetTheme.textColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            
                            Spacer()
                            
                            Text("\(daysUntilNextPhase()) \(WidgetL10n.t("in_days"))")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(widgetTheme.textColor.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                    
                    // Дополнительная информация
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Растущая")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(widgetTheme.textColor.opacity(0.6))
                                Text("\(getWaxingDays())д")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(widgetTheme.textColor)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Убывающая")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(widgetTheme.textColor.opacity(0.6))
                                Text("\(getWaningDays())д")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(widgetTheme.textColor)
                            }
                            
                            Spacer()
                        }
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Цикл")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(widgetTheme.textColor.opacity(0.6))
                                Text("29.5д")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(widgetTheme.textColor)
                            }
                            
                            Spacer()
                        }
                    }
                    .padding(.top, 2)
                }
            }
            
            // Нижняя часть - дата и время
            HStack {
                Text(formattedDate())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(widgetTheme.textColor.opacity(0.7))
                
                Spacer()
                
                Text(formattedTime())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(widgetTheme.textColor.opacity(0.7))
            }
            .padding(.top, 2)
        }
        .padding(16)
        .containerBackground(for: .widget) {
            LinearGradient(
                gradient: Gradient(colors: widgetTheme.gradientColors),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    private func InfoRow(title: String, value: String, theme: WidgetTheme) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.textColor.opacity(0.8))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(theme.textColor)
        }
    }
    
    private func DistanceRow(title: String, value: String, unit: String, theme: WidgetTheme) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.textColor.opacity(0.8))
                Spacer()
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(theme.textColor)
            }
            Text(unit)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(theme.textColor.opacity(0.6))
        }
    }
    
    private func getNextPhase(current: Double) -> Double {
        if current < 0.25 { return 0.25 }
        else if current < 0.5 { return 0.5 }
        else if current < 0.75 { return 0.75 }
        else { return 1.0 }
    }
    
    private func getWaxingDays() -> Int {
        if entry.result.phase <= 0.5 {
            return Int((0.5 - entry.result.phase) * 29.53 / 2)
        }
        return 0
    }
    
    private func getWaningDays() -> Int {
        if entry.result.phase > 0.5 {
            return Int((1.0 - entry.result.phase) * 29.53 / 2)
        }
        return Int((1.0 - 0.5) * 29.53 / 2)
    }
    
    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy"
        formatter.locale = Locale(identifier: WidgetL10n.currentLanguage() == "ru" ? "ru_RU" : "en_US")
        return formatter.string(from: entry.date)
    }
    
    private func formattedTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: entry.date)
    }
}

// MARK: - Widget Configuration
struct MoonPhaseWidget: Widget {
    let kind: String = "MoonPhaseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MoonPhaseWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Moon Phase")
        .description("Shows current moon phase, lunar day and illumination.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Widget Bundle
@main
struct MoonPhaseWidgetBundle: WidgetBundle {
    var body: some Widget {
        MoonPhaseWidget()
    }
}
