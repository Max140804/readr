import 'package:flutter/material.dart';
import 'data/timetable_data.dart';

class DuesPage extends StatelessWidget {
  const DuesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Mock data for departmental/faculty dues
    final List<Map<String, dynamic>> dues = [
      {
        "title": "Departmental Dues",
        "amount": "₦5,000",
        "status": "Unpaid",
        "deadline": "Nov 30, 2024",
        "icon": Icons.account_balance,
        "color": Colors.blue,
      },
      {
        "title": "Faculty Dues",
        "amount": "₦3,500",
        "status": "Paid",
        "deadline": "Completed",
        "icon": Icons.school,
        "color": Colors.green,
      },
      {
        "title": "Lab Fees",
        "amount": "₦2,000",
        "status": "Unpaid",
        "deadline": "Oct 15, 2024",
        "icon": Icons.science,
        "color": Colors.orange,
      },
    ];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Dues & Payments", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: AcademicTheme.primary,
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Summary Card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AcademicTheme.secondary, AcademicTheme.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: AcademicTheme.primary.withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Total Outstanding",
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                const Text(
                  "₦7,000",
                  style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    "3 Pending Payments",
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: dues.length,
              itemBuilder: (context, index) {
                final item = dues[index];
                final bool isPaid = item["status"] == "Paid";

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? AcademicTheme.darkCard : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: item["color"].withOpacity(0.1),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(item["icon"], color: item["color"]),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item["title"],
                              style: TextStyle(
                                fontWeight: FontWeight.bold, 
                                fontSize: 16,
                                color: isDark ? AcademicTheme.darkTextPrimary : AcademicTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Deadline: ${item["deadline"]}",
                              style: TextStyle(
                                color: isDark ? AcademicTheme.darkTextSecondary : Colors.grey[600], 
                                fontSize: 12
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            item["amount"],
                            style: TextStyle(
                              fontWeight: FontWeight.bold, 
                              fontSize: 16, 
                              color: isDark ? AcademicTheme.darkPrimary : AcademicTheme.primary
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isPaid ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              item["status"],
                              style: TextStyle(
                                color: isPaid ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        backgroundColor: AcademicTheme.primary,
        icon: const Icon(Icons.receipt_long, color: Colors.white),
        label: const Text("History", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
