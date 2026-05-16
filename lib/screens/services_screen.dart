import 'package:flutter/material.dart';
import 'package:malak/config/api_config.dart';

class ServicesPage extends StatefulWidget {
  const ServicesPage({super.key});

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  String _activeTab = 'all';

  final List<Map<String, dynamic>> _services = [
    {
      'id': 1,
      'title': 'Cardiology',
      'description':
          'Comprehensive heart care including advanced diagnostics, treatment, and prevention of cardiovascular diseases with state-of-the-art technology.',
      'icon': Icons.favorite_outlined,
      'category': 'specialty',
      'comingSoon': true,
      'features': ['ECG Testing', 'Heart Monitoring', 'Preventive Care'],
    },
    {
      'id': 2,
      'title': 'Primary Care',
      'description':
          'Regular check-ups, preventive care, and treatment for common illnesses and minor injuries with personalized attention.',
      'icon': Icons.local_hospital,
      'category': 'general',
      'comingSoon': true,
      'features': [
        'Annual Physicals',
        'Chronic Disease Management',
        'Wellness Exams',
      ],
    },
    {
      'id': 3,
      'title': 'Neurology',
      'description':
          'Specialized care for disorders of the nervous system, brain, and spinal cord with cutting-edge diagnostic tools.',
      'icon': Icons.psychology,
      'category': 'specialty',
      'comingSoon': true,
      'features': ['Brain Imaging', 'Neurological Exams', 'Treatment Plans'],
    },
    {
      'id': 4,
      'title': 'Pediatrics',
      'description':
          'Complete healthcare for infants, children, and adolescents, from wellness visits to specialized developmental care.',
      'icon': Icons.child_care,
      'category': 'general',
      'comingSoon': true,
      'features': ['Well-Child Visits', 'Vaccinations', 'Growth Monitoring'],
    },
    {
      'id': 5,
      'title': 'Pharmacy',
      'description':
          'On-site pharmacy services with personalized medication management, consultation, and convenient prescription fulfillment.',
      'icon': Icons.medication,
      'category': 'support',
      'comingSoon': true,
      'features': [
        'Prescription Fulfillment',
        'Drug Interactions',
        'Consultation',
      ],
    },
    {
      'id': 6,
      'title': 'Emergency Care',
      'description':
          '24/7 emergency medical services for critical conditions requiring immediate attention from experienced emergency physicians.',
      'icon': Icons.emergency,
      'category': 'emergency',
      'comingSoon': true,
      'features': ['24/7 Availability', 'Rapid Response', 'Critical Care'],
    },
  ];

  final List<Map<String, dynamic>> _categories = [];

  @override
  void initState() {
    super.initState();
    _buildCategories();
  }

  void _buildCategories() {
    _categories.addAll([
      {'id': 'all', 'label': 'All Services'},
      {'id': 'general', 'label': 'General Care'},
      {'id': 'specialty', 'label': 'Specialty Care'},
      {'id': 'emergency', 'label': 'Emergency'},
      {'id': 'support', 'label': 'Support Services'},
    ]);
  }

  List<Map<String, dynamic>> get _filteredServices => _activeTab == 'all'
      ? _services
      : _services.where((s) => s['category'] == _activeTab).toList();

  int _categoryCount(String id) => id == 'all'
      ? _services.length
      : _services.where((s) => s['category'] == id).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: CustomScrollView(
        slivers: [
          // Hero Section
          SliverToBoxAdapter(child: _buildHero()),

          // Category Tabs
          SliverToBoxAdapter(child: _buildCategoryTabs()),

          // Services Grid
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildServiceCard(_filteredServices[index]),
                ),
                childCount: _filteredServices.length,
              ),
            ),
          ),

          // Stats Section
          SliverToBoxAdapter(child: _buildStats()),

          // CTA Section
          SliverToBoxAdapter(child: _buildCTA()),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2563EB), Color(0xFF1D4ED8), Color(0xFF1E40AF)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 40),
      child: Column(
        children: [
          // Coming Soon Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.access_time, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text(
                  'Coming Soon — Launching 2026',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Our Medical Services',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Providing comprehensive healthcare services with cutting-edge technology and compassionate care for you and your family.',
            style: TextStyle(
              color: Color(0xFFDBEAFE),
              fontSize: 16,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: _heroButton(
                  icon: Icons.calendar_today,
                  label: 'Book an Appointment',
                  onTap: null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _heroButton(
                  icon: Icons.phone,
                  label: 'Contact Us',
                  onTap: null,
                  outlined: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool outlined = false,
  }) {
    return Opacity(
      opacity: 0.6,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: outlined ? Colors.transparent : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: outlined ? Border.all(color: Colors.white, width: 2) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: outlined ? Colors.white : const Color(0xFF1D4ED8),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: outlined ? Colors.white : const Color(0xFF1D4ED8),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTabs() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: _categories.map((cat) {
            final isActive = _activeTab == cat['id'];
            final count = _categoryCount(cat['id']);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _activeTab = cat['id']),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFF2563EB)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: const Color(0xFF2563EB).withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    children: [
                      Text(
                        cat['label'],
                        style: TextStyle(
                          color: isActive
                              ? Colors.white
                              : const Color(0xFF6B7280),
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFF3B82F6)
                              : const Color(0xFFE5E7EB),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            color: isActive
                                ? Colors.white
                                : const Color(0xFF6B7280),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> service) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFF3F4F6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    service['icon'] as IconData,
                    color: const Color(0xFF2563EB),
                    size: 32,
                  ),
                ),
                if (service['comingSoon'] == true)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.access_time, color: Colors.white, size: 12),
                        SizedBox(width: 4),
                        Text(
                          'Coming Soon',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              service['title'],
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              service['description'],
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 14,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 16),
            ...(service['features'] as List<String>).map(
              (feature) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Color(0xFF2563EB),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      feature,
                      style: const TextStyle(
                        color: Color(0xFF374151),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Opacity(
              opacity: 0.6,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Learn More',
                      style: TextStyle(
                        color: Color(0xFF2563EB),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward,
                      color: Color(0xFF2563EB),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats() {
    final stats = [
      {'value': '6+', 'label': 'Medical Services'},
      {'value': '24/7', 'label': 'Emergency Care'},
      {'value': '100%', 'label': 'Digital Platform'},
      {'value': '2026', 'label': 'Launch Year'},
    ];

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 2.2,
        children: stats
            .map(
              (s) => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    s['value']!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    s['label']!,
                    style: const TextStyle(
                      color: Color(0xFFBFDBFE),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildCTA() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2563EB).withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const Text(
              'Ready to Experience Better Healthcare?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Our team of healthcare professionals will be ready to provide you with the best medical care. Be among the first to know when we launch.',
              style: TextStyle(
                color: Color(0xFFDBEAFE),
                fontSize: 14,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF2563EB),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                    child: const Text(
                      'Join Waitlist',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white, width: 2),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Explore All',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
