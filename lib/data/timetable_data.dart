import 'package:flutter/material.dart';

class AcademicTheme {
  // Light Mode Colors
  static const background = Color(0xFFE3F2FD); // Light Blue Background
  static const card = Color(0xFFFFFFFF);
  static const primary = Color(0xFF1A237E); // Navy Blue
  static const secondary = Color(0xFF283593);
  static const accent = Color(0xFFC5A059); // Muted Gold
  static const textPrimary = Color(0xFF212121);
  static const textSecondary = Color(0xFF757575);

  // Dark Mode Colors
  static const darkBackground = Color(0xFF0D1117);
  static const darkCard = Color(0xFF161B22);
  static const darkPrimary = Color(0xFF58A6FF); // Lighter blue for dark mode
  static const darkSecondary = Color(0xFF1F6FEB);
  static const darkAccent = Color(0xFFE3B341);
  static const darkTextPrimary = Color(0xFFC9D1D9);
  static const darkTextSecondary = Color(0xFF8B949E);
}

const Map<String, List<Map<String, String>>> timetable = {
  "Monday": [
    {"time": "9:00 AM - 11:00 AM", "course": "ECE 505"},
    {"time": "11:00 AM - 1:00 PM", "course": "ECE 541"},
    {"time": "1:00 PM - 3:00 PM", "course": "ECE 529"},
    {"time": "3:00 PM - 5:00 PM", "course": "ECE 539 (Lab)"},
  ],
  "Tuesday": [
    {"time": "9:00 AM - 11:00 AM", "course": "ECE 527"},
    {"time": "11:00 AM - 1:00 PM", "course": "ECE 517"},
    {"time": "1:00 PM - 3:00 PM", "course": "ECE 537"},
  ],
  "Wednesday": [
    {"time": "9:00 AM - 11:00 AM", "course": "ECE 531"},
    {"time": "11:00 AM - 1:00 PM", "course": "ECE 505 (Lab)"},
    {"time": "1:00 PM - 3:00 PM", "course": "ECE 529 (Lab)"},
  ],
  "Thursday": [
    {"time": "9:00 AM - 11:00 AM", "course": "ECE 539"},
    {"time": "11:00 AM - 1:00 PM", "course": "ECE 527 (Lab)"},
    {"time": "1:00 PM - 3:00 PM", "course": "ECE 535"},
  ],
  "Friday": [],
};