import 'package:flutter/material.dart';
import '../../main.dart';
import '../jobs/post_job_screen.dart';
import '../jobs/my_jobs_screen.dart';
import '../jobs/browse_jobs_screen.dart';
import '../jobs/my_applications_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _userType;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        print('DEBUG: Loading profile for user ${user.id}');
        final profile = await supabase
            .from('profiles')
            .select('user_type')
            .eq('id', user.id)
            .single();

        print('DEBUG: Profile data: $profile');
        print('DEBUG: User type from DB: ${profile['user_type']}');

        setState(() {
          _userType = profile['user_type'] as String?;
          _isLoading = false;
        });
        print('DEBUG: _userType set to: $_userType');
      }
    } catch (e) {
      print('DEBUG: Error loading profile: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    final userName = user?.userMetadata?['name'] ?? user?.email?.split('@')[0] ?? 'Usuario';

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFFFFBF5),
        body: Center(
          child: CircularProgressIndicator(
            color: Color(0xFFE86A33),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF5),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header
            Container(
              constraints: const BoxConstraints(maxWidth: 900),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        '🔧',
                        style: TextStyle(fontSize: 28),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Mi Manitas',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFE86A33),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(
                        'Hola, $userName',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 16),
                      if (_userType == 'seeker')
                        TextButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const MyJobsScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.work_outline, size: 18),
                          label: const Text('Mis trabajos'),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFE86A33),
                          ),
                        ),
                      if (_userType == 'helper')
                        TextButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const MyApplicationsScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.assignment_outlined, size: 18),
                          label: const Text('Mis aplicaciones'),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFE86A33),
                          ),
                        ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () async {
                          await supabase.auth.signOut();
                        },
                        icon: const Icon(Icons.logout, size: 18),
                        label: const Text('Salir'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFE86A33),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Hero Section
            Container(
              constraints: const BoxConstraints(maxWidth: 900),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0E8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '🚀 Próximamente en Alicante',
                      style: TextStyle(
                        color: const Color(0xFFE86A33),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Encuentra ayuda local.',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Comparte tu ',
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        'tiempo',
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          fontStyle: FontStyle.italic,
                          color: const Color(0xFFE86A33),
                          height: 1.1,
                        ),
                      ),
                      Text(
                        '.',
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Conecta con vecinos que necesitan una mano — o ofrece tus habilidades cuando tengas tiempo libre. Sin agencias, sin intermediarios.',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            // How it works
            Container(
              constraints: const BoxConstraints(maxWidth: 900),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
              child: Column(
                children: [
                  Text(
                    'Cómo funciona',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Wrap(
                    spacing: 24,
                    runSpacing: 24,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildStep(
                        '1',
                        'Publica lo que necesitas',
                        '"Necesito ayuda para pintar mi valla este sábado" — pon tu precio o tarifa por hora.',
                      ),
                      _buildStep(
                        '2',
                        'O comparte tu tiempo',
                        'Muestra cuándo estás disponible. Deja que te encuentren cuando necesiten ayuda.',
                      ),
                      _buildStep(
                        '3',
                        'Conecta y listo',
                        'Mensajea, acuerda las condiciones, completa el trabajo. El pago se guarda seguro hasta que ambos estéis contentos.',
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // CTA Section - Different UI for helper vs seeker
            Container(
              constraints: const BoxConstraints(maxWidth: 900),
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
              padding: const EdgeInsets.all(48),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE86A33).withOpacity(0.1),
                    blurRadius: 24,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  if (_userType == 'seeker') ...[
                    // Seeker UI - Post a job
                    Text(
                      '¿Necesitas ayuda?',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Publica un trabajo y encuentra manitas en tu barrio',
                      style: TextStyle(
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const PostJobScreen(),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE86A33),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Publicar un trabajo',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ] else if (_userType == 'helper') ...[
                    // Helper UI - Post availability
                    Text(
                      '¿Tienes tiempo libre?',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Comparte tu disponibilidad y busca trabajos en tu zona',
                      style: TextStyle(
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          // TODO: Navigate to post availability
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Función de disponibilidad próximamente'),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE86A33),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Publicar disponibilidad',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const BrowseJobsScreen(),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFE86A33),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(
                            color: Color(0xFFE86A33),
                            width: 2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Buscar trabajos disponibles',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Features
            Container(
              constraints: const BoxConstraints(maxWidth: 900),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                children: [
                  Text(
                    '¿Qué hace diferente a Mi Manitas?',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildFeature(
                        '📅',
                        'Horarios flexibles',
                        'Muestra tu disponibilidad real. Perfecto para trabajadores por turnos y estudiantes.',
                      ),
                      _buildFeature(
                        '🔒',
                        'Pago seguro',
                        'El dinero se guarda en depósito hasta que el trabajo esté bien hecho.',
                      ),
                      _buildFeature(
                        '📍',
                        'Hiperlocal',
                        'Hecho para tu barrio, no un marketplace global sin alma.',
                      ),
                      _buildFeature(
                        '🚗',
                        'Opción de recogida',
                        'Los manitas pueden ofrecerte recogerte si estás a las afueras.',
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey[200]!),
                ),
              ),
              child: Text(
                'Hecho con 🔧 en Alicante',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(String number, String title, String description) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE86A33).withOpacity(0.1),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFE86A33),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeature(String icon, String title, String description) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            icon,
            style: const TextStyle(fontSize: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
