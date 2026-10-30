import Foundation
import AppKit

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published var isChecking: Bool = false
    @Published var latestVersion: String?
    @Published var hasUpdate: Bool = false
    @Published var releaseNotes: String?
    @Published var releaseURL: URL?
    @Published var checkMessage: String?

    // GitHub repository endpoint
    let repoOwner = "Minato-chen"
    let repoName = "ChestDock"

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var repoWebURL: URL {
        URL(string: "https://github.com/\(repoOwner)/\(repoName)")!
    }

    var releasesWebURL: URL {
        URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases")!
    }

    private init() {}

    func checkForUpdates(isUserInitiated: Bool = false) {
        guard !isChecking else { return }
        isChecking = true
        checkMessage = nil

        let apiURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("ChestDock-App", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.finishCheck(message: "无法连接到服务器", isUserInitiated: isUserInitiated)
                    return
                }

                if httpResponse.statusCode == 404 {
                    self.finishCheck(message: "暂无已发布的版本", isUserInitiated: isUserInitiated)
                    return
                }

                guard httpResponse.statusCode == 200 else {
                    self.finishCheck(message: "检查失败 (HTTP \(httpResponse.statusCode))", isUserInitiated: isUserInitiated)
                    return
                }

                struct GitHubRelease: Decodable {
                    let tagName: String
                    let body: String?
                    let htmlUrl: String

                    enum CodingKeys: String, CodingKey {
                        case tagName = "tag_name"
                        case body
                        case htmlUrl = "html_url"
                    }
                }

                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                let rawTag = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                self.latestVersion = rawTag
                self.releaseNotes = release.body
                self.releaseURL = URL(string: release.htmlUrl)

                let isNewer = self.compareVersions(rawTag, self.currentVersion) > 0
                self.hasUpdate = isNewer

                if isNewer {
                    self.checkMessage = "发现新版本 v\(rawTag)！"
                    if isUserInitiated {
                        self.presentUpdateAlert(version: rawTag, notes: release.body, url: self.releaseURL)
                    }
                } else {
                    self.checkMessage = "当前已是最新版本 (v\(self.currentVersion))"
                }
                self.isChecking = false
            } catch {
                self.finishCheck(message: "检查更新失败: \(error.localizedDescription)", isUserInitiated: isUserInitiated)
            }
        }
    }

    private func finishCheck(message: String, isUserInitiated: Bool) {
        self.isChecking = false
        self.checkMessage = message
        if isUserInitiated {
            let alert = NSAlert()
            alert.messageText = "检查更新"
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    private func presentUpdateAlert(version: String, notes: String?, url: URL?) {
        let alert = NSAlert()
        alert.messageText = "发现 ChestDock 新版本 (v\(version))"
        alert.informativeText = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "点击前往下载最新版本。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "前往下载")
        alert.addButton(withTitle: "稍后再说")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = url ?? URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func compareVersions(_ v1: String, _ v2: String) -> Int {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }
        let maxCount = max(parts1.count, parts2.count)
        for i in 0..<maxCount {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 > p2 { return 1 }
            if p1 < p2 { return -1 }
        }
        return 0
    }
}
