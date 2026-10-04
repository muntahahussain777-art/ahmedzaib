import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'closing2_models.dart';
import '../models/models.dart';

class VipExportService {
  static final _money = NumberFormat('#,##0.##');

  static Future<Directory> _dir() async {
    final d = await getTemporaryDirectory();
    final out = Directory(p.join(d.path, 'zaib_exports'));
    if (!await out.exists()) await out.create(recursive: true);
    return out;
  }

  static Future<void> shareFile(String path, {String? subject}) async {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], subject: subject ?? 'Zaib Petroleum Service'),
    );
  }

  // ---------------- Closing 2 ----------------

  static Future<String> closing2Excel(Closing2Report r, {required String from, required String to}) async {
    final sb = StringBuffer();
    sb.writeln('Zaib Petroleum Service - Closing 2');
    sb.writeln('From,$from');
    sb.writeln('To,$to');
    sb.writeln();
    sb.writeln('Sale Avg,Dealer Avg,Margin,Liters,Gross,Expense,Net');
    sb.writeln('${r.custAvg},${r.dealerAvg},${r.margin},${r.customerLit},${r.grossProfit},${r.expense},${r.netProfit}');
    sb.writeln();
    sb.writeln('Customer Total,Dealer Total,Balance');
    sb.writeln('${r.customerTotal},${r.dealerTotal},${r.balance}');
    sb.writeln();
    sb.writeln('Receivable Name,Receivable Amount,Payable Name,Payable Amount');
    final max = r.receivables.length > r.payables.length ? r.receivables.length : r.payables.length;
    for (var i = 0; i < max; i++) {
      final a = i < r.receivables.length ? r.receivables[i] : null;
      final b = i < r.payables.length ? r.payables[i] : null;
      sb.writeln('${_csv(a?.name)},${a?.amount ?? ''},${_csv(b?.name)},${b?.amount ?? ''}');
    }
    final path = p.join((await _dir()).path, 'Closing2_${_stamp()}.csv');
    await File(path).writeAsString('\uFEFF${sb.toString()}');
    return path;
  }

  static Future<String> closing2Pdf(Closing2Report r, {required String from, required String to}) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          _header('Closing 2 Report'),
          pw.Text('From: $from   To: $to', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 12),
          _kpiTable([
            ['Sale Avg', _money.format(r.custAvg), 'Dealer Avg', _money.format(r.dealerAvg)],
            ['Margin/L', _money.format(r.margin), 'Liters', _money.format(r.customerLit)],
            ['Gross', _money.format(r.grossProfit), 'Expense', _money.format(r.expense)],
            ['Net', _money.format(r.netProfit), 'Balance', _money.format(r.balance)],
            ['Customer Total', _money.format(r.customerTotal), 'Dealer Total', _money.format(r.dealerTotal)],
          ]),
          pw.SizedBox(height: 14),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _namedList('Receivable', r.receivables)),
              pw.SizedBox(width: 12),
              pw.Expanded(child: _namedList('Payable', r.payables)),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text('Developed by Irtaza Hussain', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        ],
      ),
    );
    final path = p.join((await _dir()).path, 'Closing2_${_stamp()}.pdf');
    await File(path).writeAsBytes(await doc.save());
    return path;
  }

  // ---------------- Diesel report (PC columns) ----------------

  static List<String> get dieselHeaders => const [
        'pid',
        'Date',
        'ReceiptNo',
        'vehicle',
        'Litter',
        'Rate',
        'Advance',
        'Amount',
        'Credit',
        'Balance',
        'Note',
        'Name',
      ];

  static List<List<String>> dieselRows(List<DieselSale> rows) => rows
      .map(
        (e) => [
          '${e.id ?? ''}',
          e.date,
          e.receiptNo,
          e.vehicle,
          e.litter.toStringAsFixed(2),
          e.rate.toStringAsFixed(2),
          e.advance.toStringAsFixed(2),
          _amountPc(e).toStringAsFixed(2),
          e.credit.toStringAsFixed(2),
          _balancePc(e).toStringAsFixed(2),
          e.note,
          e.customerName,
        ],
      )
      .toList();

  static double _amountPc(DieselSale e) {
    if (e.litter == 0 && e.rate == 0) return e.amount;
    return e.litter * e.rate + e.advance;
  }

  static double _balancePc(DieselSale e) {
    if (e.litter == 0 && e.rate == 0) return e.balance;
    return (e.litter * e.rate + e.advance) - e.credit;
  }

  // ---------------- Dealer group (PC columns) ----------------

  static List<String> get dealerHeaders => const [
        'Did',
        'DealerName',
        'DDAmount_Master',
        'DAmount_Master',
        'Balance_Master',
        'StockDate',
        'VehicleNo',
        'Litter',
        'Rate',
        'Amount',
      ];

  static List<List<String>> dealerRows(List<DealerGroupReportRow> rows) => rows
      .map(
        (e) => [
          '${e.dealerId}',
          e.dealerName,
          e.ddAmount.toStringAsFixed(2),
          e.dAmount.toStringAsFixed(2),
          e.balance.toStringAsFixed(2),
          e.stockDate ?? '',
          e.vehicle,
          e.litter.toStringAsFixed(2),
          e.rate.toStringAsFixed(2),
          e.amount.toStringAsFixed(2),
        ],
      )
      .toList();

  // ---------------- Stock (PC columns) ----------------

  static List<String> get stockHeaders => const [
        'SID',
        'SDid',
        'Date',
        'DealerName',
        'Vehicle',
        'Rate',
        'Litter',
        'Credit',
        'Debit',
        'Note',
      ];

  static List<List<String>> stockRows(List<StockDieselEntry> rows) => rows
      .map(
        (e) => [
          '${e.id ?? ''}',
          '${e.dealerId}',
          e.date,
          e.dealerName,
          e.vehicle,
          e.rate.toStringAsFixed(2),
          e.litter.toStringAsFixed(2),
          e.credit.toStringAsFixed(2),
          e.debit.toStringAsFixed(2),
          e.note,
        ],
      )
      .toList();

  static Future<String> tablePdf({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    String? subtitle,
    List<(String, String)>? footerLines,
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(18),
        build: (ctx) => [
          _header(title),
          if (subtitle != null) ...[
            pw.Text(subtitle, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            pw.SizedBox(height: 8),
          ],
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows,
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1A2744)),
            headerStyle: pw.TextStyle(color: PdfColor.fromInt(0xFFD4AF37), fontWeight: pw.FontWeight.bold, fontSize: 8),
            cellStyle: const pw.TextStyle(fontSize: 7.2, color: PdfColors.black),
            cellAlignment: pw.Alignment.centerLeft,
            border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFD4AF37), width: 0.4),
            headerAlignment: pw.Alignment.center,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF7F1E3)),
          ),
          if (footerLines != null && footerLines.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColor.fromInt(0xFFD4AF37), width: 0.8),
                color: PdfColor.fromInt(0xFF1A2744),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: footerLines
                    .map(
                      (e) => pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 4),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(e.$1, style: pw.TextStyle(color: PdfColor.fromInt(0xFFD4AF37), fontWeight: pw.FontWeight.bold, fontSize: 10)),
                            pw.Text(e.$2, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10)),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
          pw.SizedBox(height: 10),
          pw.Text('Rows: ${rows.length}  |  Zaib Petroleum Service  |  Developed by Irtaza Hussain',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ],
      ),
    );
    final safe = title.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    final path = p.join((await _dir()).path, '${safe}_${_stamp()}.pdf');
    await File(path).writeAsBytes(await doc.save());
    return path;
  }

  static Future<String> tableExcel({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
  }) async {
    final sb = StringBuffer();
    sb.writeln(headers.map(_csv).join(','));
    for (final r in rows) {
      sb.writeln(r.map(_csv).join(','));
    }
    final safe = title.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    final path = p.join((await _dir()).path, '${safe}_${_stamp()}.csv');
    await File(path).writeAsString('\uFEFF${sb.toString()}');
    return path;
  }

  /// Bul Mal VIP PDF — In / Out / Balance + note (red)
  static Future<String> bulMalPdf({
    required String title,
    required List<BulMalEntry> rows,
    required BulMalSummary summary,
    String? subtitle,
  }) async {
    final gold = PdfColor.fromInt(0xFFD4AF37);
    final navy = PdfColor.fromInt(0xFF1A2744);
    final cream = PdfColor.fromInt(0xFFF7F1E3);
    const headers = ['#', 'Owner', 'Date', 'Type', 'Amount', 'Note', 'Running'];

    var run = 0.0;
    final data = <List<String>>[];
    final chronological = rows.reversed.toList();
    for (var i = 0; i < chronological.length; i++) {
      final e = chronological[i];
      if (e.isOut) {
        run -= e.amount;
      } else {
        run += e.amount;
      }
      data.add([
        '${i + 1}',
        e.ownerName,
        e.date,
        e.type,
        _money.format(e.amount),
        e.note,
        _money.format(run),
      ]);
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(18),
        build: (ctx) => [
          _header(title),
          if (subtitle != null && subtitle.trim().isNotEmpty) ...[
            pw.Text(subtitle, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            pw.SizedBox(height: 8),
          ],
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            margin: const pw.EdgeInsets.only(bottom: 10),
            decoration: pw.BoxDecoration(
              color: navy,
              border: pw.Border.all(color: gold, width: 0.8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Text('In: ${_money.format(summary.totalIn)}',
                    style: pw.TextStyle(color: PdfColors.greenAccent, fontWeight: pw.FontWeight.bold, fontSize: 11)),
                pw.Text('Out: ${_money.format(summary.totalOut)}',
                    style: pw.TextStyle(color: PdfColors.redAccent, fontWeight: pw.FontWeight.bold, fontSize: 11)),
                pw.Text('Balance: ${_money.format(summary.balance)}',
                    style: pw.TextStyle(color: gold, fontWeight: pw.FontWeight.bold, fontSize: 11)),
              ],
            ),
          ),
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: data,
            headerDecoration: pw.BoxDecoration(color: navy),
            headerStyle: pw.TextStyle(color: gold, fontWeight: pw.FontWeight.bold, fontSize: 8),
            cellStyle: const pw.TextStyle(fontSize: 7.2, color: PdfColors.black),
            cellAlignment: pw.Alignment.centerLeft,
            border: pw.TableBorder.all(color: gold, width: 0.4),
            headerAlignment: pw.Alignment.center,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
            oddRowDecoration: pw.BoxDecoration(color: cream),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Rows: ${rows.length}  |  Zaib Petroleum Service  |  Developed by Irtaza Hussain',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );
    final safe = title.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    final path = p.join((await _dir()).path, '${safe}_${_stamp()}.pdf');
    await File(path).writeAsBytes(await doc.save());
    return path;
  }

  /// Owner VIP PDF — same table as screen; Note + Credit red
  static Future<String> ownerLedgerPdf({
    required String title,
    required String partyLabel,
    required List<OwnerLedgerLine> rows,
    String? subtitle,
  }) async {
    final totAmt = rows.fold<double>(0, (s, e) => s + e.amount);
    final totCred = rows.fold<double>(0, (s, e) => s + e.credit);
    final bal = rows.isEmpty ? 0.0 : rows.last.runningBalance;
    const headers = ['Name', 'Date', 'Vehicle', 'Note', 'Litter', 'Rate', 'Amount', 'Credit', 'Balance'];
    final gold = PdfColor.fromInt(0xFFD4AF37);
    final navy = PdfColor.fromInt(0xFF1A2744);
    final red = PdfColors.red;

    pw.Widget cell(String text, {bool redText = false, bool header = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: header ? 8 : 7.2,
            fontWeight: header || redText ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: header ? gold : (redText ? red : PdfColors.black),
          ),
        ),
      );
    }

    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: pw.BoxDecoration(color: navy),
        children: headers.map((h) => cell(h, header: true)).toList(),
      ),
      for (var i = 0; i < rows.length; i++)
        pw.TableRow(
          decoration: i.isOdd ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF7F1E3)) : null,
          children: [
            cell(rows[i].partyName),
            cell(rows[i].date),
            cell(rows[i].vehicle),
            cell(rows[i].note, redText: rows[i].note.trim().isNotEmpty),
            cell(rows[i].litter.toStringAsFixed(2)),
            cell(rows[i].rate.toStringAsFixed(2)),
            cell(rows[i].amount.toStringAsFixed(2)),
            cell(rows[i].credit.toStringAsFixed(2), redText: true),
            cell(rows[i].runningBalance.toStringAsFixed(2)),
          ],
        ),
    ];

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(18),
        build: (ctx) => [
          _header(title),
          pw.Text('Party: $partyLabel  ${subtitle ?? ''}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: gold, width: 0.4),
            children: tableRows,
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: gold, width: 0.8), color: navy),
            child: pw.Column(
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Total Amount', style: pw.TextStyle(color: gold, fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text(totAmt.toStringAsFixed(0), style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Total Credit', style: pw.TextStyle(color: gold, fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text(totCred.toStringAsFixed(0), style: pw.TextStyle(color: red, fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Balance', style: pw.TextStyle(color: gold, fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text(bal.toStringAsFixed(0), style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text('Rows: ${rows.length}  |  Zaib Petroleum Service  |  Developed by Irtaza Hussain',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ],
      ),
    );
    final safe = title.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    final path = p.join((await _dir()).path, '${safe}_${_stamp()}.pdf');
    await File(path).writeAsBytes(await doc.save());
    return path;
  }

  static pw.Widget _header(String title) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('ZAIB PETROLEUM SERVICE',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF1A2744))),
          pw.SizedBox(height: 4),
          pw.Text(title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFFD4AF37))),
          pw.Container(margin: const pw.EdgeInsets.only(top: 6, bottom: 8), height: 2, color: PdfColor.fromInt(0xFFD4AF37)),
        ],
      );

  static pw.Widget _kpiTable(List<List<String>> rows) => pw.TableHelper.fromTextArray(
        data: rows,
        border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFD4AF37), width: 0.5),
        headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF243356)),
        cellStyle: const pw.TextStyle(fontSize: 9),
        cellAlignment: pw.Alignment.centerLeft,
        cellPadding: const pw.EdgeInsets.all(5),
      );

  static pw.Widget _namedList(String title, List<ClosingNamedAmount> items) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF1A2744))),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: const ['Name', 'Amount'],
          data: items.map((e) => [e.isTemp ? '[Temp] ${e.name}' : e.name, _money.format(e.amount)]).toList(),
          headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1A2744)),
          headerStyle: pw.TextStyle(color: PdfColor.fromInt(0xFFD4AF37), fontSize: 8, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 8),
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.3),
          cellPadding: const pw.EdgeInsets.all(3),
        ),
      ],
    );
  }

  static String _csv(String? v) {
    final s = (v ?? '').replaceAll('"', '""');
    if (s.contains(',') || s.contains('"') || s.contains('\n')) return '"$s"';
    return s;
  }

  static String _stamp() => DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
}
