// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js' as js;

/// Plays a pleasant notification chime using the Web Audio API.
/// No external MP3 file needed - synthesizes a two-tone chime.
class NotificationSound {
  static bool _initialized = false;

  /// Must be called once after any user interaction (browser autoplay policy).
  static void ensureInitialized() {
    if (_initialized) return;
    // Create AudioContext on first user gesture
    try {
      js.context.callMethod('eval', ['''
        window._mimanitasAudioCtx = new (window.AudioContext || window.webkitAudioContext)();
      ''']);
      _initialized = true;
    } catch (e) {
      print('NotificationSound: Could not initialize AudioContext: $e');
    }
  }

  /// Play a pleasant two-tone notification chime.
  static void play() {
    ensureInitialized();
    try {
      js.context.callMethod('eval', ['''
        (function() {
          var ctx = window._mimanitasAudioCtx;
          if (!ctx) return;
          if (ctx.state === 'suspended') ctx.resume();

          var now = ctx.currentTime;

          // First tone (E5 = 659 Hz)
          var osc1 = ctx.createOscillator();
          var gain1 = ctx.createGain();
          osc1.type = 'sine';
          osc1.frequency.value = 659;
          gain1.gain.setValueAtTime(0.3, now);
          gain1.gain.exponentialRampToValueAtTime(0.01, now + 0.3);
          osc1.connect(gain1);
          gain1.connect(ctx.destination);
          osc1.start(now);
          osc1.stop(now + 0.3);

          // Second tone (G5 = 784 Hz) - slightly delayed for chime effect
          var osc2 = ctx.createOscillator();
          var gain2 = ctx.createGain();
          osc2.type = 'sine';
          osc2.frequency.value = 784;
          gain2.gain.setValueAtTime(0.3, now + 0.15);
          gain2.gain.exponentialRampToValueAtTime(0.01, now + 0.5);
          osc2.connect(gain2);
          gain2.connect(ctx.destination);
          osc2.start(now + 0.15);
          osc2.stop(now + 0.5);
        })();
      ''']);
    } catch (e) {
      print('NotificationSound: Could not play: $e');
    }
  }
}
