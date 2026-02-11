import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';

/// Service for managing profile avatar uploads
class AvatarService {
  static final ImagePicker _picker = ImagePicker();

  /// Pick an image from gallery or camera
  static Future<XFile?> pickImage({bool fromCamera = false}) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      return image;
    } catch (e) {
      print('Error picking image: $e');
      return null;
    }
  }

  /// Upload avatar to Supabase Storage and update profile
  /// Returns the URL on success, or throws an exception with error details
  static Future<String?> uploadAvatar(XFile imageFile) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('No user logged in');

    try {
      final bytes = await imageFile.readAsBytes();
      print('Avatar upload: got ${bytes.length} bytes');

      // Determine file extension and content type
      // On web, path is a blob URL, so use mimeType or default to jpeg
      String fileExt;
      String contentType;

      if (imageFile.mimeType != null && imageFile.mimeType!.startsWith('image/')) {
        contentType = imageFile.mimeType!;
        fileExt = contentType.split('/').last;
        if (fileExt == 'jpg') fileExt = 'jpeg';
      } else if (imageFile.path.contains('.') && !imageFile.path.startsWith('blob:')) {
        // Native platform with real file path
        fileExt = imageFile.path.split('.').last.toLowerCase();
        if (fileExt == 'jpg') fileExt = 'jpeg';
        contentType = 'image/$fileExt';
      } else {
        // Web blob URL or unknown - default to jpeg
        fileExt = 'jpeg';
        contentType = 'image/jpeg';
      }

      final fileName = '${user.id}/avatar.$fileExt';

      print('Avatar upload: fileName=$fileName, contentType=$contentType');

      // Upload to Supabase Storage
      await supabase.storage.from('avatars').uploadBinary(
        fileName,
        bytes,
        fileOptions: FileOptions(
          contentType: contentType,
          upsert: true, // Replace if exists
        ),
      );

      print('Avatar upload: upload complete');

      // Get public URL
      final avatarUrl = supabase.storage.from('avatars').getPublicUrl(fileName);
      print('Avatar upload: public URL = $avatarUrl');

      // Update profile with avatar URL (add cache buster)
      final urlWithCacheBuster = '$avatarUrl?t=${DateTime.now().millisecondsSinceEpoch}';
      await supabase.from('profiles').update({
        'avatar_url': urlWithCacheBuster,
      }).eq('id', user.id);

      print('Avatar upload: profile updated');

      return urlWithCacheBuster;
    } catch (e) {
      print('Avatar upload error: $e');
      rethrow;
    }
  }

  /// Delete current avatar
  static Future<bool> deleteAvatar() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return false;

      // List files in user's folder
      final files = await supabase.storage.from('avatars').list(path: user.id);

      // Delete all avatar files
      for (final file in files) {
        await supabase.storage.from('avatars').remove(['${user.id}/${file.name}']);
      }

      // Clear avatar URL in profile
      await supabase.from('profiles').update({
        'avatar_url': null,
      }).eq('id', user.id);

      return true;
    } catch (e) {
      print('Error deleting avatar: $e');
      return false;
    }
  }

  /// Get avatar URL for a user
  static Future<String?> getAvatarUrl(String userId) async {
    try {
      final profile = await supabase
          .from('profiles')
          .select('avatar_url')
          .eq('id', userId)
          .single();
      return profile['avatar_url'] as String?;
    } catch (e) {
      print('Error getting avatar URL: $e');
      return null;
    }
  }
}
