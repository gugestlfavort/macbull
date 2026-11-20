import Foundation

/// User-facing text of lid-closed mode.
enum LidCopy {
    static let installPrompt = "MacBull needs your password once, so it can keep this Mac awake with the lid closed."
    static let removePrompt = "MacBull needs your password to remove its lid-closed permission."

    static let noLid = "This Mac has no lid, so lid-closed mode does not apply."
    static let badAccountName = "This account name has characters that a sudo rule cannot use, so lid-closed mode cannot be set up here."
    static let macOSRefused = "macOS did not accept the change. Make sure you are signed in as an administrator, then try again."
    static let sudoersNotIncluded = "The permission was added, but sudo does not read /etc/sudoers.d on this Mac. The main sudoers file needs to include that folder."
    static let busy = "Another lid-closed change is still running. Try again in a moment."
    static let enableFailed = "MacBull could not keep the Mac awake with the lid closed. It will try again shortly."
    static let disableFailed = "MacBull could not turn normal sleep back on. It keeps trying."
    static let flagFailed = "MacBull could not write its safety note in Application Support, so it will not change the sleep setting."
    static let removeFailed = "macOS did not accept the change. The lid-closed permission is still in place."
}
