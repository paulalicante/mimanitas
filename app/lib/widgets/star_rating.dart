import 'package:flutter/material.dart';
import '../app_theme.dart';

class StarRating extends StatelessWidget {
  final double rating;
  final Function(double)? onRatingChanged;
  final double size;
  final Color color;
  final bool allowHalfRatings;

  const StarRating({
    super.key,
    required this.rating,
    this.onRatingChanged,
    this.size = 32,
    this.color = AppColors.gold,
    this.allowHalfRatings = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return GestureDetector(
          onTapDown: onRatingChanged != null
              ? (details) {
                  final box = context.findRenderObject() as RenderBox;
                  final localPosition = box.globalToLocal(details.globalPosition);
                  final starWidth = size;
                  final starIndex = (localPosition.dx / starWidth).floor();
                  final positionInStar = (localPosition.dx % starWidth) / starWidth;

                  double newRating;
                  if (allowHalfRatings && positionInStar < 0.5) {
                    newRating = starIndex + 0.5;
                  } else {
                    newRating = (starIndex + 1).toDouble();
                  }

                  if (newRating >= 0.5 && newRating <= 5.0) {
                    onRatingChanged!(newRating);
                  }
                }
              : null,
          child: Container(
            width: size,
            height: size,
            padding: const EdgeInsets.all(2),
            child: _buildStar(index),
          ),
        );
      }),
    );
  }

  Widget _buildStar(int index) {
    final difference = rating - index;

    if (difference >= 1.0) {
      // Full star
      return Icon(
        Icons.star,
        size: size - 4,
        color: color,
      );
    } else if (difference >= 0.5) {
      // Half star
      return Stack(
        children: [
          Icon(
            Icons.star_border,
            size: size - 4,
            color: color,
          ),
          ClipRect(
            clipper: _HalfClipper(),
            child: Icon(
              Icons.star,
              size: size - 4,
              color: color,
            ),
          ),
        ],
      );
    } else {
      // Empty star
      return Icon(
        Icons.star_border,
        size: size - 4,
        color: color,
      );
    }
  }
}

class _HalfClipper extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width / 2, size.height);
  }

  @override
  bool shouldReclip(CustomClipper<Rect> oldClipper) => false;
}
