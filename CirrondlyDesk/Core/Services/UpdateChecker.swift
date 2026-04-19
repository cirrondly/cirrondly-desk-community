import Foundation

@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var availableVersion: String?

    private let latestReleaseURL = URL(string: "https://api.github.com/repos/cirrondly/cirrondly-desk/releases/latest")!

    func checkForUpdatesIfNeeded() async {
        let defaults = UserDefaults.standard
        let lastCheck = defaults.object(forKey: "updates.lastCheck") as? Date
        if let lastCheck, Date().timeIntervalSince(lastCheck) < 86_400 {
            availableVersion = defaults.string(forKey: "updates.availableVersion")
            return
        }

        do {
            var request = URLRequest(url: latestReleaseURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let latest = json?["tag_name"] as? String
            defaults.set(Date(), forKey: "updates.lastCheck")
            defaults.set(latest, forKey: "updates.availableVersion")
            availableVersion = latest
        } catch {
            return
        }
    }
}