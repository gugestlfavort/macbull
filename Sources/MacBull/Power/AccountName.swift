import Foundation

/// A sudoers rule can only name accounts made of these characters, unquoted.
enum AccountName {
    static func isValid(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        return name.unicodeScalars.allSatisfy(isAllowed)
    }

    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "0"..."9", ".", "_", "-": true
        default: false
        }
    }
}
