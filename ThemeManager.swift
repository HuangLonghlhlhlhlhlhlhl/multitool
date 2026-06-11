import SwiftUI
import AppKit

struct ThemeManager {
    static func isDark(themeMode: Int) -> Bool {
        if themeMode == 0 {
            if #available(macOS 10.14, *) {
                return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            }
            return false
        }
        return themeMode == 2
    }
    
    static func applyTheme() {
        let themeMode = UserDefaults.standard.integer(forKey: "themeMode")
        let appearanceName: NSAppearance.Name?
        switch themeMode {
        case 1: appearanceName = .aqua
        case 2: appearanceName = .darkAqua
        default: appearanceName = nil // 跟随系统
        }
        
        let dark = isDark(themeMode: themeMode)
        let appearance = appearanceName != nil ? NSAppearance(named: appearanceName!) : nil
        
        DispatchQueue.main.async {
            for window in NSApp.windows {
                guard window.className.contains("NSWindow") else { continue }
                
                // 排除一些系统和不需要调整的窗口类型（例如无标题的不可见窗口）
                let title = window.title
                guard title != "" || window.styleMask.contains(.borderless) else { continue }
                
                // 应用系统/自定义外观
                window.appearance = appearance
                
                // 递归更新 contentView 中所有 NSVisualEffectView 的材质
                if let contentView = window.contentView {
                    updateVisualEffects(in: contentView, isDark: dark)
                }
            }
        }
    }
    
    private static func updateVisualEffects(in view: NSView, isDark: Bool) {
        if let visualEffect = view as? NSVisualEffectView {
            // 在深色下使用特殊的 HUD 半透明面板效果，在浅色下使用标准的轻快毛玻璃效果
            visualEffect.material = isDark ? .hudWindow : .windowBackground
        }
        for subview in view.subviews {
            updateVisualEffects(in: subview, isDark: isDark)
        }
    }
}

extension Color {
    // 动态背景颜色底色
    static let themeBg = Color(NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1.0)
        } else {
            return NSColor(red: 0.96, green: 0.96, blue: 0.98, alpha: 1.0)
        }
    })
    
    // 动态卡片背景底色
    static let themeCardBg = Color(NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.white.withAlphaComponent(0.04)
        } else {
            return NSColor.white
        }
    })
    
    // 动态边框/描边颜色
    static let themeBorder = Color(NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.white.withAlphaComponent(0.08)
        } else {
            return NSColor.black.withAlphaComponent(0.08)
        }
    })
    
    // 动态分隔线颜色
    static let themeDivider = Color(NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.white.withAlphaComponent(0.06)
        } else {
            return NSColor.black.withAlphaComponent(0.08)
        }
    })
    
    // 动态一级核心文本/图标颜色（高级深炭灰/纯白）
    static let themeText = Color(NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.white
        } else {
            return NSColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 1.0)
        }
    })
    
    // 动态二级辅助文本/图标颜色
    static let themeTextSecondary = Color(NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.white.withAlphaComponent(0.6)
        } else {
            return NSColor(red: 0.28, green: 0.30, blue: 0.38, alpha: 1.0)
        }
    })
    
    // 动态三级极淡文本/图标/占位颜色
    static let themeTextTertiary = Color(NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.white.withAlphaComponent(0.4)
        } else {
            return NSColor(red: 0.42, green: 0.45, blue: 0.55, alpha: 1.0)
        }
    })
    
    // 动态悬浮/激活态背景颜色
    static let themeHover = Color(NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.white.withAlphaComponent(0.08)
        } else {
            return NSColor.black.withAlphaComponent(0.04)
        }
    })
    
    // 动态阴影颜色（深色下不显示阴影以保证纯净暗黑，浅色下配以超级漫反射柔和阴影）
    static let themeShadow = Color(NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor.clear
        } else {
            return NSColor(white: 0.0, alpha: 0.03)
        }
    })
    
    // 背景紫色渐变微光
    static let themeRadialPurple = Color(NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 0.62, green: 0.32, blue: 0.88, alpha: 0.12)
        } else {
            return NSColor(red: 0.62, green: 0.32, blue: 0.88, alpha: 0.05)
        }
    })
    
    // 背景绿色渐变微光
    static let themeRadialGreen = Color(NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 0.22, green: 0.80, blue: 0.45, alpha: 0.08)
        } else {
            return NSColor(red: 0.22, green: 0.80, blue: 0.45, alpha: 0.03)
        }
    })
}
