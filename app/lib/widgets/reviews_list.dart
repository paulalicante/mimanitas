import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../app_theme.dart';
import '../main.dart';
import 'star_rating.dart';

class ReviewsList extends StatefulWidget {
  final String userId;

  const ReviewsList({
    super.key,
    required this.userId,
  });

  @override
  State<ReviewsList> createState() => _ReviewsListState();
}

class _ReviewsListState extends State<ReviewsList> {
  bool _isLoading = true;
  double? _averageRating;
  int _reviewCount = 0;
  List<Map<String, dynamic>> _reviews = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeAndLoadReviews();
  }

  Future<void> _initializeAndLoadReviews() async {
    await initializeDateFormatting('es', null);
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get profile with average rating
      final profileData = await supabase
          .from('profiles')
          .select('average_rating, review_count')
          .eq('id', widget.userId)
          .single();

      // Get all reviews for this user
      final reviewsData = await supabase
          .from('reviews')
          .select('''
            id,
            rating,
            comment,
            created_at,
            reviewer:reviewer_id (
              id,
              name
            )
          ''')
          .eq('reviewee_id', widget.userId)
          .order('created_at', ascending: false);

      setState(() {
        _averageRating = profileData['average_rating'] != null
            ? (profileData['average_rating'] as num).toDouble()
            : null;
        _reviewCount = profileData['review_count'] as int? ?? 0;
        _reviews = List<Map<String, dynamic>>.from(reviewsData);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            const Text(
              'Error al cargar reseñas',
              style: TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadReviews,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Average Rating Summary
        if (_averageRating != null)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.navyShadow,
                  blurRadius: 10,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  _averageRating!.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navyDark,
                  ),
                ),
                const SizedBox(height: 8),
                StarRating(
                  rating: _averageRating!,
                  size: 32,
                ),
                const SizedBox(height: 8),
                Text(
                  '$_reviewCount ${_reviewCount == 1 ? 'reseña' : 'reseñas'}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),

        // Empty state
        if (_reviews.isEmpty)
          Container(
            margin: const EdgeInsets.only(top: 24),
            padding: const EdgeInsets.all(48),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.rate_review_outlined,
                  size: 64,
                  color: AppColors.border,
                ),
                SizedBox(height: 16),
                Text(
                  'Sin reseñas todavía',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Las reseñas aparecerán aquí después de completar trabajos',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

        // Reviews list
        if (_reviews.isNotEmpty) ...[
          const SizedBox(height: 24),
          ...List.generate(_reviews.length, (index) {
            final review = _reviews[index];
            final reviewer = review['reviewer'] as Map<String, dynamic>?;
            final reviewerName =
                reviewer?['name'] as String? ?? 'Usuario';
            final rating = (review['rating'] as num).toDouble();
            final comment = review['comment'] as String?;
            final createdAt = DateTime.parse(review['created_at'] as String);
            final formattedDate = DateFormat('d MMM yyyy', 'es').format(createdAt);

            return Container(
              margin: EdgeInsets.only(bottom: index < _reviews.length - 1 ? 16 : 0),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.navyShadow,
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppColors.navyDark,
                        child: Text(
                          reviewerName[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              reviewerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              formattedDate,
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      StarRating(
                        rating: rating,
                        size: 24,
                      ),
                    ],
                  ),
                  if (comment != null && comment.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      comment,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ],
    );
  }
}
