// employeenotification.dart( year dropdrown)
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'reports.dart';
import 'sidebar.dart';

class EmployeeNotificationsPage extends StatefulWidget {
  final String empId; // ✅ required employee ID

  const EmployeeNotificationsPage({super.key, required this.empId});

  @override
  State<EmployeeNotificationsPage> createState() =>
      _EmployeeNotificationsPageState();
}

class _EmployeeNotificationsPageState extends State<EmployeeNotificationsPage> {
  final Color darkBlue = const Color(0xFF0F1020);

  late String selectedMonth;
  late int selectedYear;
  bool isLoading = false;
  String? error;
  String? expandedKey;

  final List<String> months = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
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
    fetchNotifs();
  }

  /// 🔹 Main function -> call APIs based on Year and Month
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
    } catch (e) {
      setState(() => error = "Server/network error: $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  /// 🔹 Fetch SMS Notifications (Filtered by Year and Month)
  Future<void> fetchSmsNotifications() async {
    final uri = Uri.parse(
      "https://hrm-backend-rm6c.onrender.com/notifications/employee/${widget.empId}?month=$selectedMonth&year=$selectedYear&category=message",
    );
    final resp = await http.get(uri);

    if (resp.statusCode == 200) {
      final decoded = jsonDecode(resp.body);
      if (decoded is List) {
        setState(() {
          message = decoded.cast<Map<String, dynamic>>();
        });
      }
    } else if (resp.statusCode == 404) {
      setState(() => message = []);
    }
  }

  /// 🔹 Fetch Performance Notifications (Filtered by Year and Month)
  Future<void> fetchPerformanceNotifications() async {
    final uri = Uri.parse(
      "https://hrm-backend-rm6c.onrender.com/notifications/performance/employee/$selectedMonth/${widget.empId}?year=$selectedYear",
    );
    final resp = await http.get(uri);

    if (resp.statusCode == 200) {
      final decoded = jsonDecode(resp.body);
      if (decoded is List) {
        setState(() {
          performance = decoded
              .where((n) => (n['category'] as String).toLowerCase() == 'performance')
              .cast<Map<String, dynamic>>()
              .toList();
        });
      }
    } else if (resp.statusCode == 404) {
      setState(() => performance = []);
    }
  }

  /// 🔹 Fetch Holiday Notifications (Filtered by Year and Month)
  Future<void> fetchHolidayNotifications() async {
    final uri = Uri.parse(
      "https://hrm-backend-rm6c.onrender.com/notifications/holiday/employee/${widget.empId}?month=$selectedMonth&year=$selectedYear",
    );
    final resp = await http.get(uri);

    if (resp.statusCode == 200) {
      final decoded = jsonDecode(resp.body);
      if (decoded is List) {
        setState(() {
          holidays = decoded.cast<Map<String, dynamic>>();
        });
      }
    } else if (resp.statusCode == 404) {
      setState(() => holidays = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Sidebar(
      title: "Employee Notifications",
      body: Column(
        children: [
          _buildHeader(),
          // 1. Fixed Header Section (Sticky)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Notifications",
                  style: TextStyle(
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
          
          // 2. Scrollable Section
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
                          // Removes extra padding from top of list
                          padding: const EdgeInsets.only(top: 10, bottom: 20),
                          children: [
                            notificationCategory("Message", message),
                            notificationCategory("Performance", performance),
                            notificationCategory("Holidays", holidays),
                          ],
                        ),
            ),
          ),
        ],
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
          items: years.map((y) => DropdownMenuItem(value: y, child: Text("$y"))).toList(),
          onChanged: (val) {
            if (val != null && val != selectedYear) {
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
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedMonth,
          isExpanded: true,
          items: months.map((m) => DropdownMenuItem<String>(value: m, child: Text(m))).toList(),
          onChanged: (val) {
            if (val != null && val != selectedMonth) {
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
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 12),
            child: Text("No $title found", style: const TextStyle(color: Colors.white70)),
          )
        else
          ...list.asMap().entries.map((entry) => notificationCard(entry.value, entry.key, title.toLowerCase())),
      ],
    );
  }

  Widget notificationCard(Map<String, dynamic> notif, int index, String categoryParam) {
    final cardKey = "$categoryParam-$index";
    final isExpanded = expandedKey == cardKey;
    final msgContent = notif['message'] as String;
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
          onTap: () => setState(() => expandedKey = isExpanded ? null : cardKey),
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
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        msgContent,
                        style: const TextStyle(fontSize: 14),
                        maxLines: isExpanded ? null : 1,
                        overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                      ),
                      if (isExpanded && attachments.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: attachments.map<Widget>((file) {
                            final String filename = file['originalName'] ?? file['filename'];
                            final String url = "https://hrm-backend-rm6c.onrender.com/${file['path']}";
                            final bool isImage = (file['mimetype'] ?? '').startsWith('image/');

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: InkWell(
                                onTap: () async {
                                  final uri = Uri.parse(url);
                                  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                                },
                                child: Row(
                                  children: [
                                    Icon(isImage ? Icons.image : Icons.attach_file, size: 18, color: Colors.deepPurple),
                                    const SizedBox(width: 6),
                                    Expanded(child: Text(filename, style: const TextStyle(color: Colors.deepPurple, decoration: TextDecoration.underline), overflow: TextOverflow.ellipsis)),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      if (isExpanded) const SizedBox(height: 8),
                      if (isExpanded) const Text("Click again to collapse", style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                if (category == "performance")
                  TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => ReportsAnalyticsPage())),
                    style: TextButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white),
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