import AppKit
import CoreText

/// The bundled iA Writer Mono S, with a graceful fall back to the system
/// monospaced face when the app is run outside its bundle (`swift run`).
enum Fonts {
    static let familyName = "iA Writer Mono S"

    /// Registers the fonts shipped in `Contents/Resources/Fonts`.
    ///
    /// `ATSApplicationFontsPath` in Info.plist already does this for a real
    /// bundle; this covers the unbundled case and is harmless when the fonts
    /// are registered twice.
    static func registerBundledFonts() {
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory, includingPropertiesForKeys: nil) else { return }

        for file in files where file.pathExtension.lowercased() == "ttf" {
            _ = CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }

    static func editor(size: CGFloat) -> NSFont {
        NSFont(name: familyName, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func bold(_ font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }

    static func italic(_ font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }

    /// Interface chrome (footer, find bar) uses the same face as the writing,
    /// which is what makes the window read as one surface.
    static func interface(size: CGFloat) -> NSFont {
        NSFont(name: familyName, size: size) ?? NSFont.systemFont(ofSize: size)
    }

    /// The width of one character. The writing column is measured in these.
    static func characterWidth(of font: NSFont) -> CGFloat {
        let width = ("0" as NSString).size(withAttributes: [.font: font]).width
        return width > 0 ? width : font.pointSize * 0.6
    }
}
