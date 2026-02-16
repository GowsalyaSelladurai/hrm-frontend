//admin_notification.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zeai_project/user_provider.dart';
import 'dart:typed_data'; // Required for Uint8List
import 'package:file_saver/file_saver.dart'; // For saving to device
import 'package:path_provider/path_provider.dart'; // For mobile paths

import 'reports.dart';
import 'sidebar.dart';

class AdminNotificationsPage extends StatefulWidget {
  final String empId;
  const AdminNotificationsPage({required this.empId, super.key});

  @override
  State<AdminNotificationsPage> createState() => _AdminNotificationsPageState();
}

class _AdminNotificationsPageState extends State<AdminNotificationsPage> {
  final Color darkBlue = const Color(0xFF0F1020);

  late String selectedMonth;
  late int selectedYear;
  bool isLoading = false;
  String? error;
  String? expandedKey;

  final List<String> months = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
  ];

  List<Map<String, dynamic>> message = [];
  List<Map<String, dynamic>> performance = [];
  List<Map<String, dynamic>> holidays = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    selectedMonth = months[now.month - 1];
    selectedYear = now.year;
    _markAllAsRead();
    fetchNotifs();
  }

  void _showPerformancePreview(
    BuildContext context,
    Map<String, dynamic> notif,
  ) {
    final flagColor = _getFlagColor(notif['flag'] ?? "");

    // Format the date to match your image: YYYY-MM-DD hh:mm AM/PM
    String formattedDate = "N/A";
    if (notif['createdAt'] != null) {
      try {
        DateTime dt = DateTime.parse(notif['createdAt']).toLocal();
        String hour = (dt.hour % 12 == 0 ? 12 : dt.hour % 12)
            .toString()
            .padLeft(2, '0');
        String min = dt.minute.toString().padLeft(2, '0');
        String amPm = dt.hour >= 12 ? "PM" : "AM";
        formattedDate =
            "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $hour:$min $amPm";
      } catch (e) {
        formattedDate = notif['createdAt'];
      }
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFF1EDF7),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 6, width: double.infinity, color: flagColor),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Performance Review Details",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _imageStyleRow(
                      "Sent To",
                      "${notif['empName']} (${notif['receiverId']})",
                    ),
                    _imageStyleRow(
                      "Performance Review By",
                      "${notif['senderName']} (${notif['senderId']})",
                    ),
                    _imageStyleRow(
                      "Communication",
                      notif['communication'] ?? "good",
                    ),
                    _imageStyleRow("Attitude", notif['attitude'] ?? "good"),
                    _imageStyleRow(
                      "Technical Knowledge",
                      notif['technicalKnowledge'] ?? "good",
                    ),
                    _imageStyleRow("Business", notif['business'] ?? "good"),

                    // Flag Row
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black,
                          ),
                          children: [
                            const TextSpan(text: "Flag: "),
                            TextSpan(
                              text: notif['flag'] ?? "Green Flag",
                              style: TextStyle(
                                color: flagColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _imageStyleRow("Reviewed At", formattedDate),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          "CLOSE",
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper to match the plain text list style in your image
  Widget _imageStyleRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        "$label: $value",
        style: const TextStyle(fontSize: 14, color: Colors.black87),
      ),
    );
  }

  Color _getFlagColor(String flag) {
    final f = flag.toLowerCase();
    if (f.contains("green")) return Colors.green;
    if (f.contains("red")) return Colors.red;
    if (f.contains("yellow") || f.contains("orange")) return Colors.orange;
    return Colors.grey;
  }

  Future<void> _markAllAsRead() async {
    await http.put(
      Uri.parse(
        "https://hrm-backend-rm6c.onrender.com/notifications/mark-read/${widget.empId}",
      ),
    );
  }

  Future<void> fetchNotifs() async {
    setState(() {
      isLoading = true;
      error = null;
      message.clear();
      performance.clear();
      holidays.clear();
      expandedKey = null;
    });

    try {
      await Future.wait([
        fetchSmsNotifications(),
        fetchPerformanceNotifications(),
        fetchHolidayNotifications(),
      ]);
      setState(() {});
    } catch (e) {
      setState(() => error = "Server/network error: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _downloadFile(String url, String fileName) async {
    try {
      // 1. Fetch the file data from your server
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        Uint8List bytes = response.bodyBytes;

        // 2. Extract the file extension (e.g., pdf, png, jpg)
        String extension = fileName.split('.').last.toLowerCase();

        // 3. Save to device using file_saver
        // On Web: This triggers a browser download
        // On Mobile: This saves to the Downloads/Documents folder
        await FileSaver.instance.saveFile(
          name: fileName.split('.').first, // File name without extension
          bytes: bytes,
          ext: extension,
          mimeType: _getMimeType(extension),
        );

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Downloaded $fileName")));
      } else {
        throw "Failed to fetch file";
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error downloading file: $e")));
    }
  }

  // Helper to determine MimeType for file_saver
  MimeType _getMimeType(String ext) {
    switch (ext) {
      case 'pdf':
        return MimeType.pdf;
      case 'png':
        return MimeType.png;
      case 'jpg':
      case 'jpeg':
        return MimeType.jpeg;
      case 'csv':
        return MimeType.csv;
      default:
        return MimeType.other;
    }
  }

  Future<void> fetchSmsNotifications() async {
    final uri = Uri.parse(
      "https://hrm-backend-rm6c.onrender.com/notifications/employee/${widget.empId}?month=$selectedMonth&year=$selectedYear&category=message",
    );
    final resp = await http.get(uri);

    if (resp.statusCode == 200) {
      final decoded = jsonDecode(resp.body);
      if (decoded is List) {
        setState(() => message = decoded.cast<Map<String, dynamic>>());
      }
    } else if (resp.statusCode == 404) {
      setState(() => message = []);
    }
  }

  Future<void> fetchPerformanceNotifications() async {
    // This route hits the 'performance/admin/:adminId' endpoint in your JS
    final uri = Uri.parse(
      "https://hrm-backend-rm6c.onrender.com/notifications/performance/admin/${widget.empId}?month=$selectedMonth&year=$selectedYear",
    );

    final resp = await http.get(uri);

    if (resp.statusCode == 200) {
      final decoded = jsonDecode(resp.body);
      if (decoded is List) {
        setState(() {
          performance = decoded.cast<Map<String, dynamic>>().toList();
        });
      }
    } else {
      // ✅ Changed from 404 check to general else to ensure list clears on error
      setState(() => performance = []);
    }
  }

  Future<void> fetchHolidayNotifications() async {
    final uri = Uri.parse(
      "https://hrm-backend-rm6c.onrender.com/notifications/holiday/admin/$selectedMonth?year=$selectedYear",
    );
    final resp = await http.get(uri);

    if (resp.statusCode == 200) {
      final decoded = jsonDecode(resp.body);
      if (decoded is List) {
        setState(() => holidays = decoded.cast<Map<String, dynamic>>());
      }
    } else if (resp.statusCode == 404) {
      setState(() => holidays = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    // We calculate the total count from your three lists
    final int totalCount =
        performance.length + message.length + holidays.length;

    return PopScope(
      canPop: true,
      // This ensures that when the user goes back, the totalCount is sent to the Dashboard
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          // If you have a back button in your Sidebar, make sure it calls:
          // Navigator.pop(context, totalCount);
        }
      },
      child: Sidebar(
        title: "Admin Notifications",
        body: Column(
          children: [
            _buildHeader(),
            // 1. Header Row with dynamic count display
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Updated this text to show the number of notifications found
                  Text(
                    "Notifications ($totalCount)",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      _dropdownYear(),
                      const SizedBox(width: 10),
                      _dropdownMonth(),
                    ],
                  ),
                ],
              ),
            ),

            // 2. The scrollable content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : error != null
                    ? Center(
                        child: Text(
                          error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.only(top: 14),
                        children: [
                          notificationCategory("Performance", performance),
                          notificationCategory("Message", message),
                          notificationCategory("Holidays", holidays),
                          const SizedBox(height: 20), // Bottom padding
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdownYear() {
    final years = List.generate(5, (i) => DateTime.now().year - i);
    return Container(
      width: 100,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: selectedYear,
          items: years
              .map((y) => DropdownMenuItem(value: y, child: Text("$y")))
              .toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() => selectedYear = val);
              fetchNotifs();
            }
          },
        ),
      ),
    );
  }

  Widget _dropdownMonth() {
    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedMonth,
          isExpanded: true,
          items: months
              .map((m) => DropdownMenuItem(value: m, child: Text(m)))
              .toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() => selectedMonth = val);
              fetchNotifs();
            }
          },
        ),
      ),
    );
  }

  Widget notificationCategory(String title, List<Map<String, dynamic>> list) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 16, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 12),
            child: Text(
              "No $title found",
              style: const TextStyle(color: Colors.white70),
            ),
          )
        else
          ...list.asMap().entries.map(
            (entry) =>
                notificationCard(entry.value, entry.key, title.toLowerCase()),
          ),
      ],
    );
  }

  Widget notificationCard(
    Map<String, dynamic> notif,
    int index,
    String categoryParam,
  ) {
    final cardKey = "$categoryParam-$index";
    final isExpanded = expandedKey == cardKey;
    final messageText = notif['message'] as String;
    final category = (notif['category'] as String).toLowerCase();
    final senderName = notif['senderName'] ?? 'Unknown';
    final senderId = notif['senderId'] ?? '';
    final List attachments = (notif['attachments'] as List?) ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        elevation: 2,
        borderRadius: BorderRadius.circular(category == "message" ? 0 : 12),
        child: InkWell(
          onTap: () =>
              setState(() => expandedKey = isExpanded ? null : cardKey),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (category == "message") ...[
                        Text(
                          "From: $senderName ($senderId)",
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        messageText,
                        style: const TextStyle(fontSize: 14),
                        maxLines: isExpanded ? null : 1,
                        overflow: isExpanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                      ),
                      if (isExpanded && attachments.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        ...attachments.map((file) {
                          final url = "https://hrm-backend-rm6c.onrender.com/${file['path']}";
                          final fileName =
                              file['originalName'] ?? 'downloaded_file';

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.attach_file,
                                  size: 18,
                                  color: Colors.deepPurple,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    fileName,
                                    style: const TextStyle(
                                      color: Colors.deepPurple,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                                // THE DOWNLOAD ICON BUTTON
                                IconButton(
                                  icon: const Icon(
                                    Icons.download,
                                    color: Colors.blueAccent,
                                  ),
                                  tooltip: "Download to device",
                                  onPressed: () => _downloadFile(url, fileName),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                      if (isExpanded)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            "Click again to collapse",
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                    ],
                  ),
                ),
                if (category == "performance")
                  TextButton(
                    onPressed: () {
                      final userProvider = Provider.of<UserProvider>(
                        context,
                        listen: false,
                      );
                      final String? loggedInUserId = userProvider.employeeId;
                      final String senderId = notif['senderId'] ?? "";

                      // ✅ If the logged in user is the sender (Admin), show the popup preview
                      if (loggedInUserId != null &&
                          loggedInUserId == senderId) {
                        _showPerformancePreview(context, notif);
                      } else {
                        // If the admin received a review from someone else, go to reports
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (c) => const ReportsAnalyticsPage(),
                          ),
                        );
                      }
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("View"),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() => Container(height: 60, color: darkBlue);
}