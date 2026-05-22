import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dashboard.dart';
import 'models/student_model.dart';
import 'data/timetable_data.dart';
import 'data/student_data.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController regController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isLoading = false;

  void login() {
    setState(() {
      isLoading = true;
    });

    final regNumber = regController.text.trim();
    final password = passwordController.text.trim();

    // ADMIN LOGIN
    if (regNumber.toLowerCase() == 'admin' &&
        password == 'adminwas3') {
      _proceedToDashboard('Admin', isAdmin: true);
      return;
    }

    Student? matchedStudent;

    // Normalize user input
    final searchReg = regNumber.toUpperCase();
    final searchPass = password.toLowerCase();

    for (final student in StudentData.students) {
      // Match surname123 (e.g., Nnamani -> nnamani123)
      final generatedPassword = '${student.surname.toLowerCase()}123';
      
      if (student.regNumber.toUpperCase() == searchReg &&
          generatedPassword == searchPass) {
        matchedStudent = student;
        break;
      }
    }

    setState(() {
      isLoading = false;
    });

    if (matchedStudent != null) {
      _saveLoginState(matchedStudent.firstName, false);
      _proceedToDashboard(matchedStudent.firstName, isAdmin: false);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid Registration Number or Password')),
      );
    }
  }

  Future<void> _saveLoginState(String userName, bool isAdmin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('userName', userName);
    await prefs.setBool('isAdmin', isAdmin);
  }

  void _proceedToDashboard(String firstName, {required bool isAdmin}) {
    if (isAdmin) {
      _saveLoginState(firstName, true);
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => Dashboard(userName: firstName, isAdmin: isAdmin),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AcademicTheme.darkBackground : AcademicTheme.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? AcademicTheme.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  blurRadius: 10,
                  color: Colors.black.withOpacity(isDark ? 0.3 : 0.1),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[900] : Colors.white,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(15),
                  child: Image.asset(
                    'assets/logo.png',
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.school,
                      size: 60,
                      color: isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Welcome to Readr, Scholr!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary,
                  ),
                ),
                const SizedBox(height: 30),
                TextField(
                  controller: regController,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    labelText: 'Reg Number',
                    labelStyle: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
                    prefixIcon: Icon(Icons.person_outline, color: isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
                    prefixIcon: Icon(Icons.lock_outline, color: isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary,
                      foregroundColor: isDark ? Colors.black : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: isLoading
                        ? CircularProgressIndicator(color: isDark ? Colors.black : Colors.white)
                        : const Text(
                            'LOGIN',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Password format: surname123',
                  style: TextStyle(color: isDark ? Colors.grey[500] : Colors.grey[600]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
