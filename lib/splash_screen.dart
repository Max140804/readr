import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import 'login_page.dart';
import 'dashboard.dart';
import 'data/timetable_data.dart';
import 'services/update_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _pulseController;
  late AnimationController _particleController;
  
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _contentFade;
  late Animation<double> _bgScale;
  late Animation<double> _textTracking;
  late Animation<double> _glowOpacity;

  final List<Particle> _particles = List.generate(25, (index) => Particle());

  @override
  void initState() {
    super.initState();
    
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();

    _logoScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.15).chain(CurveTween(curve: Curves.easeOutBack)), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 55),
    ]).animate(_mainController);

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _mainController, curve: const Interval(0.0, 0.4, curve: Curves.easeIn)),
    );

    _contentFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _mainController, curve: const Interval(0.5, 0.85, curve: Curves.easeIn)),
    );

    _bgScale = Tween<double>(begin: 1.4, end: 1.0).animate(
      CurvedAnimation(parent: _mainController, curve: const Interval(0.0, 1.0, curve: Curves.linearToEaseOut)),
    );

    _textTracking = Tween<double>(begin: 18.0, end: 6.0).animate(
      CurvedAnimation(parent: _mainController, curve: const Interval(0.5, 0.95, curve: Curves.fastLinearToSlowEaseIn)),
    );

    _glowOpacity = Tween<double>(begin: 0.0, end: 0.6).animate(
      CurvedAnimation(parent: _mainController, curve: const Interval(0.3, 0.7, curve: Curves.easeIn)),
    );

    _mainController.forward();

    // Safe, non-blocking navigation and update check
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.checkForUpdates(context);
      Future.delayed(const Duration(milliseconds: 2200), _checkAuthAndNavigate);
    });
  }

  Future<void> _checkAuthAndNavigate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

      if (!mounted) return;

      Widget targetPage;
      if (isLoggedIn) {
        final String userName = prefs.getString('userName') ?? 'Student';
        final String userId = prefs.getString('userId') ?? 'user';
        final bool isAdmin = prefs.getBool('isAdmin') ?? false;
        targetPage = Dashboard(userName: userName, userId: userId, isAdmin: isAdmin);
      } else {
        targetPage = const LoginPage();
      }

      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => targetPage,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
    } catch (_) {
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
    }
  }

  @override
  void dispose() {
    _mainController.dispose();
    _pulseController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. Premium Gradient Background
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [
                  Color(0xFF283593), // Lighter Navy
                  Color(0xFF1A237E), // Deep Navy
                  Color(0xFF0D1117), // Near Black
                ],
                stops: [0.0, 0.6, 1.0],
              ),
            ),
          ),

          // 2. Particle Background
          AnimatedBuilder(
            animation: _particleController,
            builder: (context, child) {
              return CustomPaint(
                painter: ParticlePainter(_particles, _particleController.value),
                size: Size.infinite,
              );
            },
          ),

          // 3. Texture Layer (Subtle)
          AnimatedBuilder(
            animation: _bgScale,
            builder: (context, child) {
              return Transform.scale(
                scale: _bgScale.value,
                child: Opacity(
                  opacity: 0.05,
                  child: Image.asset(
                    'assets/pattern.png',
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (context, error, stackTrace) => Container(),
                  ),
                ),
              );
            },
          ),

          // 4. Center Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Enhanced Glow
                    FadeTransition(
                      opacity: _glowOpacity,
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Container(
                            width: 240 + (_pulseController.value * 60),
                            height: 240 + (_pulseController.value * 60),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  const Color(0xFFC5A059).withValues(alpha: 0.15),
                                  const Color(0xFFC5A059).withValues(alpha: 0.0),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // Main Logo Container
                    ScaleTransition(
                      scale: _logoScale,
                      child: FadeTransition(
                        opacity: _logoOpacity,
                        child: Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 50,
                                offset: const Offset(0, 20),
                              ),
                              BoxShadow(
                                color: const Color(0xFFC5A059).withValues(alpha: 0.3),
                                blurRadius: 20,
                                spreadRadius: -5,
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(28),
                          child: Image.asset(
                            'assets/logo.png',
                            errorBuilder: (context, error, stackTrace) => const Icon(
                              Icons.menu_book_rounded,
                              size: 80,
                              color: Color(0xFF1A237E),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 60),

                // Text Section with Shimmer effect (via opacity/gradient)
                AnimatedBuilder(
                  animation: _mainController,
                  builder: (context, child) {
                    return FadeTransition(
                      opacity: _contentFade,
                      child: Column(
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [Colors.white, Color(0xFFC5A059), Colors.white],
                              stops: [0.0, 0.5, 1.0],
                            ).createShader(bounds),
                            child: Text(
                              "Readr",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 58,
                                fontWeight: FontWeight.w900,
                                letterSpacing: _textTracking.value,
                              ),
                            ),
                          ),
                          const SizedBox(height: 15),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(40),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0.05),
                                  Colors.white.withValues(alpha: 0.1),
                                ],
                              ),
                            ),
                            child: const Text(
                              "UNLEASH YOUR POTENTIAL",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Minimal Loading Indicator
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _contentFade,
              child: Center(
                child: SizedBox(
                  width: 40,
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFC5A059)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Particle {
  late double x;
  late double y;
  late double size;
  late double speed;
  late double opacity;

  Particle() {
    restart();
  }

  void restart() {
    x = math.Random().nextDouble();
    y = math.Random().nextDouble();
    size = math.Random().nextDouble() * 2.5 + 0.5;
    speed = math.Random().nextDouble() * 0.03 + 0.005;
    opacity = math.Random().nextDouble() * 0.4 + 0.1;
  }
}

class ParticlePainter extends CustomPainter {
  final List<Particle> particles;
  final double animationValue;

  ParticlePainter(this.particles, this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var particle in particles) {
      final yPos = ((particle.y - animationValue * particle.speed) % 1.0) * size.height;
      final xPos = particle.x * size.width;
      paint.color = Colors.white.withValues(alpha: particle.opacity);
      canvas.drawCircle(Offset(xPos, yPos), particle.size, paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
