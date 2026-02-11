import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app_theme.dart';

/// Bottom navigation bar for Mi Manitas app
/// Shows 5 tabs with different options for helpers vs seekers
class MiManitasBottomNav extends StatelessWidget {
  final int currentIndex;
  final String? userType;
  final int unreadMessageCount;
  final ValueChanged<int> onTap;

  const MiManitasBottomNav({
    super.key,
    required this.currentIndex,
    required this.userType,
    required this.unreadMessageCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.navyShadow,
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: _buildNavItems(),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildNavItems() {
    if (userType == 'helper') {
      return [
        _buildNavItem(
          index: 0,
          icon: Icons.home_outlined,
          activeIcon: Icons.home,
          label: 'Inicio',
        ),
        _buildNavItem(
          index: 1,
          icon: Icons.search_outlined,
          activeIcon: Icons.search,
          label: 'Trabajos',
        ),
        _buildNavItem(
          index: 2,
          icon: Icons.calendar_today_outlined,
          activeIcon: Icons.calendar_today,
          label: 'Calendario',
        ),
        _buildNavItem(
          index: 3,
          icon: Icons.message_outlined,
          activeIcon: Icons.message,
          label: 'Mensajes',
          badgeCount: unreadMessageCount,
        ),
        _buildNavItem(
          index: 4,
          icon: Icons.person_outlined,
          activeIcon: Icons.person,
          label: 'Perfil',
        ),
      ];
    } else {
      // Seeker tabs
      return [
        _buildNavItem(
          index: 0,
          icon: Icons.home_outlined,
          activeIcon: Icons.home,
          label: 'Inicio',
        ),
        _buildNavItem(
          index: 1,
          icon: Icons.work_outline,
          activeIcon: Icons.work,
          label: 'Mis trabajos',
        ),
        _buildNavItem(
          index: 2,
          icon: Icons.add_circle_outline,
          activeIcon: Icons.add_circle,
          label: 'Publicar',
        ),
        _buildNavItem(
          index: 3,
          icon: Icons.message_outlined,
          activeIcon: Icons.message,
          label: 'Mensajes',
          badgeCount: unreadMessageCount,
        ),
        _buildNavItem(
          index: 4,
          icon: Icons.person_outlined,
          activeIcon: Icons.person,
          label: 'Perfil',
        ),
      ];
    }
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    int? badgeCount,
  }) {
    final isSelected = currentIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    isSelected ? activeIcon : icon,
                    color: isSelected ? AppColors.orange : AppColors.textMuted,
                    size: 24,
                  ),
                  if (badgeCount != null && badgeCount > 0)
                    Positioned(
                      right: -8,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        decoration: const BoxDecoration(
                          color: AppColors.orange,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          badgeCount > 9 ? '9+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? AppColors.orange : AppColors.textMuted,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
