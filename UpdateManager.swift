import Foundation
import AppKit

class UpdateManager: NSObject, ObservableObject {
    static let shared = UpdateManager()
    
    override private init() {
        super.init()
        // Automatically check silently on launch
        checkForUpdates(silent: true)
    }
    
    @Published var currentVersion: String = {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.7.0"
    }()
    
    @Published var latestVersion: String? = nil
    @Published var releaseNotes: String? = nil
    @Published var downloadURL: String? = nil
    @Published var htmlURL: String? = nil
    
    @Published var isChecking: Bool = false
    @Published var checkError: String? = nil
    
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadError: String? = nil
    
    var hasUpdate: Bool {
        guard let latest = latestVersion else { return false }
        return compareVersions(latest, currentVersion) > 0
    }
    
    var shouldShowRedDot: Bool {
        guard let latest = latestVersion, hasUpdate else { return false }
        let skipped = UserDefaults.standard.string(forKey: "skippedVersion") ?? ""
        return latest != skipped
    }
    
    func skipVersion() {
        if let latest = latestVersion {
            UserDefaults.standard.set(latest, forKey: "skippedVersion")
            objectWillChange.send()
        }
    }
    
    func resetSkippedVersion() {
        UserDefaults.standard.removeObject(forKey: "skippedVersion")
        objectWillChange.send()
        checkForUpdates(silent: true)
    }
    
    // Compare version strings (e.g. "1.5.2" vs "1.5.1")
    // Returns 1 if v1 > v2, -1 if v1 < v2, 0 if v1 == v2
    private func compareVersions(_ v1: String, _ v2: String) -> Int {
        let cleanV1 = v1.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let cleanV2 = v2.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        
        let components1 = cleanV1.split(separator: ".").compactMap { Int($0) }
        let components2 = cleanV2.split(separator: ".").compactMap { Int($0) }
        
        let count = max(components1.count, components2.count)
        for i in 0..<count {
            let num1 = i < components1.count ? components1[i] : 0
            let num2 = i < components2.count ? components2[i] : 0
            
            if num1 > num2 {
                return 1
            } else if num1 < num2 {
                return -1
            }
        }
        return 0
    }
    
    func checkForUpdates(silent: Bool = false, completion: ((Bool) -> Void)? = nil) {
        guard !isChecking else { return }
        
        DispatchQueue.main.async {
            self.isChecking = true
            self.checkError = nil
        }
        
        let urlString = "https://api.github.com/repos/HuangLonghlhlhlhlhlhlhl/multitool/releases/latest"
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.isChecking = false
                self.checkError = "链接格式错误"
                completion?(false)
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("STATUS-CTRL-Updater", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15.0
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            defer {
                DispatchQueue.main.async {
                    self.isChecking = false
                }
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.checkError = error.localizedDescription
                    completion?(false)
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self.checkError = "未收到有效数据"
                    completion?(false)
                }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    // Check for rate limit or API error
                    if let message = json["message"] as? String, message.contains("rate limit") {
                        DispatchQueue.main.async {
                            self.checkError = "GitHub API 访问速率受限，请稍后再试"
                            completion?(false)
                        }
                        return
                    }
                    
                    let tagName = json["tag_name"] as? String ?? ""
                    let body = json["body"] as? String ?? ""
                    let htmlUrl = json["html_url"] as? String ?? ""
                    
                    var dmgUrl: String? = nil
                    if let assets = json["assets"] as? [[String: Any]] {
                        for asset in assets {
                            if let name = asset["name"] as? String, name.lowercased().hasSuffix(".dmg") {
                                dmgUrl = asset["browser_download_url"] as? String
                                break
                            }
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.latestVersion = tagName
                        self.releaseNotes = body
                        self.htmlURL = htmlUrl
                        self.downloadURL = dmgUrl
                        
                        NotificationCenter.default.post(name: NSNotification.Name("UpdateStatusChanged"), object: nil)
                        
                        completion?(self.hasUpdate)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.checkError = "解析 JSON 失败"
                        completion?(false)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.checkError = "解析 JSON 发生错误: \(error.localizedDescription)"
                    completion?(false)
                }
            }
        }
        task.resume()
    }
    
    // Download and open the DMG
    private var downloadTask: URLSessionDownloadTask?
    
    func startDownload() {
        guard let urlString = downloadURL, let url = URL(string: urlString) else {
            // Fallback to opening release html page if no dmg is found
            openReleasePage()
            return
        }
        
        guard !isDownloading else { return }
        
        DispatchQueue.main.async {
            self.isDownloading = true
            self.downloadProgress = 0.0
            self.downloadError = nil
        }
        
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        self.downloadTask = task
        task.resume()
    }
    
    func cancelDownload() {
        downloadTask?.cancel()
        DispatchQueue.main.async {
            self.isDownloading = false
            self.downloadProgress = 0.0
        }
    }
    
    func openReleasePage() {
        let urlStr = htmlURL ?? "https://github.com/HuangLonghlhlhlhlhlhlhl/multitool/releases/latest"
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }
}

extension UpdateManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async {
            self.downloadProgress = progress
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        defer {
            DispatchQueue.main.async {
                self.isDownloading = false
            }
        }
        
        // Save file in temporary directory as a .dmg file
        let tempDir = FileManager.default.temporaryDirectory
        let destinationURL = tempDir.appendingPathComponent("STATUS_CTRL_Update.dmg")
        
        try? FileManager.default.removeItem(at: destinationURL)
        
        do {
            try FileManager.default.moveItem(at: location, to: destinationURL)
            
            DispatchQueue.main.async {
                // Open the DMG file automatically
                NSWorkspace.shared.open(destinationURL)
            }
        } catch {
            DispatchQueue.main.async {
                self.downloadError = "安装包重命名/移动失败: \(error.localizedDescription)"
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.isDownloading = false
                self.downloadError = error.localizedDescription
            }
        }
    }
}
