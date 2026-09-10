import UIKit

public struct AppTheme {
    public static let background = UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1.0)
    public static let secondaryBackground = UIColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
    public static let cardBackground = UIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1.0)
    public static let primaryAccent = UIColor(red: 0.98, green: 0.32, blue: 0.28, alpha: 1.0) // Vibrant Coral/Red
    public static let secondaryAccent = UIColor(red: 0.20, green: 0.60, blue: 0.95, alpha: 1.0)
    public static let textPrimary = UIColor.white
    public static let textSecondary = UIColor(white: 0.65, alpha: 1.0)
    public static let textTertiary = UIColor(white: 0.45, alpha: 1.0)
    public static let separator = UIColor(white: 0.22, alpha: 1.0)
    public static let success = UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1.0)

    public static func applyGlobalAppearance() {
        // Tab Bar
        UITabBar.appearance().barTintColor = AppTheme.background
        UITabBar.appearance().tintColor = AppTheme.primaryAccent
        UITabBar.appearance().unselectedItemTintColor = AppTheme.textSecondary
        UITabBar.appearance().isTranslucent = false

        // Navigation Bar
        UINavigationBar.appearance().barTintColor = AppTheme.background
        UINavigationBar.appearance().tintColor = AppTheme.primaryAccent
        UINavigationBar.appearance().titleTextAttributes = [
            .foregroundColor: AppTheme.textPrimary,
            .font: UIFont.systemFont(ofSize: 17, weight: .bold)
        ]
        UINavigationBar.appearance().isTranslucent = false
    }
}

