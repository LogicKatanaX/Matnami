import UIKit

public final class TabBarController: UITabBarController {

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupTabs()
    }

    private func setupTabs() {
        // Tab 1: Catalog
        let catalogVC = CatalogViewController()
        let catalogNav = UINavigationController(rootViewController: catalogVC)
        catalogNav.tabBarItem = UITabBarItem(
            title: "Catalog",
            image: createTabIcon(text: "📺"),
            selectedImage: nil
        )

        // Tab 2: Search
        let searchVC = SearchViewController()
        let searchNav = UINavigationController(rootViewController: searchVC)
        searchNav.tabBarItem = UITabBarItem(
            title: "Search",
            image: createTabIcon(text: "🔍"),
            selectedImage: nil
        )

        // Tab 3: Downloads
        let downloadsVC = DownloadsViewController()
        let downloadsNav = UINavigationController(rootViewController: downloadsVC)
        downloadsNav.tabBarItem = UITabBarItem(
            title: "Downloads",
            image: createTabIcon(text: "⬇️"),
            selectedImage: nil
        )

        // Tab 4: Settings
        let settingsVC = SettingsViewController(style: .grouped)
        let settingsNav = UINavigationController(rootViewController: settingsVC)
        settingsNav.tabBarItem = UITabBarItem(
            title: "Settings",
            image: createTabIcon(text: "⚙️"),
            selectedImage: nil
        )

        viewControllers = [catalogNav, searchNav, downloadsNav, settingsNav]
    }

    /// Generates a simple, crisp glyph icon for UITabBarItem on iOS 12
    private func createTabIcon(text: String) -> UIImage? {
        let size = CGSize(width: 30, height: 30)
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        let rect = CGRect(origin: .zero, size: size)
        let font = UIFont.systemFont(ofSize: 22)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let textRect = CGRect(
            x: (size.width - textSize.width) / 2.0,
            y: (size.height - textSize.height) / 2.0,
            width: textSize.width,
            height: textSize.height
        )
        (text as NSString).draw(in: textRect, withAttributes: attributes)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image?.withRenderingMode(.alwaysOriginal)
    }
}
