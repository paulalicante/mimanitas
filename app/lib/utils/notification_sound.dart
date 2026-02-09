// Conditional import: use web implementation on web, stub on mobile
export 'notification_sound_stub.dart'
    if (dart.library.html) 'notification_sound_web.dart';
