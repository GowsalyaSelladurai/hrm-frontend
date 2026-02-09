// message.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'sidebar.dart';
import 'package:provider/provider.dart';
import 'user_provider.dart';
import 'package:file_picker/file_picker.dart';

class MsgPage extends StatefulWidget {
  final String employeeId;

  const MsgPage({super.key, required this.employeeId});

  @override
  State<MsgPage> createState() => _MsgPageState();
}

class _MsgPageState extends State<MsgPage> {
  Map<String, dynamic>? employeeData;
  final TextEditingController _msgController = TextEditingController();
  bool _loading = true;

  // Multiple file attachments
  final List<PlatformFile> _selectedFiles = [];

  @override
  void initState() {
    super.initState();
    fetchEmployeeDetails();
  }

  Future<void> fetchEmployeeDetails() async {
    try {
      final response = await http.get(
        Uri.parse("https://hrm-backend-rm6c.onrender.com/api/employees/${widget.employeeId}"),
      );
      if (response.statusCode == 200) {
        setState(() {
          employeeData = json.decode(response.body);
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
        debugPrint("❌ Failed to load employee: ${response.statusCode}");
      }
    } catch (e) {
      setState(() => _loading = false);
      debugPrint("❌ Error fetching employee: $e");
    }
  }

  // Pick multiple files
  Future<void> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedFiles.addAll(result.files);
      });
    }
  }

  void removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  // Send message + attachments
  Future<void> sendMessage() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final senderId = userProvider.employeeId;
    final senderName = userProvider.employeeName;

    if ((_msgController.text.trim().isEmpty && _selectedFiles.isEmpty) || senderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Enter message or select file to send"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    String month = [
      "January","February","March","April","May","June",
      "July","August","September","October","November","December"
    ][DateTime.now().month - 1];

    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse("https://hrm-backend-rm6c.onrender.com/notifications/with-files"),
      );

      // ✅ Add fields
      request.fields.addAll({
        "month": month,
        "year": DateTime.now().year.toString(),
        "category": "message",
        "message": _msgController.text.trim(),
        "empId": widget.employeeId,
        "senderId": senderId,
        "senderName": senderName ?? "",
      });

      // ✅ Add attachments if any
      for (final file in _selectedFiles) {
        if (file.bytes != null) {
          request.files.add(
            http.MultipartFile.fromBytes(
              "attachments",
              file.bytes!,
              filename: file.name,
            ),
          );
        }
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Message sent to ${employeeData?['employeeName']}"),
            backgroundColor: Colors.green,
          ),
        );
        _msgController.clear();
        setState(() => _selectedFiles.clear());
      } else {
        debugPrint("❌ Failed: ${response.statusCode} - ${response.body}");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to send message"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint("❌ Error sending message: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Error sending message"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }


  bool _isImage(String? ext) {
    if (ext == null) return false;
    return ["jpg", "jpeg", "png"].contains(ext.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    return Sidebar(
      title: "Send Message",
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Employee photo
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey[300],
                    backgroundImage: (employeeData?['employeeImage'] != null &&
                            employeeData!['employeeImage'].isNotEmpty)
                        ? NetworkImage(
                            "https://hrm-backend-rm6c.onrender.com${employeeData!['employeeImage']}")
                        : const AssetImage("assets/profile.png")
                            as ImageProvider,
                  ),
                  const SizedBox(height: 12),
                  // Name
                  Text(
                    employeeData?['employeeName'] ?? "Unknown",
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  Text(
                    employeeData?['position'] ?? "",
                    style: const TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                  const SizedBox(height: 25),
                  // Message box
                  TextField(
                    controller: _msgController,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: "Type your message...",
                      filled: true,
                      fillColor: Colors.deepPurple.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  // File Upload Button
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      onPressed: pickFiles,
                      icon: const Icon(Icons.attach_file),
                      label: const Text("Upload Files"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Selected files preview
                  if (_selectedFiles.isNotEmpty)
                    SizedBox(
                      height: 120,
                      child: ListView.builder(
                        itemCount: _selectedFiles.length,
                        itemBuilder: (context, index) {
                          final file = _selectedFiles[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.deepPurple.shade50,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                _isImage(file.extension)
                                    ? Image.memory(
                                        file.bytes!,
                                        width: 50,
                                        height: 50,
                                        fit: BoxFit.cover,
                                      )
                                    : const Icon(
                                        Icons.insert_drive_file,
                                        size: 40,
                                        color: Colors.deepPurple,
                                      ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    file.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close,
                                      color: Colors.red),
                                  onPressed: () => removeFile(index),
                                )
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 20),
                  // Action buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: sendMessage,
                        icon: const Icon(Icons.send),
                        label: const Text("Send"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.cancel),
                        label: const Text("Cancel"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}