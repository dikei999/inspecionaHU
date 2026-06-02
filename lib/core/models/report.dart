class Report {
  final String id;
  final String inspectionId;
  final String hospitalId;
  final String sectorId;
  final int totalItems;
  final int compliant;
  final int nonCompliant;
  final int notApplicable;
  final double complianceRate; // ex: 87.50
  final String? pdfUrl;
  final String? excelUrl;
  final DateTime generatedAt;

  const Report({
    required this.id,
    required this.inspectionId,
    required this.hospitalId,
    required this.sectorId,
    required this.totalItems,
    required this.compliant,
    required this.nonCompliant,
    required this.notApplicable,
    required this.complianceRate,
    this.pdfUrl,
    this.excelUrl,
    required this.generatedAt,
  });

  factory Report.fromJson(Map<String, dynamic> json) => Report(
        id: json['id'] as String,
        inspectionId: json['inspection_id'] as String,
        hospitalId: json['hospital_id'] as String,
        sectorId: json['sector_id'] as String,
        totalItems: json['total_items'] as int,
        compliant: json['compliant'] as int,
        nonCompliant: json['non_compliant'] as int,
        notApplicable: json['not_applicable'] as int,
        complianceRate: (json['compliance_rate'] as num).toDouble(),
        pdfUrl: json['pdf_url'] as String?,
        excelUrl: json['excel_url'] as String?,
        generatedAt: DateTime.parse(json['generated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'inspection_id': inspectionId,
        'hospital_id': hospitalId,
        'sector_id': sectorId,
        'total_items': totalItems,
        'compliant': compliant,
        'non_compliant': nonCompliant,
        'not_applicable': notApplicable,
        'compliance_rate': complianceRate,
        'pdf_url': pdfUrl,
        'excel_url': excelUrl,
        'generated_at': generatedAt.toIso8601String(),
      };
}
