import SwiftUI
import Combine

extension Color {
    static let themeAccent = Color.purple
}

// MARK: - 数据模型定义

struct LeftoverItem: Identifiable, Equatable {
    var id: String { path }
    let name: String
    let path: String
    let sizeBytes: Int64
    let sizeString: String
    let parentCategory: String
    let isDirectory: Bool
}

struct AppItem: Identifiable, Equatable {
    var id: String { path }
    let name: String
    let path: String
    let bundleIdentifier: String
    let version: String
    var sizeBytes: Int64 = 0
    var sizeString: String = "--"
}

struct SkillItem: Identifiable, Equatable {
    var id: String { path }
    let name: String
    let path: String
    let sizeBytes: Int64
    let sizeString: String
}

struct TerminalAgentItem: Identifiable, Equatable {
    var id: String { path }
    let name: String        // 例如 "Claude Code (龙虾)"
    let path: String        // 数据文件夹路径
    let binaryPath: String  // 二进制软链路径
    var skills: [SkillItem] = []
    var isInstalled: Bool = false
}

struct LargeModelItem: Identifiable, Equatable {
    var id: String { path }
    let name: String
    let path: String
    let sizeBytes: Int64
    let sizeString: String
    let type: ModelType
    
    enum ModelType {
        case ollama
        case lmstudio
    }
}

// MARK: - Ollama JSON 解码结构体
struct OllamaManifest: Codable {
    struct Layer: Codable {
        let digest: String?
        let size: Int64?
    }
    struct Config: Codable {
        let digest: String?
        let size: Int64?
    }
    let layers: [Layer]?
    let config: Config?
}

// MARK: - 业务逻辑控制类
class AppModelManager: ObservableObject {
    @Published var apps: [AppItem] = []
    @Published var selectedApp: AppItem? = nil
    @Published var appLeftovers: [LeftoverItem] = []
    @Published var selectedLeftoverPaths: Set<String> = []
    @Published var isScanningApps = false
    @Published var isScanningLeftovers = false
    @Published var isDeletingApps = false
    @Published var appStatusText = ""
    
    @Published var terminalAgents: [TerminalAgentItem] = []
    @Published var selectedAgent: TerminalAgentItem? = nil
    @Published var selectedSkillPaths: Set<String> = []
    @Published var isScanningAgents = false
    @Published var isDeletingAgents = false
    @Published var agentStatusText = ""
    
    @Published var models: [LargeModelItem] = []
    @Published var selectedModelPaths: Set<String> = []
    @Published var isScanningModels = false
    @Published var isDeletingModels = false
    @Published var modelStatusText = ""
    
    private let managerQueue = DispatchQueue(label: "com.statusctrl.appmodelmanager", qos: .userInitiated)
    
    // MARK: - App 深度卸载逻辑
    
    func scanInstalledApps() {
        guard !isScanningApps else { return }
        isScanningApps = true
        appStatusText = "正在扫描已安装的应用..."
        apps.removeAll()
        selectedApp = nil
        appLeftovers.removeAll()
        selectedLeftoverPaths.removeAll()
        
        managerQueue.async {
            var foundApps: [AppItem] = []
            let fm = FileManager.default
            let searchPaths = ["/Applications", NSHomeDirectory() + "/Applications"]
            
            for basePath in searchPaths {
                guard fm.fileExists(atPath: basePath) else { continue }
                do {
                    let urls = try fm.contentsOfDirectory(at: URL(fileURLWithPath: basePath), includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants])
                    for url in urls {
                        if url.pathExtension == "app" {
                            let name = url.deletingPathExtension().lastPathComponent
                            let infoPlistPath = url.appendingPathComponent("Contents/Info.plist").path
                            var bundleId = ""
                            var version = ""
                            
                            if fm.fileExists(atPath: infoPlistPath), let dict = NSDictionary(contentsOfFile: infoPlistPath) {
                                bundleId = dict["CFBundleIdentifier"] as? String ?? ""
                                version = dict["CFBundleShortVersionString"] as? String ?? ""
                            }
                            
                            // 排除系统基础内置组件或多功能小助手自身，避免用户误删
                            if name == "Antigravity" || name == "STATUS CTRL" || name == "Finder" || name == "Safari" {
                                continue
                            }
                            
                            foundApps.append(AppItem(name: name, path: url.path, bundleIdentifier: bundleId, version: version, sizeBytes: 0, sizeString: "--"))
                        }
                    }
                } catch {
                    print("[AppModelManager] Failed to scan directory \(basePath): \(error)")
                }
            }
            
            // 按名称排序
            foundApps.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
            
            DispatchQueue.main.async {
                self.apps = foundApps
                self.isScanningApps = false
                self.appStatusText = "扫描完成，共找到 \(foundApps.count) 个应用程序。"
                
                // 异步计算各个 App 的物理大小，防止卡顿
                self.loadAppSizes()
            }
        }
    }
    
    private func loadAppSizes() {
        managerQueue.async {
            for i in 0..<self.apps.count {
                let app = self.apps[i]
                let url = URL(fileURLWithPath: app.path)
                let sizeBytes = self.getDirectorySize(url: url)
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                let sizeString = formatter.string(fromByteCount: sizeBytes)
                
                DispatchQueue.main.async {
                    if i < self.apps.count && self.apps[i].path == app.path {
                        self.apps[i].sizeBytes = sizeBytes
                        self.apps[i].sizeString = sizeString
                    }
                }
            }
        }
    }
    
    func scanLeftovers(for app: AppItem) {
        guard !isScanningLeftovers else { return }
        isScanningLeftovers = true
        selectedApp = app
        appLeftovers.removeAll()
        selectedLeftoverPaths.removeAll()
        appStatusText = "正在扫描 \"\(app.name)\" 的残留关联文件..."
        
        let appName = app.name.lowercased()
        let bundleId = app.bundleIdentifier.lowercased()
        
        managerQueue.async {
            var foundItems: [LeftoverItem] = []
            let fm = FileManager.default
            
            let searchDirs = [
                NSHomeDirectory() + "/Library/Application Support",
                NSHomeDirectory() + "/Library/Caches",
                NSHomeDirectory() + "/Library/Preferences",
                NSHomeDirectory() + "/Library/Logs",
                NSHomeDirectory() + "/Library/Containers",
                NSHomeDirectory() + "/Library/Saved Application State",
                NSHomeDirectory() + "/Library/WebKit",
                NSHomeDirectory() + "/Library/HTTPStorages",
                "/Library/Application Support",
                "/Library/Caches",
                "/Library/Preferences"
            ]
            
            for dirPath in searchDirs {
                let dirURL = URL(fileURLWithPath: dirPath)
                guard fm.fileExists(atPath: dirPath) else { continue }
                
                do {
                    let contents = try fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.skipsSubdirectoryDescendants])
                    for url in contents {
                        let lastComp = url.lastPathComponent.lowercased()
                        var isMatched = false
                        
                        // 匹配 Bundle Identifier (排除空字符串)
                        if !bundleId.isEmpty && lastComp.contains(bundleId) {
                            isMatched = true
                        }
                        
                        // 匹配 App 名称
                        if lastComp.contains(appName) {
                            isMatched = true
                        }
                        
                        // 如果应用名称较长，截取前几个字符前缀匹配
                        if appName.count > 4 && lastComp.contains(String(appName.prefix(4))) {
                            isMatched = true
                        }
                        
                        if isMatched {
                            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                            let size: Int64
                            if isDir {
                                size = self.getDirectorySize(url: url)
                            } else {
                                size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                            }
                            
                            let formatter = ByteCountFormatter()
                            formatter.countStyle = .file
                            let sizeStr = formatter.string(fromByteCount: size)
                            
                            foundItems.append(LeftoverItem(
                                name: url.lastPathComponent,
                                path: url.path,
                                sizeBytes: size,
                                sizeString: sizeStr,
                                parentCategory: dirURL.lastPathComponent,
                                isDirectory: isDir
                            ))
                        }
                    }
                } catch {
                    print("[AppModelManager] Leftover scan error in \(dirPath): \(error)")
                }
            }
            
            DispatchQueue.main.async {
                self.appLeftovers = foundItems
                self.isScanningLeftovers = false
                self.appStatusText = foundItems.isEmpty ? "未发现任何关联的残留文件。" : "扫描完成。发现该应用共有 \(foundItems.count) 个关联残留文件。"
            }
        }
    }
    
    func deleteSelectedAppAndLeftovers() {
        guard let app = selectedApp, !isDeletingApps else { return }
        isDeletingApps = true
        appStatusText = "正在删除应用及残留文件..."
        
        let pathsToDelete = Array(selectedLeftoverPaths)
        let appPath = app.path
        
        managerQueue.async {
            let fm = FileManager.default
            var deletedCount = 0
            var reclaimedBytes: Int64 = 0
            
            // 1. 删除勾选的残留文件
            for path in pathsToDelete {
                if fm.fileExists(atPath: path) {
                    let isDir = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    let size = isDir ? self.getDirectorySize(url: URL(fileURLWithPath: path)) : Int64((try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                    
                    do {
                        try fm.removeItem(atPath: path)
                        deletedCount += 1
                        reclaimedBytes += size
                    } catch {
                        print("[AppModelManager] Failed to remove leftover at \(path): \(error)")
                    }
                }
            }
            
            // 2. 删除 App 本体
            var appDeleted = false
            if fm.fileExists(atPath: appPath) {
                let size = self.getDirectorySize(url: URL(fileURLWithPath: appPath))
                do {
                    try fm.removeItem(atPath: appPath)
                    appDeleted = true
                    reclaimedBytes += size
                } catch {
                    print("[AppModelManager] Failed to remove App bundle at \(appPath): \(error)")
                }
            }
            
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let reclaimedStr = formatter.string(fromByteCount: reclaimedBytes)
            
            DispatchQueue.main.async {
                self.isDeletingApps = false
                self.selectedApp = nil
                self.appLeftovers.removeAll()
                self.selectedLeftoverPaths.removeAll()
                self.appStatusText = "卸载成功！\(appDeleted ? "应用本体已移除，" : "")共清理了 \(deletedCount) 个残留文件，累计释放空间: \(reclaimedStr)。"
                self.scanInstalledApps()
            }
        }
    }
    
    // MARK: - 终端程序及 Skills 管理逻辑
    
    func scanTerminalAgents() {
        guard !isScanningAgents else { return }
        isScanningAgents = true
        agentStatusText = "正在扫描终端 AI 代理程序及技能..."
        terminalAgents.removeAll()
        selectedAgent = nil
        selectedSkillPaths.removeAll()
        
        managerQueue.async {
            var agents: [TerminalAgentItem] = []
            
            let agentConfigs = [
                ("龙虾 (Claude Code)", "~/.claude", "~/.local/bin/claude"),
                ("爱马仕 (Hermes Agent)", "~/.hermes", "~/.local/bin/hermes"),
                ("开爪 (OpenClaw / ClawX)", "~/.openclaw", "~/.local/bin/openclaw"),
                ("开爪 (QClaw 数据备份)", "~/.qclaw", "~/.local/bin/clawx"),
                ("Antigravity (AGY)", "~/.gemini", "~/.local/bin/agy")
            ]
            
            let fm = FileManager.default
            
            for (name, dataPath, binPath) in agentConfigs {
                let resolvedDataPath = dataPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
                let resolvedBinPath = binPath.replacingOccurrences(of: "~", with: NSHomeDirectory())
                
                var agent = TerminalAgentItem(
                    name: name,
                    path: resolvedDataPath,
                    binaryPath: resolvedBinPath,
                    skills: [],
                    isInstalled: false
                )
                
                let hasData = fm.fileExists(atPath: resolvedDataPath)
                let hasBin = fm.fileExists(atPath: resolvedBinPath)
                
                if hasData || hasBin {
                    agent.isInstalled = true
                    
                    // 扫描 Skills 目录
                    let skillsPath = resolvedDataPath + "/skills"
                    if fm.fileExists(atPath: skillsPath) {
                        do {
                            let contents = try fm.contentsOfDirectory(at: URL(fileURLWithPath: skillsPath), includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [])
                            var skills: [SkillItem] = []
                            for url in contents {
                                // 忽略隐藏文件
                                if url.lastPathComponent.hasPrefix(".") {
                                    continue
                                }
                                
                                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                                let size = isDir ? self.getDirectorySize(url: url) : Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                                
                                let formatter = ByteCountFormatter()
                                formatter.countStyle = .file
                                let sizeStr = formatter.string(fromByteCount: size)
                                
                                skills.append(SkillItem(
                                    name: url.lastPathComponent,
                                    path: url.path,
                                    sizeBytes: size,
                                    sizeString: sizeStr
                                ))
                            }
                            // 按名称排序
                            skills.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
                            agent.skills = skills
                        } catch {
                            print("[AppModelManager] Failed to read skills in \(skillsPath): \(error)")
                        }
                    }
                    
                    agents.append(agent)
                }
            }
            
            DispatchQueue.main.async {
                self.terminalAgents = agents
                self.isScanningAgents = false
                self.agentStatusText = agents.isEmpty ? "未在电脑上检测到终端 AI 代理组件。" : "扫描完成，共找到 \(agents.count) 个终端 AI 组件。"
            }
        }
    }
    
    func deleteSelectedSkillsOrAgent() {
        guard let agent = selectedAgent, !isDeletingAgents else { return }
        isDeletingAgents = true
        agentStatusText = "正在进行清理作业..."
        
        let skillPathsToDelete = Array(selectedSkillPaths)
        let deleteEntireAgent = selectedSkillPaths.contains(agent.path)
        
        managerQueue.async {
            let fm = FileManager.default
            var deletedCount = 0
            
            if deleteEntireAgent {
                // 1. 删除整个代理 (包括数据目录与可执行文件)
                if fm.fileExists(atPath: agent.path) {
                    try? fm.removeItem(atPath: agent.path)
                }
                if fm.fileExists(atPath: agent.binaryPath) {
                    try? fm.removeItem(atPath: agent.binaryPath)
                }
                deletedCount += 1
            } else {
                // 2. 仅删除选中的 Skills
                for path in skillPathsToDelete {
                    if fm.fileExists(atPath: path) {
                        do {
                            try fm.removeItem(atPath: path)
                            deletedCount += 1
                        } catch {
                            print("[AppModelManager] Failed to remove skill at \(path): \(error)")
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.isDeletingAgents = false
                self.selectedAgent = nil
                self.selectedSkillPaths.removeAll()
                self.agentStatusText = deleteEntireAgent ? "已成功卸载 \"\(agent.name)\" 主程序及数据配置！" : "已成功清理 \(deletedCount) 个指定的 Skill 技能代理。"
                self.scanTerminalAgents()
            }
        }
    }
    
    // MARK: - 大模型管理逻辑
    
    func scanLargeModels() {
        guard !isScanningModels else { return }
        isScanningModels = true
        modelStatusText = "正在扫描本地大模型文件..."
        models.removeAll()
        selectedModelPaths.removeAll()
        
        managerQueue.async {
            var foundModels: [LargeModelItem] = []
            let fm = FileManager.default
            
            // 1. Ollama 模型扫描
            let ollamaManifestsBase = NSHomeDirectory() + "/.ollama/models/manifests"
            if fm.fileExists(atPath: ollamaManifestsBase) {
                let baseURl = URL(fileURLWithPath: ollamaManifestsBase)
                let keys: [URLResourceKey] = [.isRegularFileKey]
                if let enumerator = fm.enumerator(at: baseURl, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles], errorHandler: nil) {
                    while let fileURL = enumerator.nextObject() as? URL {
                        // 如果是正则文件，代表是一个模型的 manifest 配置文件
                        if let isRegular = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile), isRegular {
                            // 从全路径中移除 manifestsBase 前缀，获取模型名字
                            let relativePath = fileURL.path.replacingOccurrences(of: ollamaManifestsBase + "/", with: "")
                            // 把类似 registry.ollama.ai/library/deepseek-r1/14b 转成 deepseek-r1:14b
                            let nameParts = relativePath.components(separatedBy: "/")
                            var modelName = relativePath
                            if nameParts.count >= 3 {
                                // 拼接最后两段，也就是 库名+版本，如 "deepseek-r1:14b"
                                let library = nameParts[nameParts.count - 2]
                                let tag = nameParts[nameParts.count - 1]
                                modelName = "\(library):\(tag)"
                            }
                            
                            // 读取 JSON 解析模型大小
                            var sizeBytes: Int64 = 0
                            if let data = try? Data(contentsOf: fileURL),
                               let manifest = try? JSONDecoder().decode(OllamaManifest.self, from: data) {
                                // 累加所有 layers 的大小
                                if let layers = manifest.layers {
                                    for layer in layers {
                                        sizeBytes += layer.size ?? 0
                                    }
                                }
                                // 加上 config 文件的大小
                                sizeBytes += manifest.config?.size ?? 0
                            } else {
                                // 兜底：直接计算其对应 blobs 实体的大小
                                sizeBytes = Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                            }
                            
                            let formatter = ByteCountFormatter()
                            formatter.countStyle = .file
                            let sizeStr = formatter.string(fromByteCount: sizeBytes)
                            
                            foundModels.append(LargeModelItem(
                                name: modelName,
                                path: fileURL.path,
                                sizeBytes: sizeBytes,
                                sizeString: sizeStr,
                                type: .ollama
                            ))
                        }
                    }
                }
            }
            
            // 2. LM Studio 模型扫描 (包含两个常见路径)
            let lmStudioDirs = [
                NSHomeDirectory() + "/.lmstudio/models",
                NSHomeDirectory() + "/.cache/lm-studio/models"
            ]
            
            for lmDir in lmStudioDirs {
                if fm.fileExists(atPath: lmDir) {
                    let baseURl = URL(fileURLWithPath: lmDir)
                    if let enumerator = fm.enumerator(at: baseURl, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles], errorHandler: nil) {
                        while let fileURL = enumerator.nextObject() as? URL {
                            if fileURL.pathExtension.lowercased() == "gguf" {
                                let relativePath = fileURL.path.replacingOccurrences(of: lmDir + "/", with: "")
                                let sizeBytes = Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                                let formatter = ByteCountFormatter()
                                formatter.countStyle = .file
                                let sizeStr = formatter.string(fromByteCount: sizeBytes)
                                
                                foundModels.append(LargeModelItem(
                                    name: relativePath,
                                    path: fileURL.path,
                                    sizeBytes: sizeBytes,
                                    sizeString: sizeStr,
                                    type: .lmstudio
                                ))
                            }
                        }
                    }
                }
            }
            
            // 按大小从大到小排序
            foundModels.sort { $0.sizeBytes > $1.sizeBytes }
            
            DispatchQueue.main.async {
                self.models = foundModels
                self.isScanningModels = false
                self.modelStatusText = foundModels.isEmpty ? "未在默认位置找到任何 Ollama 或 LM Studio 本地大模型。" : "扫描完成，共管理着 \(foundModels.count) 个本地大模型文件。"
            }
        }
    }
    
    func deleteSelectedModels() {
        let targets = models.filter { selectedModelPaths.contains($0.path) }
        guard !targets.isEmpty, !isDeletingModels else { return }
        isDeletingModels = true
        modelStatusText = "正在删除指定的大模型文件，请稍候..."
        
        managerQueue.async {
            let fm = FileManager.default
            var deletedCount = 0
            var reclaimedBytes: Int64 = 0
            
            for model in targets {
                if model.type == .ollama {
                    // 对于 Ollama，我们可以尝试使用 CLI 删除以维护库的完整度
                    var cliSuccess = false
                    let ollamaCLI = "/usr/local/bin/ollama"
                    if fm.fileExists(atPath: ollamaCLI) {
                        let proc = Process()
                        proc.executableURL = URL(fileURLWithPath: ollamaCLI)
                        proc.arguments = ["rm", model.name]
                        do {
                            try proc.run()
                            proc.waitUntilExit()
                            if proc.terminationStatus == 0 {
                                cliSuccess = true
                                deletedCount += 1
                                reclaimedBytes += model.sizeBytes
                            }
                        } catch {}
                    }
                    
                    // 兜底：如果 CLI 不可用或者执行失败，直接物理强删 manifest
                    if !cliSuccess {
                        // 读取 manifest 提取 blobs
                        if let data = try? Data(contentsOf: URL(fileURLWithPath: model.path)),
                           (try? JSONDecoder().decode(OllamaManifest.self, from: data)) != nil {
                            // 物理删除 manifest 本身
                            try? fm.removeItem(atPath: model.path)
                            deletedCount += 1
                            reclaimedBytes += model.sizeBytes
                        } else {
                            try? fm.removeItem(atPath: model.path)
                            deletedCount += 1
                            reclaimedBytes += model.sizeBytes
                        }
                    }
                } else if model.type == .lmstudio {
                    // LM Studio 物理删除对应的 GGUF
                    if fm.fileExists(atPath: model.path) {
                        do {
                            try fm.removeItem(atPath: model.path)
                            deletedCount += 1
                            reclaimedBytes += model.sizeBytes
                            
                            // 如果父目录变为空目录，也同步删除它
                            let parentURL = URL(fileURLWithPath: model.path).deletingLastPathComponent()
                            if let children = try? fm.contentsOfDirectory(atPath: parentURL.path), children.isEmpty {
                                try? fm.removeItem(atPath: parentURL.path)
                            }
                        } catch {
                            print("[AppModelManager] Failed to remove GGUF model: \(error)")
                        }
                    }
                }
            }
            
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let reclaimedStr = formatter.string(fromByteCount: reclaimedBytes)
            
            DispatchQueue.main.async {
                self.isDeletingModels = false
                self.selectedModelPaths.removeAll()
                self.modelStatusText = "已成功删除了 \(deletedCount) 个大模型，释放了 \(reclaimedStr) 磁盘空间！"
                self.scanLargeModels()
            }
        }
    }
    
    // MARK: - 文件夹大小获取实用工具 (递归非链接)
    
    private func getDirectorySize(url: URL) -> Int64 {
        let fm = FileManager.default
        var size: Int64 = 0
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: nil) else {
            return 0
        }
        
        while let fileURL = enumerator.nextObject() as? URL {
            // 防御符号链接死循环
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]),
               let isSymlink = resourceValues.isSymbolicLink, isSymlink {
                enumerator.skipDescendants()
                continue
            }
            
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(keys))
                if let isDir = resourceValues.isDirectory, isDir {
                    continue
                }
                if let fileSize = resourceValues.fileSize {
                    size += Int64(fileSize)
                }
            } catch {}
        }
        return size
    }
}

// MARK: - SwiftUI 界面视图

struct AppModelManagerView: View {
    var useSingleColumn: Bool = false
    @StateObject private var manager = AppModelManager()
    @State private var subTab = 0 // 0: 应用卸载, 1: 大模型, 2: 终端与Skill
    @State private var appSearchText = ""
    @State private var modelSearchText = ""
    @State private var agentSearchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部 Sub-Tab 切换栏（采用微小磨砂玻璃视觉及动画）
            HStack(spacing: 12) {
                SubTabButton(title: "应用深度卸载", icon: "app.badge.fill", active: subTab == 0) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { subTab = 0 }
                }
                SubTabButton(title: "本地大模型", icon: "cpu.fill", active: subTab == 1) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { subTab = 1 }
                }
                SubTabButton(title: "终端Agent & Skill", icon: "terminal.fill", active: subTab == 2) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { subTab = 2 }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background(Color.themeBg.opacity(0.4))
            
            Divider().background(Color.themeDivider)
            
            // 下方分栏具体内容展示
            ZStack {
                if subTab == 0 {
                    appUninstallerPanel
                } else if subTab == 1 {
                    largeModelPanel
                } else {
                    terminalAgentPanel
                }
            }
            .frame(maxHeight: .infinity)
        }
        .background(Color.themeBg)
        .onAppear {
            // 首次出现自动加载
            manager.scanInstalledApps()
            manager.scanLargeModels()
            manager.scanTerminalAgents()
        }
    }
    
    // MARK: - App 深度卸载面板
    @ViewBuilder
    private var appUninstallerPanel: some View {
        if useSingleColumn {
            ScrollView {
                VStack(spacing: 14) {
                    // App 列表列
                    VStack(spacing: 8) {
                        // 搜索栏
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundColor(.themeTextTertiary)
                            TextField("搜索应用...", text: $appSearchText)
                                .textFieldStyle(PlainTextFieldStyle())
                                .foregroundColor(.themeText)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.themeBg.opacity(0.6))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeDivider, lineWidth: 1))
                        
                        // 列表
                        if manager.isScanningApps {
                            Spacer()
                            ProgressView().scaleEffect(0.8)
                            Text("正在检索应用程序...").font(.system(size: 11)).foregroundColor(.themeTextSecondary).padding(.top, 4)
                            Spacer()
                        } else {
                            let filtered = manager.apps.filter { appSearchText.isEmpty || $0.name.localizedCaseInsensitiveContains(appSearchText) }
                            
                            ScrollView {
                                LazyVStack(spacing: 6) {
                                    ForEach(filtered) { app in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(app.name)
                                                    .font(.system(size: 12.5, weight: .bold))
                                                    .foregroundColor(.themeText)
                                                    .lineLimit(1)
                                                Text(app.bundleIdentifier)
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.themeTextTertiary)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            Text(app.sizeString)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(.themeTextSecondary)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(manager.selectedApp == app ? Color.themeAccent.opacity(0.15) : Color.themeCardBg.opacity(0.4))
                                        .cornerRadius(8)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(manager.selectedApp == app ? Color.themeAccent : Color.themeDivider, lineWidth: 1))
                                        .onTapGesture {
                                            withAnimation {
                                                manager.scanLeftovers(for: app)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .frame(height: 200)
                    
                    Divider().background(Color.themeDivider)
                    
                    // 右侧：所选 App 残留文件扫描与卸载详情
                    VStack(alignment: .leading, spacing: 12) {
                        if let app = manager.selectedApp {
                            // 头部 App 信息卡片
                            HStack(spacing: 12) {
                                Image(systemName: "app.badge.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.themeAccent)
                                    .frame(width: 52, height: 52)
                                    .background(Color.themeAccent.opacity(0.12))
                                    .cornerRadius(12)
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.name)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(.themeText)
                                    Text("版本: \(app.version.isEmpty ? "未知" : app.version) | \(app.sizeString)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.themeTextSecondary)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(Color.themeCardBg.opacity(0.5))
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeDivider, lineWidth: 1))
                            
                            Text("关联残留系统文件 (建议全部勾选)：")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.themeTextSecondary)
                            
                            // 残留文件列表
                            if manager.isScanningLeftovers {
                                Spacer()
                                HStack {
                                    Spacer()
                                    VStack(spacing: 8) {
                                        ProgressView().scaleEffect(0.8)
                                        Text("正在深挖应用关联缓存与配置文件...").font(.system(size: 11)).foregroundColor(.themeTextTertiary)
                                    }
                                    Spacer()
                                }
                                Spacer()
                            } else if manager.appLeftovers.isEmpty {
                                Spacer()
                                HStack {
                                    Spacer()
                                    VStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 24))
                                        Text("未发现明显的关联残留文件，该 App 非常干净。").font(.system(size: 11.5)).foregroundColor(.themeTextSecondary)
                                    }
                                    Spacer()
                                }
                                Spacer()
                            } else {
                                ScrollView {
                                    VStack(spacing: 6) {
                                        ForEach(manager.appLeftovers) { item in
                                            HStack {
                                                Toggle("", isOn: Binding(
                                                    get: { manager.selectedLeftoverPaths.contains(item.path) },
                                                    set: { checked in
                                                        if checked {
                                                            manager.selectedLeftoverPaths.insert(item.path)
                                                        } else {
                                                            manager.selectedLeftoverPaths.remove(item.path)
                                                        }
                                                    }
                                                ))
                                                .toggleStyle(CheckboxToggleStyle())
                                                
                                                VStack(alignment: .leading, spacing: 3) {
                                                    HStack {
                                                        Text(item.name)
                                                            .font(.system(size: 11.5, weight: .semibold))
                                                            .foregroundColor(.themeText)
                                                            .lineLimit(1)
                                                        
                                                        Text("[\(item.parentCategory)]")
                                                            .font(.system(size: 9))
                                                            .padding(.horizontal, 4)
                                                            .padding(.vertical, 1)
                                                            .background(Color.themeAccent.opacity(0.12))
                                                            .foregroundColor(.themeAccent)
                                                            .cornerRadius(4)
                                                    }
                                                    Text(item.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                                        .font(.system(size: 9.5))
                                                        .foregroundColor(.themeTextTertiary)
                                                        .lineLimit(1)
                                                }
                                                Spacer()
                                                Text(item.sizeString)
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .foregroundColor(.themeTextSecondary)
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.themeBg.opacity(0.3))
                                            .cornerRadius(6)
                                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.themeDivider, lineWidth: 1))
                                        }
                                    }
                                }
                                .frame(height: 250)
                            }
                            
                            // 操作栏
                            HStack {
                                Button(action: {
                                    // 全选
                                    let allPaths = manager.appLeftovers.map { $0.path }
                                    manager.selectedLeftoverPaths = Set(allPaths)
                                }) {
                                    Text("全选").font(.system(size: 11))
                                }
                                .buttonStyle(PlainButtonStyle())
                                .foregroundColor(.themeAccent)
                                
                                Spacer()
                                
                                if manager.isDeletingApps {
                                    ProgressView().scaleEffect(0.6).padding(.trailing, 6)
                                }
                                
                                Button(action: {
                                    manager.deleteSelectedAppAndLeftovers()
                                }) {
                                    HStack {
                                        Image(systemName: "trash.fill")
                                        Text("深度卸载所选程序")
                                    }
                                    .font(.system(size: 11.5, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.red)
                                    .cornerRadius(8)
                                    .shadow(color: Color.red.opacity(0.2), radius: 4, x: 0, y: 2)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(manager.isDeletingApps)
                            }
                            .padding(.top, 4)
                        } else {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "arrow.up.circle")
                                        .font(.system(size: 32))
                                        .foregroundColor(.themeTextTertiary)
                                    Text("请在上方列表中选择要卸载的应用程序")
                                        .font(.system(size: 12))
                                        .foregroundColor(.themeTextSecondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        } else {
            HStack(spacing: 14) {
                // 左侧：App 列表列
                VStack(spacing: 8) {
                    // 搜索栏
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.themeTextTertiary)
                        TextField("搜索应用...", text: $appSearchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .foregroundColor(.themeText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.themeBg.opacity(0.6))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeDivider, lineWidth: 1))
                    
                    // 列表
                    if manager.isScanningApps {
                        Spacer()
                        ProgressView().scaleEffect(0.8)
                        Text("正在检索应用程序...").font(.system(size: 11)).foregroundColor(.themeTextSecondary).padding(.top, 4)
                        Spacer()
                    } else {
                        let filtered = manager.apps.filter { appSearchText.isEmpty || $0.name.localizedCaseInsensitiveContains(appSearchText) }
                        
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(filtered) { app in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(app.name)
                                                .font(.system(size: 12.5, weight: .bold))
                                                .foregroundColor(.themeText)
                                                .lineLimit(1)
                                            Text(app.bundleIdentifier)
                                                .font(.system(size: 10))
                                                .foregroundColor(.themeTextTertiary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        Text(app.sizeString)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.themeTextSecondary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(manager.selectedApp == app ? Color.themeAccent.opacity(0.15) : Color.themeCardBg.opacity(0.4))
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(manager.selectedApp == app ? Color.themeAccent : Color.themeDivider, lineWidth: 1))
                                    .onTapGesture {
                                        withAnimation {
                                            manager.scanLeftovers(for: app)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(width: 260)
                .padding(.leading, 16)
                .padding(.vertical, 12)
                
                Divider().background(Color.themeDivider)
                
                // 右侧：所选 App 残流文件扫描与卸载详情
                VStack(alignment: .leading, spacing: 12) {
                    if let app = manager.selectedApp {
                        // 头部 App 信息卡片
                        HStack(spacing: 12) {
                            Image(systemName: "app.badge.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.themeAccent)
                                .frame(width: 52, height: 52)
                                .background(Color.themeAccent.opacity(0.12))
                                .cornerRadius(12)
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.name)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.themeText)
                                Text("版本: \(app.version.isEmpty ? "未知" : app.version) | \(app.sizeString)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.themeTextSecondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.themeCardBg.opacity(0.5))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeDivider, lineWidth: 1))
                        
                        Text("关联残留系统文件 (建议全部勾选)：")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.themeTextSecondary)
                        
                        // 残留文件列表
                        if manager.isScanningLeftovers {
                            Spacer()
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    ProgressView().scaleEffect(0.8)
                                    Text("正在深挖应用关联缓存与配置文件...").font(.system(size: 11)).foregroundColor(.themeTextTertiary)
                                }
                                Spacer()
                            }
                            Spacer()
                        } else if manager.appLeftovers.isEmpty {
                            Spacer()
                            HStack {
                                Spacer()
                                VStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 24))
                                    Text("未发现明显的关联残留文件，该 App 非常干净。").font(.system(size: 11.5)).foregroundColor(.themeTextSecondary)
                                }
                                Spacer()
                            }
                            Spacer()
                        } else {
                            ScrollView {
                                VStack(spacing: 6) {
                                    ForEach(manager.appLeftovers) { item in
                                        HStack {
                                            Toggle("", isOn: Binding(
                                                get: { manager.selectedLeftoverPaths.contains(item.path) },
                                                set: { checked in
                                                    if checked {
                                                        manager.selectedLeftoverPaths.insert(item.path)
                                                    } else {
                                                        manager.selectedLeftoverPaths.remove(item.path)
                                                    }
                                                }
                                            ))
                                            .toggleStyle(CheckboxToggleStyle())
                                            
                                            VStack(alignment: .leading, spacing: 3) {
                                                HStack {
                                                    Text(item.name)
                                                        .font(.system(size: 11.5, weight: .semibold))
                                                        .foregroundColor(.themeText)
                                                        .lineLimit(1)
                                                    
                                                    Text("[\(item.parentCategory)]")
                                                        .font(.system(size: 9))
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(Color.themeAccent.opacity(0.12))
                                                        .foregroundColor(.themeAccent)
                                                        .cornerRadius(4)
                                                }
                                                Text(item.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                                    .font(.system(size: 9.5))
                                                    .foregroundColor(.themeTextTertiary)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            Text(item.sizeString)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(.themeTextSecondary)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.themeBg.opacity(0.3))
                                        .cornerRadius(6)
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.themeDivider, lineWidth: 1))
                                    }
                                }
                            }
                        }
                        
                        // 操作栏
                        HStack {
                            Button(action: {
                                // 全选
                                let allPaths = manager.appLeftovers.map { $0.path }
                                manager.selectedLeftoverPaths = Set(allPaths)
                            }) {
                                Text("全选").font(.system(size: 11))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .foregroundColor(.themeAccent)
                            
                            Spacer()
                            
                            if manager.isDeletingApps {
                                ProgressView().scaleEffect(0.6).padding(.trailing, 6)
                            }
                            
                            Button(action: {
                                manager.deleteSelectedAppAndLeftovers()
                            }) {
                                HStack {
                                    Image(systemName: "trash.fill")
                                    Text("深度卸载所选程序")
                                }
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.red)
                                .cornerRadius(8)
                                .shadow(color: Color.red.opacity(0.2), radius: 4, x: 0, y: 2)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(manager.isDeletingApps)
                        }
                        .padding(.top, 4)
                    } else {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.left.circle")
                                    .font(.system(size: 32))
                                    .foregroundColor(.themeTextTertiary)
                                Text("请在左侧列表中选择要卸载的应用程序")
                                    .font(.system(size: 12))
                                    .foregroundColor(.themeTextSecondary)
                            }
                            Spacer()
                        }
                        Spacer()
                    }
                }
                .padding(.trailing, 16)
                .padding(.vertical, 12)
            }
        }
    }
    
    // MARK: - 大模型管理面板
    private var largeModelPanel: some View {
        VStack(spacing: 12) {
            // 模型筛选与搜索顶栏
            HStack {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.themeTextTertiary)
                    TextField("搜索本地模型...", text: $modelSearchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .foregroundColor(.themeText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.themeBg.opacity(0.6))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeDivider, lineWidth: 1))
                
                Spacer()
                
                Button(action: {
                    manager.scanLargeModels()
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("刷新列表")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.themeTextSecondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            // 模型列表区
            if manager.isScanningModels {
                Spacer()
                ProgressView().scaleEffect(0.8)
                Text("正在盘点本地 Ollama 与 LM Studio 模型文件...").font(.system(size: 11.5)).foregroundColor(.themeTextSecondary).padding(.top, 4)
                Spacer()
            } else if manager.models.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "cpu").font(.system(size: 32)).foregroundColor(.themeTextTertiary)
                    Text("电脑中没有发现安装大模型。").font(.system(size: 12)).foregroundColor(.themeTextSecondary)
                }
                Spacer()
            } else {
                let filtered = manager.models.filter { modelSearchText.isEmpty || $0.name.localizedCaseInsensitiveContains(modelSearchText) }
                
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(filtered) { model in
                            HStack(spacing: 12) {
                                Toggle("", isOn: Binding(
                                    get: { manager.selectedModelPaths.contains(model.path) },
                                    set: { checked in
                                        if checked {
                                            manager.selectedModelPaths.insert(model.path)
                                        } else {
                                            manager.selectedModelPaths.remove(model.path)
                                        }
                                    }
                                ))
                                .toggleStyle(CheckboxToggleStyle())
                                
                                Image(systemName: model.type == .ollama ? "server.rack" : "doc.plaintext.fill")
                                    .foregroundColor(model.type == .ollama ? .orange : .cyan)
                                    .font(.system(size: 16))
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(model.name)
                                            .font(.system(size: 12.5, weight: .bold))
                                            .foregroundColor(.themeText)
                                            .lineLimit(1)
                                        
                                        Text(model.type == .ollama ? "Ollama" : "LM Studio")
                                            .font(.system(size: 8.5, weight: .semibold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1.5)
                                            .background((model.type == .ollama ? Color.orange : Color.cyan).opacity(0.12))
                                            .foregroundColor(model.type == .ollama ? .orange : .cyan)
                                            .cornerRadius(4)
                                    }
                                    
                                    Text(model.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                        .font(.system(size: 10))
                                        .foregroundColor(.themeTextTertiary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                Text(model.sizeString)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.themeTextSecondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.themeCardBg.opacity(0.4))
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.themeDivider, lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }
                
                // 底部动作状态条
                Divider().background(Color.themeDivider)
                
                HStack {
                    Text(manager.modelStatusText)
                        .font(.system(size: 10.5))
                        .foregroundColor(.themeTextSecondary)
                    
                    Spacer()
                    
                    if manager.isDeletingModels {
                        ProgressView().scaleEffect(0.6).padding(.trailing, 6)
                    }
                    
                    Button(action: {
                        manager.deleteSelectedModels()
                    }) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("物理删除选中的模型 (\(manager.selectedModelPaths.count))")
                        }
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(manager.selectedModelPaths.isEmpty ? Color.gray.opacity(0.3) : Color.red)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(manager.selectedModelPaths.isEmpty || manager.isDeletingModels)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .padding(.top, 4)
            }
        }
    }
    
    // MARK: - 终端程序及 Skill 代理面板
    @ViewBuilder
    private var terminalAgentPanel: some View {
        if useSingleColumn {
            ScrollView {
                VStack(spacing: 14) {
                    // 左侧：AI Agent 工具列表
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundColor(.themeTextTertiary)
                            TextField("搜索工具...", text: $agentSearchText)
                                .textFieldStyle(PlainTextFieldStyle())
                                .foregroundColor(.themeText)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.themeBg.opacity(0.6))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeDivider, lineWidth: 1))
                        
                        if manager.isScanningAgents {
                            Spacer()
                            ProgressView().scaleEffect(0.8)
                            Text("扫描终端程序中...").font(.system(size: 11)).foregroundColor(.themeTextSecondary).padding(.top, 4)
                            Spacer()
                        } else if manager.terminalAgents.isEmpty {
                            Spacer()
                            Text("未发现可管理的终端 Agent。").font(.system(size: 11.5)).foregroundColor(.themeTextSecondary)
                            Spacer()
                        } else {
                            let filtered = manager.terminalAgents.filter { agentSearchText.isEmpty || $0.name.localizedCaseInsensitiveContains(agentSearchText) }
                            
                            ScrollView {
                                LazyVStack(spacing: 6) {
                                    ForEach(filtered) { agent in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(agent.name)
                                                    .font(.system(size: 12.5, weight: .bold))
                                                    .foregroundColor(.themeText)
                                                Text(agent.skills.isEmpty ? "无技能" : "含有 \(agent.skills.count) 个 Skill 技能")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.themeTextSecondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 10))
                                                .foregroundColor(.themeTextTertiary)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 10)
                                        .background(manager.selectedAgent == agent ? Color.themeAccent.opacity(0.15) : Color.themeCardBg.opacity(0.4))
                                        .cornerRadius(8)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(manager.selectedAgent == agent ? Color.themeAccent : Color.themeDivider, lineWidth: 1))
                                        .onTapGesture {
                                            withAnimation {
                                                manager.selectedAgent = agent
                                                manager.selectedSkillPaths.removeAll()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: 200)
                    
                    Divider().background(Color.themeDivider)
                    
                    // 右侧：Skills 的精细勾选管理与主程序卸载
                    VStack(alignment: .leading, spacing: 12) {
                        if let agent = manager.selectedAgent {
                            // 主程序信息卡
                            HStack(spacing: 12) {
                                Image(systemName: "terminal.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.themeAccent)
                                    .frame(width: 44, height: 44)
                                    .background(Color.themeAccent.opacity(0.12))
                                    .cornerRadius(10)
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(agent.name)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.themeText)
                                    Text("主路径: \(agent.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
                                        .font(.system(size: 10))
                                        .foregroundColor(.themeTextSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(Color.themeCardBg.opacity(0.5))
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.themeDivider, lineWidth: 1))
                            
                            HStack {
                                Text("技能代理文件 (Skills)：")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(.themeTextSecondary)
                                Spacer()
                                
                                // 彻底卸载终端程序的勾选框
                                Toggle(isOn: Binding(
                                    get: { manager.selectedSkillPaths.contains(agent.path) },
                                    set: { checked in
                                        if checked {
                                            // 卸载整个程序，清空 Skill 勾选
                                            manager.selectedSkillPaths.removeAll()
                                            manager.selectedSkillPaths.insert(agent.path)
                                        } else {
                                            manager.selectedSkillPaths.remove(agent.path)
                                        }
                                    }
                                )) {
                                    Text("卸载主程序").font(.system(size: 11, weight: .bold)).foregroundColor(.red)
                                }
                                .toggleStyle(CheckboxToggleStyle())
                            }
                            
                            // Skills 列表
                            if manager.selectedSkillPaths.contains(agent.path) {
                                Spacer()
                                HStack {
                                    Spacer()
                                    VStack(spacing: 6) {
                                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red).font(.system(size: 24))
                                        Text("警告：您已选择【卸载主程序】！").font(.system(size: 12, weight: .bold)).foregroundColor(.red)
                                        Text("这将会彻底移除该工具的本地二进制软链及所有 skills 技能数据。").font(.system(size: 10.5)).foregroundColor(.themeTextSecondary).multilineTextAlignment(.center)
                                    }
                                    Spacer()
                                }
                                Spacer()
                            } else if agent.skills.isEmpty {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Text("该代理下暂无任何已安装的技能(Skill)项目。").font(.system(size: 11.5)).foregroundColor(.themeTextSecondary)
                                    Spacer()
                                }
                                Spacer()
                            } else {
                                ScrollView {
                                    VStack(spacing: 6) {
                                        ForEach(agent.skills) { skill in
                                            HStack {
                                                Toggle("", isOn: Binding(
                                                    get: { manager.selectedSkillPaths.contains(skill.path) },
                                                    set: { checked in
                                                        if checked {
                                                            manager.selectedSkillPaths.insert(skill.path)
                                                        } else {
                                                            manager.selectedSkillPaths.remove(skill.path)
                                                        }
                                                    }
                                                ))
                                                .toggleStyle(CheckboxToggleStyle())
                                                
                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(skill.name)
                                                        .font(.system(size: 12, weight: .semibold))
                                                        .foregroundColor(.themeText)
                                                    Text(skill.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                                        .font(.system(size: 9.5))
                                                        .foregroundColor(.themeTextTertiary)
                                                        .lineLimit(1)
                                                }
                                                Spacer()
                                                Text(skill.sizeString)
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .foregroundColor(.themeTextSecondary)
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.themeBg.opacity(0.3))
                                            .cornerRadius(6)
                                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.themeDivider, lineWidth: 1))
                                        }
                                    }
                                }
                                .frame(height: 250)
                            }
                            
                            // 动作按钮
                            HStack {
                                Text(manager.agentStatusText)
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.themeTextSecondary)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                if manager.isDeletingAgents {
                                    ProgressView().scaleEffect(0.6).padding(.trailing, 6)
                                }
                                
                                Button(action: {
                                    manager.deleteSelectedSkillsOrAgent()
                                }) {
                                    HStack {
                                        Image(systemName: "trash.fill")
                                        Text(manager.selectedSkillPaths.contains(agent.path) ? "确认卸载主程序" : "删除选中的 Skill (\(manager.selectedSkillPaths.count))")
                                    }
                                    .font(.system(size: 11.5, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(manager.selectedSkillPaths.isEmpty ? Color.gray.opacity(0.3) : Color.red)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(manager.selectedSkillPaths.isEmpty || manager.isDeletingAgents)
                            }
                            .padding(.top, 4)
                        } else {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "arrow.up.circle")
                                        .font(.system(size: 32))
                                        .foregroundColor(.themeTextTertiary)
                                    Text("请在上方列表中选择要管理的 Agent 终端程序")
                                        .font(.system(size: 12))
                                        .foregroundColor(.themeTextSecondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        } else {
            HStack(spacing: 14) {
                // 左侧：AI Agent 工具列表
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.themeTextTertiary)
                        TextField("搜索工具...", text: $agentSearchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .foregroundColor(.themeText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.themeBg.opacity(0.6))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeDivider, lineWidth: 1))
                    
                    if manager.isScanningAgents {
                        Spacer()
                        ProgressView().scaleEffect(0.8)
                        Text("扫描终端程序中...").font(.system(size: 11)).foregroundColor(.themeTextSecondary).padding(.top, 4)
                        Spacer()
                    } else if manager.terminalAgents.isEmpty {
                        Spacer()
                        Text("未发现可管理的终端 Agent。").font(.system(size: 11.5)).foregroundColor(.themeTextSecondary)
                        Spacer()
                    } else {
                        let filtered = manager.terminalAgents.filter { agentSearchText.isEmpty || $0.name.localizedCaseInsensitiveContains(agentSearchText) }
                        
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(filtered) { agent in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(agent.name)
                                                .font(.system(size: 12.5, weight: .bold))
                                                .foregroundColor(.themeText)
                                            Text(agent.skills.isEmpty ? "无技能" : "含有 \(agent.skills.count) 个 Skill 技能")
                                                .font(.system(size: 10))
                                                .foregroundColor(.themeTextSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10))
                                            .foregroundColor(.themeTextTertiary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 10)
                                    .background(manager.selectedAgent == agent ? Color.themeAccent.opacity(0.15) : Color.themeCardBg.opacity(0.4))
                                    .cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(manager.selectedAgent == agent ? Color.themeAccent : Color.themeDivider, lineWidth: 1))
                                    .onTapGesture {
                                        withAnimation {
                                            manager.selectedAgent = agent
                                            manager.selectedSkillPaths.removeAll()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(width: 250)
                .padding(.leading, 16)
                .padding(.vertical, 12)
                
                Divider().background(Color.themeDivider)
                
                // 右侧：Skills 的精细勾选管理与主程序卸载
                VStack(alignment: .leading, spacing: 12) {
                    if let agent = manager.selectedAgent {
                        // 主程序信息卡
                        HStack(spacing: 12) {
                            Image(systemName: "terminal.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.themeAccent)
                                .frame(width: 44, height: 44)
                                .background(Color.themeAccent.opacity(0.12))
                                .cornerRadius(10)
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(agent.name)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.themeText)
                                Text("主路径: \(agent.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
                                    .font(.system(size: 10))
                                    .foregroundColor(.themeTextSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.themeCardBg.opacity(0.5))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.themeDivider, lineWidth: 1))
                        
                        HStack {
                            Text("技能代理文件 (Skills)：")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(.themeTextSecondary)
                            Spacer()
                            
                            // 彻底卸载终端程序的勾选框
                            Toggle(isOn: Binding(
                                get: { manager.selectedSkillPaths.contains(agent.path) },
                                set: { checked in
                                    if checked {
                                        // 卸载整个程序，清空 Skill 勾选
                                        manager.selectedSkillPaths.removeAll()
                                        manager.selectedSkillPaths.insert(agent.path)
                                    } else {
                                        manager.selectedSkillPaths.remove(agent.path)
                                    }
                                }
                            )) {
                                Text("卸载主程序").font(.system(size: 11, weight: .bold)).foregroundColor(.red)
                            }
                            .toggleStyle(CheckboxToggleStyle())
                        }
                        
                        // Skills 列表
                        if manager.selectedSkillPaths.contains(agent.path) {
                            Spacer()
                            HStack {
                                Spacer()
                                VStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red).font(.system(size: 24))
                                    Text("警告：您已选择【卸载主程序】！").font(.system(size: 12, weight: .bold)).foregroundColor(.red)
                                    Text("这将会彻底移除该工具的本地二进制软链及所有 skills 技能数据。").font(.system(size: 10.5)).foregroundColor(.themeTextSecondary).multilineTextAlignment(.center)
                                }
                                Spacer()
                            }
                            Spacer()
                        } else if agent.skills.isEmpty {
                            Spacer()
                            HStack {
                                Spacer()
                                Text("该代理下暂无任何已安装的技能(Skill)项目。").font(.system(size: 11.5)).foregroundColor(.themeTextSecondary)
                                Spacer()
                            }
                            Spacer()
                        } else {
                            ScrollView {
                                VStack(spacing: 6) {
                                    ForEach(agent.skills) { skill in
                                        HStack {
                                            Toggle("", isOn: Binding(
                                                get: { manager.selectedSkillPaths.contains(skill.path) },
                                                set: { checked in
                                                    if checked {
                                                        manager.selectedSkillPaths.insert(skill.path)
                                                    } else {
                                                        manager.selectedSkillPaths.remove(skill.path)
                                                    }
                                                }
                                            ))
                                            .toggleStyle(CheckboxToggleStyle())
                                            
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(skill.name)
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(.themeText)
                                                Text(skill.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                                    .font(.system(size: 9.5))
                                                    .foregroundColor(.themeTextTertiary)
                                                    .lineLimit(1)
                                            }
                                            Spacer()
                                            Text(skill.sizeString)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(.themeTextSecondary)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.themeBg.opacity(0.3))
                                        .cornerRadius(6)
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.themeDivider, lineWidth: 1))
                                    }
                                }
                            }
                        }
                        
                        // 动作按钮
                        HStack {
                            Text(manager.agentStatusText)
                                .font(.system(size: 10.5))
                                .foregroundColor(.themeTextSecondary)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            if manager.isDeletingAgents {
                                ProgressView().scaleEffect(0.6).padding(.trailing, 6)
                            }
                            
                            Button(action: {
                                manager.deleteSelectedSkillsOrAgent()
                            }) {
                                HStack {
                                    Image(systemName: "trash.fill")
                                    Text(manager.selectedSkillPaths.contains(agent.path) ? "确认卸载主程序" : "删除选中的 Skill (\(manager.selectedSkillPaths.count))")
                                }
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(manager.selectedSkillPaths.isEmpty ? Color.gray.opacity(0.3) : Color.red)
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(manager.selectedSkillPaths.isEmpty || manager.isDeletingAgents)
                        }
                        .padding(.top, 4)
                    } else {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.left.circle")
                                    .font(.system(size: 32))
                                    .foregroundColor(.themeTextTertiary)
                                Text("请在左侧列表中选择要管理的 Agent 终端程序")
                                    .font(.system(size: 12))
                                    .foregroundColor(.themeTextSecondary)
                            }
                            Spacer()
                        }
                        Spacer()
                    }
                }
                .padding(.trailing, 16)
                .padding(.vertical, 12)
            }
        }
    }
}

// MARK: - 辅助样式组件

struct SubTabButton: View {
    let title: String
    let icon: String
    let active: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 11.5, weight: active ? .bold : .medium))
            }
            .foregroundColor(active ? .themeText : .themeTextSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    if active {
                        Color.themeCardBg
                            .cornerRadius(8)
                            .shadow(color: .themeShadow, radius: 4, x: 0, y: 2)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.themeDivider, lineWidth: 1))
                    } else {
                        Color.clear
                    }
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}


