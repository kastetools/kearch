import Foundation
import AppKit

/// 通过 GitHub Releases 检查/安装更新(参考 kaste 实现)。
/// 更新走 DMG:下载 → 挂载 → ditto 覆盖当前 .app → 重启。
enum UpdateChecker {
    static let repoOwner = "kastetools"
    static let repoName = "kearch"

    struct ReleaseInfo: Equatable {
        let tagName: String      // "v1.2.0"
        let version: String      // "1.2.0"
        let htmlURL: URL
        let dmgURL: URL?
    }

    enum UpdateError: LocalizedError {
        case noReleaseYet
        case badStatus(Int)
        case rateLimited(resetAt: Date?)
        case malformedResponse
        case noDMGAsset

        var errorDescription: String? {
            switch self {
            case .noReleaseYet:      return "仓库尚无发布版本。"
            case .badStatus(let c):  return "GitHub 返回 HTTP \(c)"
            case .rateLimited(let at):
                if let at {
                    let mins = max(1, Int(ceil(at.timeIntervalSinceNow / 60)))
                    return "GitHub API 限流,约 \(mins) 分钟后重试。"
                }
                return "GitHub API 限流,请稍后重试。"
            case .malformedResponse: return "GitHub 返回内容异常"
            case .noDMGAsset:        return "最新版本没有 DMG 附件"
            }
        }
    }

    // ETag 缓存:304 Not Modified 不计入匿名 60/小时 限流。
    private static let etagKey = "updateChecker.etag"
    private static let cachedReleaseKey = "updateChecker.cachedRelease"

    private static func loadCachedRelease() -> ReleaseInfo? {
        guard let data = UserDefaults.standard.data(forKey: cachedReleaseKey),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return parseRelease(from: json)
    }

    private static func saveCachedRelease(rawJSON: Data, etag: String?) {
        UserDefaults.standard.set(rawJSON, forKey: cachedReleaseKey)
        if let etag { UserDefaults.standard.set(etag, forKey: etagKey) }
    }

    private static func parseRelease(from json: [String: Any]) -> ReleaseInfo? {
        guard let tagName = json["tag_name"] as? String,
              let htmlURLString = json["html_url"] as? String,
              let htmlURL = URL(string: htmlURLString) else {
            return nil
        }
        let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmgURL = assets.compactMap { asset -> URL? in
            guard let name = asset["name"] as? String, name.hasSuffix(".dmg"),
                  let urlStr = asset["browser_download_url"] as? String else { return nil }
            return URL(string: urlStr)
        }.first
        return ReleaseInfo(tagName: tagName, version: version, htmlURL: htmlURL, dmgURL: dmgURL)
    }

    static func currentVersion() -> String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    /// remote 是否严格新于 local(点分整数比较,如 1.1.10 > 1.1.9)。
    static func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        let len = max(r.count, l.count)
        for i in 0..<len {
            let a = i < r.count ? r[i] : 0
            let b = i < l.count ? l[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    static func fetchLatest() async throws -> ReleaseInfo {
        let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.timeoutInterval = 15
        if let etag = UserDefaults.standard.string(forKey: etagKey) {
            req.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.malformedResponse }

        if http.statusCode == 304, let cached = loadCachedRelease() {
            return cached
        }
        if http.statusCode == 404 {
            throw UpdateError.noReleaseYet
        }
        if http.statusCode == 403 || http.statusCode == 429 {
            let resetAt = (http.value(forHTTPHeaderField: "x-ratelimit-reset")).flatMap(TimeInterval.init)
                .map { Date(timeIntervalSince1970: $0) }
            if let cached = loadCachedRelease() { return cached }
            throw UpdateError.rateLimited(resetAt: resetAt)
        }
        guard http.statusCode == 200 else { throw UpdateError.badStatus(http.statusCode) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let release = parseRelease(from: json) else {
            throw UpdateError.malformedResponse
        }
        saveCachedRelease(rawJSON: data,
                          etag: http.value(forHTTPHeaderField: "Etag") ?? http.value(forHTTPHeaderField: "ETag"))
        return release
    }

    /// 下载 DMG,交给一个分离的 shell 脚本:等待本进程退出 → 覆盖 .app → 重启。
    static func downloadAndInstall(_ release: ReleaseInfo) async throws {
        guard let dmgURL = release.dmgURL else { throw UpdateError.noDMGAsset }
        var req = URLRequest(url: dmgURL)
        req.timeoutInterval = 120
        let (tempLocal, _) = try await URLSession.shared.download(for: req)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kearch-\(release.version).dmg")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempLocal, to: dest)

        await MainActor.run {
            try? Self.runInstaller(dmgPath: dest.path)
        }
    }

    @MainActor
    private static func runInstaller(dmgPath: String) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kearch-installer-\(pid).sh")
        let currentBundle = Bundle.main.bundleURL.path

        let script = #"""
        #!/bin/bash
        PID="__PID__"
        DMG="__DMG__"
        DEST="__DEST__"
        LOG="/tmp/kearch-installer.log"

        exec >>"$LOG" 2>&1
        echo "---- $(date) installer start, pid=$PID, dmg=$DMG ----"

        for i in $(seq 1 60); do
          kill -0 "$PID" 2>/dev/null || break
          sleep 0.5
        done
        sleep 1

        MOUNT_OUT=$(/usr/bin/hdiutil attach "$DMG" -nobrowse 2>&1)
        VOLUME=$(echo "$MOUNT_OUT" | /usr/bin/awk -F'\t' '/\/Volumes\// {print $NF}' | /usr/bin/tail -1)
        if [ -z "$VOLUME" ] || [ ! -d "$VOLUME/Kearch.app" ]; then
          echo "Mount failed or no Kearch.app on volume"
          echo "$MOUNT_OUT"
          exit 1
        fi

        if ! /usr/bin/ditto "$VOLUME/Kearch.app" "$DEST"; then
          echo "ditto failed — $DEST likely not writable"
          /usr/bin/hdiutil detach "$VOLUME" -quiet
          MARKER="$HOME/Desktop/Kearch-update-FAILED.txt"
          {
            echo "Kearch 自动更新失败。"
            echo ""
            echo "原因:无法写入 $DEST"
            echo "已下载的 DMG 保留在:$DMG"
            echo ""
            echo "手动修复:打开 DMG,把 Kearch.app 拖到可写的 Applications 目录。"
          } > "$MARKER"
          /usr/bin/open -R "$DMG"
          exit 1
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

        /usr/bin/hdiutil detach "$VOLUME" -quiet || true
        /bin/rm -f "$DMG"

        /usr/bin/open "$DEST"
        /bin/rm -- "$0"
        """#
        .replacingOccurrences(of: "__PID__", with: "\(pid)")
        .replacingOccurrences(of: "__DMG__", with: dmgPath)
        .replacingOccurrences(of: "__DEST__", with: currentBundle)

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: scriptURL.path)

        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "nohup \"\(scriptURL.path)\" </dev/null >/dev/null 2>&1 &"]
        try task.run()
        task.waitUntilExit()

        NSApp.terminate(nil)
    }
}
