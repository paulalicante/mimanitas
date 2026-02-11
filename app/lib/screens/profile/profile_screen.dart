import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../main.dart';
import '../../widgets/reviews_list.dart';
import '../../app_theme.dart';
import '../../services/avatar_service.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId; // If null, shows current user's profile

  const ProfileScreen({
    super.key,
    this.userId,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  bool _isOwnProfile = false;
  bool _isUploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _pickAndUploadAvatar() async {
    // Show options: camera (mobile only) or gallery
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Camera option only on mobile (web can't access webcam via image_picker)
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.camera_alt, color: AppColors.navyDark),
                title: const Text('Hacer foto'),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.navyDark),
              title: Text(kIsWeb ? 'Elegir archivo' : 'Elegir de galería'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            if (_profile?['avatar_url'] != null)
              ListTile(
                leading: const Icon(Icons.delete, color: AppColors.error),
                title: const Text('Eliminar foto', style: TextStyle(color: AppColors.error)),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;

    if (source == 'delete') {
      setState(() => _isUploadingAvatar = true);
      final success = await AvatarService.deleteAvatar();
      if (success) {
        setState(() {
          _profile?['avatar_url'] = null;
          _isUploadingAvatar = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Foto eliminada'), backgroundColor: AppColors.success),
          );
        }
      } else {
        setState(() => _isUploadingAvatar = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error al eliminar foto'), backgroundColor: AppColors.error),
          );
        }
      }
      return;
    }

    final image = await AvatarService.pickImage(fromCamera: source == 'camera');
    if (image == null) return;

    setState(() => _isUploadingAvatar = true);

    try {
      final avatarUrl = await AvatarService.uploadAvatar(image);

      if (avatarUrl != null) {
        setState(() {
          _profile?['avatar_url'] = avatarUrl;
          _isUploadingAvatar = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Foto actualizada'), backgroundColor: AppColors.success),
          );
        }
      } else {
        setState(() => _isUploadingAvatar = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error al subir foto'), backgroundColor: AppColors.error),
          );
        }
      }
    } catch (e) {
      print('Avatar upload exception: $e');
      setState(() => _isUploadingAvatar = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      final profileId = widget.userId ?? currentUser.id;
      _isOwnProfile = profileId == currentUser.id;

      final profileData = await supabase
          .from('profiles')
          .select('*')
          .eq('id', profileId)
          .single();

      setState(() {
        _profile = profileData;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading profile: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(''),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_profile == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(''),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '😕',
                style: TextStyle(fontSize: 64),
              ),
              const SizedBox(height: 16),
              Text(
                'Perfil no encontrado',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final fullName = _profile!['name'] as String? ?? 'Usuario';
    final avatarUrl = _profile!['avatar_url'] as String?;
    final bio = _profile!['bio'] as String?;
    final phone = _profile!['phone'] as String?;
    final phoneVerified = _profile!['phone_verified'] as bool? ?? false;
    final barrio = _profile!['barrio'] as String?;
    final averageRating = _profile!['average_rating'] != null
        ? (_profile!['average_rating'] as num).toDouble()
        : null;
    final reviewCount = _profile!['review_count'] as int? ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isOwnProfile ? 'Mi perfil' : 'Perfil',
        ),
        actions: [
          if (_isOwnProfile)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Función de edición próximamente'),
                  ),
                );
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Profile header card
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: AppDecorations.card(),
                    child: Column(
                      children: [
                        // Avatar
                        GestureDetector(
                          onTap: _isOwnProfile ? _pickAndUploadAvatar : null,
                          child: Stack(
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  gradient: avatarUrl == null
                                      ? const LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [AppColors.navyDark, AppColors.navyLight],
                                        )
                                      : null,
                                  shape: BoxShape.circle,
                                  image: avatarUrl != null
                                      ? DecorationImage(
                                          image: NetworkImage(avatarUrl),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.navyDark.withOpacity(0.3),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: avatarUrl == null
                                    ? Center(
                                        child: Text(
                                          fullName.isNotEmpty ? fullName[0].toUpperCase() : 'U',
                                          style: GoogleFonts.nunito(
                                            fontSize: 42,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                              // Upload indicator or edit badge
                              if (_isOwnProfile)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: _isUploadingAvatar ? AppColors.gold : AppColors.orange,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                    ),
                                    child: _isUploadingAvatar
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.camera_alt,
                                            size: 16,
                                            color: Colors.white,
                                          ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Name with verification badge
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              fullName,
                              style: GoogleFonts.nunito(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: AppColors.navyDark,
                              ),
                            ),
                            if (phoneVerified) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: AppColors.info,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Location
                        if (barrio != null)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 18,
                                color: AppColors.textMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                barrio,
                                style: GoogleFonts.inter(
                                  color: AppColors.textMuted,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),

                        // Rating badge
                        if (averageRating != null && reviewCount > 0) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.goldLight,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.gold.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star,
                                  color: AppColors.gold,
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  averageRating.toStringAsFixed(1),
                                  style: GoogleFonts.nunito(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.navyDark,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '($reviewCount ${reviewCount == 1 ? 'reseña' : 'reseñas'})',
                                  style: GoogleFonts.inter(
                                    color: AppColors.textMuted,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Bio section
                  if (bio != null && bio.isNotEmpty)
                    _buildInfoCard(
                      icon: Icons.person_outline,
                      title: 'Sobre mí',
                      child: Text(
                        bio,
                        style: GoogleFonts.inter(
                          color: AppColors.textMuted,
                          fontSize: 15,
                          height: 1.6,
                        ),
                      ),
                    ),

                  // Contact info (only for own profile)
                  if (_isOwnProfile && phone != null) ...[
                    const SizedBox(height: 16),
                    _buildInfoCard(
                      icon: Icons.contact_phone_outlined,
                      title: 'Información de contacto',
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.navyVeryLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.phone,
                              size: 20,
                              color: AppColors.navyDark,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                phone,
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textDark,
                                ),
                              ),
                              if (phoneVerified)
                                Text(
                                  'Verificado',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Reviews section
                  if (reviewCount > 0) ...[
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        const Icon(Icons.reviews_outlined, size: 22, color: AppColors.navyDark),
                        const SizedBox(width: 8),
                        Text(
                          'Reseñas',
                          style: GoogleFonts.nunito(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navyDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ReviewsList(userId: widget.userId ?? supabase.auth.currentUser!.id),
                  ],

                  // Empty state for no reviews
                  if (reviewCount == 0) ...[
                    const SizedBox(height: 28),
                    Container(
                      padding: const EdgeInsets.all(48),
                      decoration: AppDecorations.card(),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: const BoxDecoration(
                              color: AppColors.navyVeryLight,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.rate_review_outlined,
                              size: 40,
                              color: AppColors.navyLight,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Sin reseñas todavía',
                            style: GoogleFonts.nunito(
                              color: AppColors.navyDark,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Las reseñas aparecerán aquí después de completar trabajos',
                            style: GoogleFonts.inter(
                              color: AppColors.textMuted,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.navyDark),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.nunito(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navyDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
