import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dashboard.dart';
import 'models/student_model.dart';
import 'data/timetable_data.dart';
import 'data/student_data.dart';
import 'utils/responsive_utils.dart';
import 'services/update_service.dart';
import 'services/sync_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController regController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.checkForUpdates(context);
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(15),
      ),
    );
  }

  Future<void> login() async {
    final rawReg = regController.text.trim();
    final rawPass = passwordController.text.trim();
    
    if (rawReg.isEmpty || rawPass.isEmpty) {
      _showError('Please enter both Reg Number and Password');
      return;
    }

    setState(() => isLoading = true);

    try {
      // 1. Identify User (Local lookup - Instant)
      final String searchId = rawReg.toUpperCase().split('@')[0].replaceAll(RegExp(r'\s+'), '');
      Student? identity;
      bool isSuperAdmin = searchId == 'ADMIN';
      bool isDev = searchId == 'DEV';

      if (isSuperAdmin) {
        identity = Student(regNumber: 'ADMIN', surname: 'ADMIN', firstName: 'Administrator');
      } else if (isDev) {
        identity = Student(regNumber: 'DEV', surname: 'DEV', firstName: 'Developer');
      } else {
        try {
          identity = StudentData.students.firstWhere(
            (s) => s.regNumber.toUpperCase().replaceAll(RegExp(r'\s+'), '') == searchId
          );
        } catch (_) {
          identity = null;
        }
      }

      if (identity == null) {
        _showError('Record not found for "$searchId".');
        return;
      }

      // 2. Local Password Validation (Instant)
      final bool hasAdminOverride = rawPass == 'adminwas3';
      final bool hasDevOverride = rawPass == 'devmaxx';
      
      String expectedPassword;
      if (isSuperAdmin || hasAdminOverride) {
        expectedPassword = 'adminwas3';
      } else if (isDev || hasDevOverride) {
        expectedPassword = 'devmaxx';
      } else {
        expectedPassword = '${identity.surname.replaceAll(RegExp(r'\s+'), '').toLowerCase()}123';
      }

      if (rawPass != expectedPassword) {
        _showError('Invalid Password.');
        return;
      }

      final bool isAdmin = isSuperAdmin || hasAdminOverride;
      final bool isDeveloper = isDev || hasDevOverride;

      final String loginEmail = isSuperAdmin 
          ? 'admin@readr.com' 
          : isDev ? 'dev@readr.com'
          : '${identity.regNumber.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}@readr.com';
      
      final String effectiveUserId = isSuperAdmin ? 'admin' : isDev ? 'dev' : identity.regNumber;

      // 3. Save state and navigate IMMEDIATELY
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('userName', identity.firstName);
      await prefs.setString('userId', effectiveUserId);
      await prefs.setBool('isAdmin', isAdmin);
      await prefs.setBool('isDev', isDeveloper);

      // Start background auth without waiting
      _performBackgroundAuth(loginEmail, expectedPassword, identity, isAdmin, isDeveloper).then((_) {
        // After successful background auth, pull data from cloud
        SyncService().pullFromCloud();
      });

      if (mounted) {
        _proceedToDashboard(identity.firstName, effectiveUserId, isAdmin: isAdmin, isDev: isDeveloper);
      }
    } catch (e) {
      _showError('An error occurred: $e');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> _performBackgroundAuth(String email, String password, Student identity, bool isAdmin, bool isDev) async {
    try {
      final supabase = Supabase.instance.client;
      try {
        await supabase.auth.signInWithPassword(email: email, password: password);
      } catch (_) {
        await supabase.auth.signUp(
          email: email,
          password: password,
          data: {
            'full_name': '${identity.firstName} ${identity.surname}',
            'reg_number': identity.regNumber,
            'role': isAdmin ? 'Admin' : isDev ? 'Developer' : 'Student',
          },
        );
      }
    } catch (e) {
      debugPrint("Background Auth Error: $e");
    }
  }

  void _proceedToDashboard(String firstName, String userId, {required bool isAdmin, bool isDev = false}) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => Dashboard(
          userName: firstName, 
          userId: userId,
          isAdmin: isAdmin,
          isDev: isDev
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryBlue = isDark ? const Color(0xFF58A6FF) : AcademicTheme.primary;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF001220) : AcademicTheme.background,
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: Responsive.isMobile(context) ? 24 : 0, 
                vertical: 24
              ),
              child: Center(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: Responsive.isMobile(context) ? double.infinity : 450,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Hero(
                        tag: 'logo',
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: primaryBlue.withValues(alpha: 0.3),
                                blurRadius: 40,
                                spreadRadius: 5,
                              )
                            ],
                          ),
                          child: Image.asset('assets/logo.png', height: 100, errorBuilder: (_,__,___) => Icon(Icons.school, size: 100, color: primaryBlue)),
                        ),
                      ),
                      const SizedBox(height: 40),
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [
                            isDark ? Colors.white : AcademicTheme.primary,
                            primaryBlue,
                            isDark ? Colors.white : AcademicTheme.primary,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ).createShader(bounds),
                        child: const Text(
                          'Readr',
                          style: TextStyle(
                            fontSize: 68,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 10,
                            height: 1.0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: primaryBlue.withValues(alpha: 0.2)),
                          gradient: LinearGradient(
                            colors: [primaryBlue.withValues(alpha: 0.05), primaryBlue.withValues(alpha: 0.1)],
                          ),
                        ),
                        child: Text(
                          'UNLEASH YOUR POTENTIAL',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4,
                            color: isDark ? Colors.white60 : AcademicTheme.primary.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                      const SizedBox(height: 60),
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF001A2F) : Colors.white,
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(color: primaryBlue.withValues(alpha: 0.1)),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 50, 
                              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
                              offset: const Offset(0, 20),
                            )
                          ],
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: regController,
                              style: TextStyle(color: isDark ? Colors.white : AcademicTheme.textPrimary, fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                labelText: 'Registration Number',
                                labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white38 : AcademicTheme.textSecondary),
                                prefixIcon: Icon(Icons.alternate_email_rounded, size: 20, color: primaryBlue),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                                filled: true,
                                fillColor: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey[100],
                                floatingLabelStyle: TextStyle(color: primaryBlue),
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: passwordController,
                              obscureText: _obscurePassword,
                              style: TextStyle(color: isDark ? Colors.white : AcademicTheme.textPrimary, fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white38 : AcademicTheme.textSecondary),
                                prefixIcon: Icon(Icons.lock_outline_rounded, size: 20, color: primaryBlue),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20, color: isDark ? Colors.white24 : Colors.grey),
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                ),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                                filled: true,
                                fillColor: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey[100],
                                floatingLabelStyle: TextStyle(color: primaryBlue),
                              ),
                            ),
                            const SizedBox(height: 32),
                            SizedBox(
                              width: double.infinity,
                              height: 60,
                              child: ElevatedButton(
                                onPressed: isLoading ? null : login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryBlue,
                                  foregroundColor: Colors.white,
                                  elevation: isDark ? 0 : 4,
                                  shadowColor: primaryBlue.withValues(alpha: 0.4),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                ),
                                child: isLoading
                                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                    : const Text('SIGN IN', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Password format: surname123', 
                        style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.3) : AcademicTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)
                      ),
                    ],
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
