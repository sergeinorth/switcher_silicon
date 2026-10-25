import AppKit

public enum FrontmostApp {
    public static var bundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    public static var name: String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }
}
