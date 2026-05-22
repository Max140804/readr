import 'package:flutter/services.dart';
import 'package:excel/excel.dart';
import '../models/student_model.dart';

class ExcelService {
  static Future<List<Student>> loadStudents() async {
    try {
      final ByteData data = await rootBundle.load('assets/ELECTRONICS AND COMPUTER ENG 2026 BATCH A-6 MONTHS.xlsx');
      final bytes = data.buffer.asUint8List();
      final Excel excel = Excel.decodeBytes(bytes);

      if (excel.tables.isEmpty) return [];
      
      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName];
      List<Student> students = [];

      if (sheet == null) return students;

      // The Excel file has headers. Data typically starts from row 5 (index 4).
      for (int i = 4; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (row.length < 4) continue;

        // Extracting data from columns: B (index 1), C (index 2), D (index 3)
        final regNumber = row[1]?.value?.toString().trim() ?? '';
        final surname = row[2]?.value?.toString().trim() ?? '';
        final firstName = row[3]?.value?.toString().trim() ?? '';

        if (regNumber.isEmpty) continue;

        students.add(
          Student(
            regNumber: regNumber,
            surname: surname,
            firstName: firstName,
          ),
        );
      }
      return students;
    } catch (e) {
      // Return empty list on error
      return [];
    }
  }
}
