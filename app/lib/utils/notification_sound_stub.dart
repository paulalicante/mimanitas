/// Stub implementation for non-web platforms (Android/iOS).
/// Does nothing - notification sounds are web-only for now.
class NotificationSound {
  static void ensureInitialized() {
    // No-op on mobile
  }

  static void play() {
    // No-op on mobile - could add mobile sound later
  }
}
