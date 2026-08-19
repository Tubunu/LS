import SwiftUI

@main
struct LongScreenshotApp: App {
    @AppStorage(AppSettings.appThemeKey) private var appThemeRaw: String = AppSettings.defaultTheme.rawValue
    
    init() {
        ImageExporter.cleanupTemporaryFiles()
    }
    
    private var colorScheme: ColorScheme? {
        (AppTheme(rawValue: appThemeRaw) ?? .system).colorScheme
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(colorScheme)
        }
    }
}
