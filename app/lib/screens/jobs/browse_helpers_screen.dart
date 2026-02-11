import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_theme.dart';
import '../../main.dart';
import '../profile/profile_screen.dart';

/// Screen for seekers to browse helpers for service-menu categories (like cleaning)
/// Allows direct contact/booking without posting a job first
class BrowseHelpersScreen extends StatefulWidget {
  final String skillId;
  final String skillName;

  const BrowseHelpersScreen({
    super.key,
    required this.skillId,
    required this.skillName,
  });

  @override
  State<BrowseHelpersScreen> createState() => _BrowseHelpersScreenState();
}

class _BrowseHelpersScreenState extends State<BrowseHelpersScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _helpers = [];
  String _sortBy = 'rate_low'; // rate_low, rate_high, rating

  @override
  void initState() {
    super.initState();
    _loadHelpers();
  }

  Future<void> _loadHelpers() async {
    setState(() => _isLoading = true);

    try {
      // Get helpers who have this skill
      final data = await supabase
          .from('user_skills')
          .select('''
            user_id, rate_per_hour, skill_attributes,
            profiles!inner(id, name, bio, avatar_url, phone_verified)
          ''')
          .eq('skill_id', widget.skillId);

      // Filter to only helpers (users with type = 'helper')
      final helpers = <Map<String, dynamic>>[];
      for (final us in data) {
        final profile = us['profiles'] as Map<String, dynamic>;
        // Get average rating for this helper
        final reviews = await supabase
            .from('reviews')
            .select('rating')
            .eq('reviewee_id', profile['id']);

        double avgRating = 0;
        if (reviews.isNotEmpty) {
          final total = reviews.fold<double>(
            0,
            (sum, r) => sum + (r['rating'] as num).toDouble(),
          );
          avgRating = total / reviews.length;
        }

        helpers.add({
          'user_id': us['user_id'],
          'rate_per_hour': us['rate_per_hour'],
          'skill_attributes': us['skill_attributes'],
          'name': profile['name'],
          'bio': profile['bio'],
          'avatar_url': profile['avatar_url'],
          'phone_verified': profile['phone_verified'],
          'avg_rating': avgRating,
          'review_count': reviews.length,
        });
      }

      // Sort helpers
      _sortHelpers(helpers);

      setState(() {
        _helpers = helpers;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading helpers: $e');
      setState(() => _isLoading = false);
    }
  }

  void _sortHelpers(List<Map<String, dynamic>> helpers) {
    switch (_sortBy) {
      case 'rate_low':
        helpers.sort((a, b) {
          final aRate = (a['rate_per_hour'] as num?)?.toDouble() ?? 999;
          final bRate = (b['rate_per_hour'] as num?)?.toDouble() ?? 999;
          return aRate.compareTo(bRate);
        });
        break;
      case 'rate_high':
        helpers.sort((a, b) {
          final aRate = (a['rate_per_hour'] as num?)?.toDouble() ?? 0;
          final bRate = (b['rate_per_hour'] as num?)?.toDouble() ?? 0;
          return bRate.compareTo(aRate);
        });
        break;
      case 'rating':
        helpers.sort((a, b) {
          final aRating = (a['avg_rating'] as num?)?.toDouble() ?? 0;
          final bRating = (b['avg_rating'] as num?)?.toDouble() ?? 0;
          return bRating.compareTo(aRating);
        });
        break;
    }
  }

  void _changeSortOrder(String sortBy) {
    setState(() {
      _sortBy = sortBy;
      _sortHelpers(_helpers);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.skillName,
          style: GoogleFonts.nunito(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.navyDark,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Ordenar por',
            onSelected: _changeSortOrder,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'rate_low',
                child: Row(
                  children: [
                    Icon(
                      Icons.arrow_upward,
                      size: 18,
                      color: _sortBy == 'rate_low' ? AppColors.orange : AppColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Precio: menor a mayor',
                      style: TextStyle(
                        fontWeight: _sortBy == 'rate_low' ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'rate_high',
                child: Row(
                  children: [
                    Icon(
                      Icons.arrow_downward,
                      size: 18,
                      color: _sortBy == 'rate_high' ? AppColors.orange : AppColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Precio: mayor a menor',
                      style: TextStyle(
                        fontWeight: _sortBy == 'rate_high' ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'rating',
                child: Row(
                  children: [
                    Icon(
                      Icons.star,
                      size: 18,
                      color: _sortBy == 'rating' ? AppColors.orange : AppColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Mejor valorados',
                      style: TextStyle(
                        fontWeight: _sortBy == 'rating' ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : _helpers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.search_off, size: 64, color: AppColors.textMuted),
                      const SizedBox(height: 16),
                      Text(
                        'No hay ayudantes disponibles',
                        style: GoogleFonts.nunito(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Prueba a publicar un trabajo',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadHelpers,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _helpers.length,
                    itemBuilder: (context, index) {
                      final helper = _helpers[index];
                      return _buildHelperCard(helper);
                    },
                  ),
                ),
    );
  }

  Widget _buildHelperCard(Map<String, dynamic> helper) {
    final name = helper['name'] as String? ?? 'Ayudante';
    final bio = helper['bio'] as String?;
    final avatarUrl = helper['avatar_url'] as String?;
    final rate = helper['rate_per_hour'] as num?;
    final avgRating = (helper['avg_rating'] as num?)?.toDouble() ?? 0;
    final reviewCount = helper['review_count'] as int? ?? 0;
    final phoneVerified = helper['phone_verified'] == true;
    final attributes = helper['skill_attributes'] as Map<String, dynamic>? ?? {};

    // Build attributes summary
    final attrSummary = _buildAttributesSummary(attributes);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => ProfileScreen(userId: helper['user_id']),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.navyLight,
                    backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl == null
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'A',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  // Name and rating
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                style: GoogleFonts.nunito(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.navyDark,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (phoneVerified) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.verified, size: 18, color: AppColors.success),
                            ],
                          ],
                        ),
                        if (reviewCount > 0)
                          Row(
                            children: [
                              Icon(Icons.star, size: 16, color: AppColors.gold),
                              const SizedBox(width: 4),
                              Text(
                                '${avgRating.toStringAsFixed(1)} ($reviewCount)',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  // Price
                  if (rate != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.orangeLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${rate.toStringAsFixed(0)}€/h',
                        style: GoogleFonts.nunito(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.orange,
                        ),
                      ),
                    ),
                ],
              ),
              // Bio
              if (bio != null && bio.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  bio,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              // Attributes summary
              if (attrSummary.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: attrSummary.map((attr) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.navyVeryLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        attr,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.navyDark,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              // View profile button
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ProfileScreen(userId: helper['user_id']),
                      ),
                    );
                  },
                  icon: const Icon(Icons.person_outline, size: 18),
                  label: const Text('Ver perfil y contactar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _buildAttributesSummary(Map<String, dynamic> attributes) {
    final summary = <String>[];

    // Map attribute values to readable labels
    final labelMap = {
      'regular': 'Regular',
      'deep': 'Profunda',
      'post_obra': 'Fin de obra',
      'windows': 'Ventanas',
      'oven': 'Horno',
      'fridge': 'Nevera',
      'ironing': 'Plancha',
    };

    for (final entry in attributes.entries) {
      final value = entry.value;
      if (value is List) {
        for (final v in value) {
          final label = labelMap[v] ?? v.toString();
          summary.add(label);
        }
      } else if (value is String && labelMap.containsKey(value)) {
        summary.add(labelMap[value]!);
      }
    }

    return summary.take(5).toList(); // Limit to 5 tags
  }
}
