import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import 'data/timetable_data.dart';
import 'login_page.dart';
import 'dashboard.dart';

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
      duration: const Duration(milliseconds: 3200),
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

    _mainController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 800), _checkLoginStatus);
      }
    });
  }

  @override
  void dispose() {
    _mainController.dispose();
    _pulseController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    
    if (!mounted) return;

    Widget targetPage;
    if (isLoggedIn) {
      final String userName = prefs.getString('userName') ?? 'Student';
      final bool isAdmin = prefs.getBool('isAdmin') ?? false;
      targetPage = Dashboard(userName: userName, isAdmin: isAdmin);
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
            child: ScaleTransition(
              scale: Tween<double>(begin: 1.05, end: 1.0).animate(animation),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 1000),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AcademicTheme.primary,
      body: Stack(
        children: [
          // 1. Particle Background
          AnimatedBuilder(
            animation: _particleController,
            builder: (context, child) {
              return CustomPaint(
                painter: ParticlePainter(_particles, _particleController.value),
                size: Size.infinite,
              );
            },
          ),

          // 2. Texture Layer
          AnimatedBuilder(
            animation: _bgScale,
            builder: (context, child) {
              return Transform.scale(
                scale: _bgScale.value,
                child: Opacity(
                  opacity: 0.08,
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

          // 3. Center Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo Section
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Glow Effect
                    FadeTransition(
                      opacity: _glowOpacity,
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Container(
                            width: 200 + (_pulseController.value * 40),
                            height: 200 + (_pulseController.value * 40),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  AcademicTheme.accent.withOpacity(0.2),
                                  AcademicTheme.accent.withOpacity(0.0),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // Main Logo Circle
                    ScaleTransition(
                      scale: _logoScale,
                      child: FadeTransition(
                        opacity: _logoOpacity,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 40,
                                offset: const Offset(0, 15),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(25),
                          child: Image.asset(
                            'assets/logo.png',
                            errorBuilder: (context, error, stackTrace) => const Icon(
                              Icons.menu_book_rounded,
                              size: 75,
                              color: AcademicTheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 50),

                // Text Section
                AnimatedBuilder(
                  animation: _mainController,
                  builder: (context, child) {
                    return FadeTransition(
                      opacity: _contentFade,
                      child: Column(
                        children: [
                          Text(
                            "Readr",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 52,
                              fontWeight: FontWeight.w900,
                              letterSpacing: _textTracking.value,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withOpacity(0.3),
                                  offset: const Offset(0, 5),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(color: Colors.white.withOpacity(0.25)),
                            ),
                            child: const Text(
                              "UNLEASH YOUR POTENTIAL",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 3,
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

          // 4. Loading Indicator at Bottom
          Positioned(
            bottom: 70,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _contentFade,
              child: const Column(
                children: [
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AcademicTheme.accent),
                    ),
                  ),
                  SizedBox(height: 15),
                  Text(
                    "Loading your universe...",
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
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
      
      paint.color = Colors.white.withOpacity(particle.opacity);
      canvas.drawCircle(Offset(xPos, yPos), particle.size, paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
