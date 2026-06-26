class Assignment {
  final String? id;
  final String course;
  final String questions;
  final DateTime dueDate;
  final DateTime createdAt;

  Assignment({
    this.id,
    required this.course,
    required this.questions,
    required this.dueDate,
    required this.createdAt,
  });

  factory Assignment.fromJson(Map<String, dynamic> json) {
    return Assignment(
      id: json['id']?.toString(),
      course: json['course'] ?? '',
      questions: json['questions'] ?? '',
      dueDate: DateTime.parse(json['due_date']),
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'course': course,
      'questions': questions,
      'due_date': dueDate.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}
