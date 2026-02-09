// mail.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zeai_project/user_provider.dart'; // Assume these are imported from your project

class MailDashboard extends StatefulWidget {
  const MailDashboard({super.key});

  @override
  State<MailDashboard> createState() => _MailDashboardState();
}

class _MailDashboardState extends State<MailDashboard> {
  int selectedMenu = 0; // 0 = Inbox, 1 = Sent, 2 = Compose, 3 = View Mail, 4 = Trash, 5 = Drafts
  Map<String, dynamic>? selectedMail;

  List inbox = [];
  List sent = [];
  List trash = [];
  List drafts = [];

  bool loadingInbox = true;
  bool loadingSent = true;
  bool loadingTrash = true;
  bool loadingDrafts = true;

  bool isReplyOrForward = false;

  // Controllers
  final TextEditingController _toCtrl = TextEditingController();
  final TextEditingController _subCtrl = TextEditingController();
  final TextEditingController _ccCtrl = TextEditingController();
  final TextEditingController _bccCtrl = TextEditingController();
  final TextEditingController _bodyCtrl = TextEditingController();
  List<PlatformFile> attachments = [];
  bool sending = false;

  // NEW: Inline reply state & controllers
  bool showInlineReply = false;
  int? replyTargetIndex; // which message index to show inline composer under
  final TextEditingController _inlineBodyCtrl = TextEditingController();
  final TextEditingController _inlineCcCtrl = TextEditingController();
  final TextEditingController _inlineBccCtrl = TextEditingController();
  final TextEditingController _inlineToCtrl = TextEditingController();
  bool _inlineShowCc = false;
  bool _inlineShowBcc = false;
  bool _inlineSending = false;

  // NEW: Current thread id used when replying (null => new thread)
  String? currentThreadId;

  // NEW: keep track of which messages are expanded in the thread view
  Set<int> expandedMessages = {};

  // NEW: Track which message header details are expanded
  Set<int> expandedHeaderDetails = {};

  // NEW: Inline attachments for reply/reply-all
  final List<PlatformFile> _inlineAttachments = [];

  // NEW: When preparing a Forward / opening draft, capture server-side filenames from the thread to forward
  List<String> _forwardedAttachments = [];

  // NEW: Draft metadata (when saving / editing)
  String? _editingDraftId;

  // Auto-save debounce timer for drafts
  Timer? _draftDebounce;

  // Periodic auto-refresh
  Timer? _refreshTimer;

  // Search
  String _searchQuery = "";
  final TextEditingController _searchCtrl = TextEditingController();

  // Month names for display
  static const List<String> _monthNames = [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec"
  ];

  @override
  void initState() {
    super.initState();
    loadAll();
    // Periodic refresh every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      loadAll(silent: true);
    });

    // listen to compose fields to trigger autosave
    _toCtrl.addListener(_onComposeChanged);
    _ccCtrl.addListener(_onComposeChanged);
    _bccCtrl.addListener(_onComposeChanged);
    _subCtrl.addListener(_onComposeChanged);
    _bodyCtrl.addListener(_onComposeChanged);

    // search listener (local filter)
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _draftDebounce?.cancel();
    _refreshTimer?.cancel();
    _toCtrl.removeListener(_onComposeChanged);
    _ccCtrl.removeListener(_onComposeChanged);
    _bccCtrl.removeListener(_onComposeChanged);
    _subCtrl.removeListener(_onComposeChanged);
    _bodyCtrl.removeListener(_onComposeChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  // ------------------ Date helpers ------------------ //
  // Convert various backend timestamp formats into a relative short string:
  // - if less than 60 minutes -> "5 min ago"
  // - if less than 24 hours -> "1 hour ago" / "3 hours ago"
  // - if yesterday -> "Yesterday"
  // - otherwise -> "Feb 6"
  String formatRelativeDate(dynamic dateValue) {
    if (dateValue == null) return "";
    DateTime dt;
    try {
      if (dateValue is DateTime) {
        dt = dateValue.toLocal();
      } else {
        // handle both ISO strings and numeric timestamps
        final s = dateValue.toString();
        // some backends may send an object; string parse should handle ISO
        dt = DateTime.parse(s).toLocal();
      }
    } catch (e) {
      return dateValue.toString();
    }

    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) {
      return "${diff.inSeconds}s ago";
    }
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return m == 1 ? "1 min ago" : "$m min ago";
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return h == 1 ? "1 hour ago" : "$h hours ago";
    }

    // days difference - use local dates (no time)
    final today = DateTime(now.year, now.month, now.day);
    final then = DateTime(dt.year, dt.month, dt.day);
    final days = today.difference(then).inDays;

    if (days == 1) return "Yesterday";

    // older -> short month/day e.g. "Feb 6"
    return "${_monthNames[dt.month - 1]} ${dt.day}";
  }

  // Full readable date-time (e.g. "Feb 6, 10:04 AM") and optionally include relative in parentheses
  String formatFullDateTime(dynamic dateValue) {
    if (dateValue == null) return "";
    DateTime dt;
    try {
      if (dateValue is DateTime) {
        dt = dateValue.toLocal();
      } else {
        dt = DateTime.parse(dateValue.toString()).toLocal();
      }
    } catch (e) {
      return dateValue.toString();
    }

    final hour = dt.hour;
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    final minute = dt.minute.toString().padLeft(2, "0");
    final ampm = hour >= 12 ? "PM" : "AM";

    final shortDate = "${_monthNames[dt.month - 1]} ${dt.day}, $displayHour:$minute $ampm";

    // append relative only when within last 7 days for helpfulness
    final now = DateTime.now();
    final daysDiff = DateTime(now.year, now.month, now.day).difference(DateTime(dt.year, dt.month, dt.day)).inDays;
    if (daysDiff <= 7) {
      final rel = formatRelativeDate(dateValue);
      return "$shortDate ($rel)";
    }
    return shortDate;
  }

  // safe extractor for the "last activity" datetime on a mail/draft/thread object
  dynamic _extractLastActivityDate(dynamic item) {
    if (item == null) return null;
    try {
      // expected: item is Map (thread-like or draft-like). Be defensive.
      if (item is Map) {
        // server may provide lastUpdated / updatedAt
        if (item['lastUpdated'] != null) return item['lastUpdated'];
        if (item['updatedAt'] != null) return item['updatedAt'];

        // if we have messages array, try to get last message createdAt/updatedAt
        if (item['messages'] is List && (item['messages'] as List).isNotEmpty) {
          final last = (item['messages'] as List).last;
          if (last is Map) {
            return last['createdAt'] ?? last['updatedAt'];
          }
        }

        // fallback to createdAt if present (useful for drafts)
        if (item['createdAt'] != null) return item['createdAt'];
      }
      return null;
    } catch (e) {
      // defensive: any unexpected shape -> null
      debugPrint("extractLastActivityDate error: $e");
      return null;
    }
  }

  // ------------------ end date helpers ------------------ //

  Future<void> loadAll({bool silent = false}) async {
    if (!silent) setState(() { loadingInbox = loadingSent = loadingTrash = loadingDrafts = true; });
    await Future.wait([loadInbox(silent: silent), loadSent(silent: silent), loadTrash(silent: silent), loadDrafts(silent: silent)]);
  }

  Future<void> loadInbox({bool silent = false}) async {
    final user = Provider.of<UserProvider>(context, listen: false);
    final empId = user.employeeId;
    try {
      final res = await http.get(Uri.parse("https://hrm-backend-rm6c.onrender.com/api/mail/inbox/$empId"));
      if (res.statusCode == 200) {
        setState(() {
          inbox = json.decode(res.body);
          loadingInbox = false;
        });
      }
    } catch (e) {
      debugPrint("Inbox error: $e");
      setState(() => loadingInbox = false);
    }
  }

  Future<void> loadSent({bool silent = false}) async {
    final user = Provider.of<UserProvider>(context, listen: false);
    final empId = user.employeeId;
    try {
      final res = await http.get(Uri.parse("https://hrm-backend-rm6c.onrender.com/api/mail/sent/$empId"));
      if (res.statusCode == 200) {
        setState(() {
          sent = json.decode(res.body);
          loadingSent = false;
        });
      }
    } catch (e) {
      debugPrint("Sent error: $e");
      setState(() => loadingSent = false);
    }
  }

  Future<void> loadTrash({bool silent = false}) async {
    final user = Provider.of<UserProvider>(context, listen: false);
    final empId = user.employeeId;
    try {
      final res = await http.get(Uri.parse("https://hrm-backend-rm6c.onrender.com/api/mail/trash/$empId"));
      if (res.statusCode == 200) {
        setState(() {
          trash = json.decode(res.body);
          loadingTrash = false;
        });
      }
    } catch (e) {
      debugPrint("Trash load error: $e");
      setState(() => loadingTrash = false);
    }
  }

  Future<void> loadDrafts({bool silent = false}) async {
    final user = Provider.of<UserProvider>(context, listen: false);
    final empId = user.employeeId;
    try {
      final res = await http.get(Uri.parse("https://hrm-backend-rm6c.onrender.com/api/mail/drafts/$empId"));
      if (res.statusCode == 200) {
        setState(() {
          drafts = json.decode(res.body);
          loadingDrafts = false;
        });
      }
    } catch (e) {
      debugPrint("Drafts load error: $e");
      setState(() => loadingDrafts = false);
    }
  }

  // OPEN MAIL -> now calls thread endpoint and passes current user's employeeId
  Future<void> openMail(String id) async {
    setState(() {
      selectedMenu = 3;
      selectedMail = null;
      expandedMessages.clear();
      currentThreadId = null; // reset - will be set only when user chooses Reply/ReplyAll
      showInlineReply = false;
      replyTargetIndex = null;
      expandedHeaderDetails.clear();
      _editingDraftId = null; // viewing a thread, not editing a draft
      _forwardedAttachments.clear();
    });
    try {
      final user = Provider.of<UserProvider>(context, listen: false);
      final empId = user.employeeId;
      final res = await http.get(Uri.parse("https://hrm-backend-rm6c.onrender.com/api/mail/thread/$id/$empId"));
      if (res.statusCode == 200) {
        setState(() {
          selectedMail = json.decode(res.body);
        });
      }
    } catch (e) {
      debugPrint("Mail view error: $e");
    }
  }

  Future<void> pickFiles() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    if (res != null) {
      setState(() {
        attachments.addAll(res.files);
      });
      // trigger autosave because attachments changed
      _scheduleDraftSave();
    }
  }

  Future<void> pickInlineFiles() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    if (res != null) {
      setState(() {
        _inlineAttachments.addAll(res.files);
      });
    }
  }

  Future<void> sendMail() async {
    final user = Provider.of<UserProvider>(context, listen: false);
    final from = user.employeeId;
    if (_toCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Receiver required")));
      return;
    }
    setState(() => sending = true);

    // Build arrays for to/cc/bcc - split by comma and trim
    List<String> parseList(String raw) {
      return raw
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }

    final toList = parseList(_toCtrl.text);
    final ccList = parseList(_ccCtrl.text);
    final bccList = parseList(_bccCtrl.text);

    var req = http.MultipartRequest("POST", Uri.parse("https://hrm-backend-rm6c.onrender.com/api/mail/send"));
    req.fields["from"] = from!;
    req.fields["to"] = jsonEncode(toList); // <-- JSON array
    req.fields["cc"] = jsonEncode(ccList); // <-- JSON array (optional)
    req.fields["bcc"] = jsonEncode(bccList); // <-- JSON array (optional)
    req.fields["subject"] = _subCtrl.text;
    req.fields["body"] = _bodyCtrl.text;

    // NEW: include threadId only if replying/ appending
    if (currentThreadId != null) {
      req.fields["threadId"] = currentThreadId!;
    }

    // NEW: include forwarded server-side attachments if any (send as JSON list)
    if (_forwardedAttachments.isNotEmpty) {
      req.fields["forwardAttachments"] = jsonEncode(_forwardedAttachments);
    }

    // if this compose was loaded from a draft, send draftId so we can delete it after success
    if (_editingDraftId != null) {
      req.fields["draftId"] = _editingDraftId!;
    }

    for (var f in attachments) {
      if (f.bytes != null) {
        req.files.add(http.MultipartFile.fromBytes("attachments", f.bytes!, filename: f.name));
      } else if (f.path != null) {
        req.files.add(await http.MultipartFile.fromPath("attachments", f.path!, filename: f.name));
      }
    }

    try {
      var resp = await req.send();
      var finalRes = await http.Response.fromStream(resp);
      if (finalRes.statusCode == 201 || finalRes.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Mail Sent"), backgroundColor: Colors.green),
        );
        // If this was a draft, delete it now from server
        if (_editingDraftId != null) {
          try {
            final user = Provider.of<UserProvider>(context, listen: false);
            final empId = user.employeeId;
            await http.delete(Uri.parse("https://hrm-backend-rm6c.onrender.com/api/mail/draft/$_editingDraftId/$empId"));
          } catch (e) {
            debugPrint("Failed to delete draft after send: $e");
          }
        }

        setState(() {
          attachments.clear();
          _forwardedAttachments.clear();
          isReplyOrForward = false;
          currentThreadId = null; // reset after successful send
          _editingDraftId = null;
          selectedMenu = 0;
        });
        await loadAll();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: ${finalRes.body}")));
      }
    } catch (e) {
      debugPrint("Send error: $e");
    }
    setState(() => sending = false);
  }

  // Inline send (small reply box). Appends to thread (threadId required)
  Future<void> _sendInlineReply() async {
    if (currentThreadId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Thread not set")));
      return;
    }
    final user = Provider.of<UserProvider>(context, listen: false);
    final from = user.employeeId;
    final toList = _inlineToCtrl.text.split(",").map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (toList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Receiver required")));
      return;
    }
    setState(() => _inlineSending = true);

    List<String> parseList(String raw) {
      return raw
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }

    final ccList = parseList(_inlineCcCtrl.text);
    final bccList = parseList(_inlineBccCtrl.text);
    final body = _inlineBodyCtrl.text;

    var req = http.MultipartRequest("POST", Uri.parse("https://hrm-backend-rm6c.onrender.com/api/mail/send"));
    req.fields["from"] = from!;
    req.fields["to"] = jsonEncode(toList);
    req.fields["cc"] = jsonEncode(ccList);
    req.fields["bcc"] = jsonEncode(bccList);
    req.fields["subject"] = _subCtrl.text.isNotEmpty ? _subCtrl.text : (selectedMail?['subject'] ?? "");
    req.fields["body"] = body;
    req.fields["threadId"] = currentThreadId!;

    // Add inline attachments to request
    for (var f in _inlineAttachments) {
      if (f.bytes != null) {
        req.files.add(http.MultipartFile.fromBytes("attachments", f.bytes!, filename: f.name));
      } else if (f.path != null) {
        req.files.add(await http.MultipartFile.fromPath("attachments", f.path!, filename: f.name));
      }
    }

    try {
      var resp = await req.send();
      var finalRes = await http.Response.fromStream(resp);
      if (finalRes.statusCode == 201 || finalRes.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Reply sent"), backgroundColor: Colors.green),
        );
        // clear inline composer and refresh thread
        setState(() {
          _inlineBodyCtrl.clear();
          _inlineCcCtrl.clear();
          _inlineBccCtrl.clear();
          _inlineToCtrl.clear();
          _inlineAttachments.clear();
          _inlineShowCc = false;
          _inlineShowBcc = false;
          showInlineReply = false;
          replyTargetIndex = null;
        });
        // reload thread
        if (currentThreadId != null) {
          await openMail(currentThreadId!);
        }
        // refresh lists
        await loadAll(silent: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: ${finalRes.body}")));
      }
    } catch (e) {
      debugPrint("Inline send error: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to send reply")));
    } finally {
      setState(() => _inlineSending = false);
    }
  }

  // Draft save (create or update). Called by autosave and manual save.
  Future<void> _saveDraft({bool showSnack = true}) async {
    // Keep simple rule: only save drafts when any meaningful field present (to, subject, body, attachments)
    final user = Provider.of<UserProvider>(context, listen: false);
    final from = user.employeeId;
    if (from == null) return;

    final hasContent = _toCtrl.text.trim().isNotEmpty ||
        _ccCtrl.text.trim().isNotEmpty ||
        _bccCtrl.text.trim().isNotEmpty ||
        _subCtrl.text.trim().isNotEmpty ||
        _bodyCtrl.text.trim().isNotEmpty ||
        attachments.isNotEmpty ||
        _forwardedAttachments.isNotEmpty;

    if (!hasContent) {
      // if nothing meaningful, and we have an existing draft id, we may delete empty draft
      if (_editingDraftId != null) {
        try {
          await http.delete(Uri.parse("https://hrm-backend-rm6c.onrender.com/api/mail/draft/$_editingDraftId/$from"));
        } catch (e) {
          debugPrint("Delete empty draft error: $e");
        }
        setState(() {
          _editingDraftId = null;
        });
        await loadDrafts(silent: true);
      }
      return;
    }

    // prepare multipart request to save draft (attachments are optional)
    var uri = Uri.parse("https://hrm-backend-rm6c.onrender.com/api/mail/drafts/save");
    var req = http.MultipartRequest("POST", uri);
    if (_editingDraftId != null) req.fields["draftId"] = _editingDraftId!;
    req.fields["from"] = from;
    req.fields["to"] = jsonEncode(_toCtrl.text.split(",").map((s) => s.trim()).where((s) => s.isNotEmpty).toList());
    req.fields["cc"] = jsonEncode(_ccCtrl.text.split(",").map((s) => s.trim()).where((s) => s.isNotEmpty).toList());
    req.fields["bcc"] = jsonEncode(_bccCtrl.text.split(",").map((s) => s.trim()).where((s) => s.isNotEmpty).toList());
    req.fields["subject"] = _subCtrl.text;
    req.fields["body"] = _bodyCtrl.text;

    // Add local picked attachments
    for (var f in attachments) {
      if (f.bytes != null) {
        req.files.add(http.MultipartFile.fromBytes("attachments", f.bytes!, filename: f.name));
      } else if (f.path != null) {
        req.files.add(await http.MultipartFile.fromPath("attachments", f.path!, filename: f.name));
      }
    }

    // If there are already server-side forwarded attachments (e.g. from opening draft or forward),
    // include them so server can retain them. We pass them as a field 'forwardAttachments' JSON.
    if (_forwardedAttachments.isNotEmpty) {
      req.fields["forwardAttachments"] = jsonEncode(_forwardedAttachments);
    }

    try {
      var resp = await req.send();
      var finalRes = await http.Response.fromStream(resp);
      if (finalRes.statusCode == 201 || finalRes.statusCode == 200) {
        final body = json.decode(finalRes.body);
        final d = body['draft'] ?? body;
        setState(() {
          _editingDraftId = d != null ? (d['_id'] ?? d['id'] ?? _editingDraftId) : _editingDraftId;
        });
        if (showSnack) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Draft saved"), backgroundColor: Colors.green));
        }
        await loadDrafts(silent: true);
      } else {
        debugPrint("Draft save server error: ${finalRes.body}");
      }
    } catch (e) {
      debugPrint("Draft save error: $e");
    }
  }

  // Debounce schedule for autosave
  void _scheduleDraftSave() {
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(seconds: 2), () {
      _saveDraft(showSnack: false);
    });
  }

  // Called whenever the compose fields change
  void _onComposeChanged() {
    // schedule autosave only if we're currently in Compose view
    if (selectedMenu == 2) _scheduleDraftSave();
  }

  // Open a draft for editing in compose
  Future<void> _openDraftForEdit(Map draft) async {
    // load draft fields into compose
    setState(() {
      selectedMenu = 2;
      _editingDraftId = draft['_id']?.toString();
      _toCtrl.text = (draft['to'] as List?)?.join(", ") ?? "";
      _ccCtrl.text = (draft['cc'] as List?)?.join(", ") ?? "";
      _bccCtrl.text = (draft['bcc'] as List?)?.join(", ") ?? "";
      _subCtrl.text = draft['subject'] ?? "";
      _bodyCtrl.text = draft['body'] ?? "";
      attachments.clear();
      // convert server attachments into forwardedAttachments so they show up (server filenames)
      _forwardedAttachments = (draft['attachments'] as List?)?.map<String>((a) => a['filename'] as String).toList() ?? [];
      currentThreadId = null;
      isReplyOrForward = false;
    });
  }

  // delete a draft
  Future<void> _deleteDraft(String draftId) async {
    try {
      final user = Provider.of<UserProvider>(context, listen: false);
      final empId = user.employeeId;
      final res = await http.delete(Uri.parse("https://hrm-backend-rm6c.onrender.com/api/mail/draft/$draftId/$empId"));
      if (res.statusCode == 200) {
        await loadDrafts();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Draft deleted"), backgroundColor: Colors.green));
        if (_editingDraftId == draftId) {
          // clear compose
          setState(() {
            _editingDraftId = null;
            _toCtrl.clear();
            _ccCtrl.clear();
            _bccCtrl.clear();
            _subCtrl.clear();
            _bodyCtrl.clear();
            attachments.clear();
            _forwardedAttachments.clear();
          });
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error deleting draft: ${res.body}")));
      }
    } catch (e) {
      debugPrint("Draft delete error: $e");
    }
  }

  // Replace existing _moveToTrash
  Future<void> _moveToTrash(String threadId) async {
    try {
      final user = Provider.of<UserProvider>(context, listen: false);
      final empId = user.employeeId;
      final res = await http.put(
        Uri.parse("https://hrm-backend-rm6c.onrender.com/api/mail/trash/$threadId/$empId"),
      );
      if (res.statusCode == 200) {
        await loadInbox();
        await loadTrash();
        setState(() => selectedMenu = 4);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Moved to Trash"), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error moving to trash: ${res.body}")),
        );
      }
    } catch (e) {
      debugPrint("Trash error: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to move to trash")));
    }
  }

  // Replace existing _restoreMail
  Future<void> _restoreMail(String threadId) async {
    try {
      final user = Provider.of<UserProvider>(context, listen: false);
      final empId = user.employeeId;
      final res = await http.put(
        Uri.parse("https://hrm-backend-rm6c.onrender.com/api/mail/restore/$threadId/$empId"),
      );
      if (res.statusCode == 200) {
        await loadTrash();
        await loadInbox();
        setState(() => selectedMenu = 0);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Restored from Trash"), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error restoring: ${res.body}")),
        );
      }
    } catch (e) {
      debugPrint("Restore error: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to restore")));
    }
  }

  // Replace existing _deleteForever
  Future<void> _deleteForever(String threadId) async {
    try {
      final user = Provider.of<UserProvider>(context, listen: false);
      final empId = user.employeeId;
      final res = await http.delete(
        Uri.parse("https://hrm-backend-rm6c.onrender.com/api/mail/delete-permanent/$threadId/$empId"),
      );
      if (res.statusCode == 200) {
        await loadTrash();
        setState(() => selectedMenu = 4);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Deleted permanently"), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error deleting permanently: ${res.body}")),

        );
      }
    } catch (e) {
      debugPrint("Delete forever error: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to delete permanently")));
    }
  }

  // ========== Compose helpers (Reply / Reply-All / Forward) ==========

  // Prepare reply to a thread (inline reply to the last message sender)
  void _prepareReplyMail(Map thread, {int? targetIndex}) {
    final messages = (thread['messages'] as List?) ?? [];
    final idx = targetIndex ?? (messages.isNotEmpty ? messages.length - 1 : 0);
    final last = (messages.isNotEmpty && idx < messages.length) ? messages[idx] : {};
    final senderEmpId = (last is Map && last['from'] is Map) ? (last['from']?['employeeId'] ?? "") : (last['from'] ?? "");
    setState(() {
      // prepare inline reply (small box) under the specific message
      isReplyOrForward = false;
      selectedMenu = 3; // stay in thread view
      attachments.clear();
      _inlineToCtrl.text = senderEmpId ?? "";
      _inlineCcCtrl.clear();
      _inlineBccCtrl.clear();
      _inlineBodyCtrl.clear(); // do not include original
      _subCtrl.text = "Re: ${thread['subject'] ?? ''}";
      currentThreadId = thread['_id']?.toString(); // IMPORTANT: set thread id to append
      showInlineReply = true;
      replyTargetIndex = idx;
      // clear any compose-draft context
      _editingDraftId = null;
      _forwardedAttachments.clear();
    });
  }

  // Prepare reply-all (inline) - sets currentThreadId
  void _prepareReplyAll(Map thread, {int? targetIndex}) {
    final user = Provider.of<UserProvider>(context, listen: false);
    final me = user.employeeId;
    final participants = (thread['participants'] as List?)?.cast<String>() ?? [];

    // Collect per-message CCs if present
    final ccFromMessages = <String>{};
    final messages = (thread['messages'] as List?) ?? [];
    for (final m in messages) {
      if (m is Map && m['cc'] is List) {
        for (final c in (m['cc'] as List)) {
          if (c is Map && c['employeeId'] != null) {
            ccFromMessages.add(c['employeeId']);
          } else if (c is String) ccFromMessages.add(c);
        }
      }
    }

    // reply-all: set to all participants except me
    final toList = participants.where((p) => p != me).toList();
    // cc list: include ccFromMessages except me and except those already in toList
    final ccList = ccFromMessages.where((p) => p != me && !toList.contains(p)).toList();

    setState(() {
      isReplyOrForward = false;
      selectedMenu = 3; // stay in thread view (inline)
      attachments.clear();
      _inlineToCtrl.text = toList.join(", ");
      _inlineCcCtrl.text = ccList.join(", ");
      _inlineBccCtrl.clear();
      _inlineBodyCtrl.clear();
      _subCtrl.text = "Re: ${thread['subject'] ?? ''}";
      currentThreadId = thread['_id']?.toString();
      showInlineReply = true;
      replyTargetIndex = (messages.isNotEmpty ? messages.length - 1 : 0);
      _inlineShowCc = ccList.isNotEmpty;
      // clear compose draft context
      _editingDraftId = null;
      _forwardedAttachments.clear();
    });
  }

  // Prepare forward (forward last message content) - opens full compose (new thread)
  void _prepareForwardMail(Map thread) {
    final messages = (thread['messages'] as List?) ?? [];
    final last = messages.isNotEmpty ? messages.last : (messages.isNotEmpty ? messages[0] : {});
    final fromInfo = (last is Map) ? (last['from'] ?? {}) : {};
    final fromText = (fromInfo is Map) ? "${fromInfo['employeeName'] ?? ''} (${fromInfo['employeeId'] ?? ''})" : fromInfo.toString();

    // Collect server-side filenames to include with the forwarded message
    final fwdFilenames = <String>{};
    // collect from per-message attachments
    for (final m in messages) {
      if (m is Map && m['attachments'] is List) {
        for (final a in (m['attachments'] as List)) {
          if (a is Map && a['filename'] != null) {
            fwdFilenames.add(a['filename']);
          } else if (a is String) {
            fwdFilenames.add(a);
          }
        }
      }
    }
    // also include thread-level attachments (defensive)
    if (thread['attachments'] is List) {
      for (final a in (thread['attachments'] as List)) {
        if (a is Map && a['filename'] != null) fwdFilenames.add(a['filename']);
      }
    }

    setState(() {
      isReplyOrForward = true;
      selectedMenu = 2; // full compose
      attachments.clear();
      _toCtrl.clear();
      _ccCtrl.clear();
      _bccCtrl.clear();
      _subCtrl.text = "Fwd: ${thread['subject'] ?? ''}";
      _bodyCtrl.text = "----- Forwarded Message -----\nFrom: $fromText\n\n${last is Map ? (last['body'] ?? '') : ''}";
      currentThreadId = null; // FORWARD -> create new thread
      _forwardedAttachments = fwdFilenames.toList();
      _editingDraftId = null;
    });
  }

  // small helper: count unread-like items defensively
  int _countUnread(List list) {
    try {
      return list.where((m) {
        if (m is Map) {
          if (m.containsKey('unread')) return m['unread'] == true;
          if (m.containsKey('isRead')) return m['isRead'] == false;
          // maybe thread has participants read info
          return false;
        }
        return false;
      }).length;
    } catch (e) {
      return 0;
    }
  }

  // small helper: apply local search filter by subject/preview/participants
  List _applySearchFilter(List source) {
    if (_searchQuery.isEmpty) return source;
    return source.where((item) {
      if (item is Map) {
        final subject = (item['subject'] ?? "").toString().toLowerCase();
        final preview = (item['lastMessagePreview'] ?? item['body'] ?? "").toString().toLowerCase();
        final parts = item['participants'] is List ? (item['participants'] as List).join(' ') : '';
        final participants = parts.toString().toLowerCase();
        return subject.contains(_searchQuery) || preview.contains(_searchQuery) || participants.contains(_searchQuery);
      }
      return false;
    }).toList();
  }

  Widget _menuButton(icon, text, index) {
    final selected = selectedMenu == index;
    int badge = 0;
    if (index == 0) badge = _countUnread(inbox);
    if (index == 1) badge = _countUnread(sent);
    if (index == 4) badge = _countUnread(trash);
    if (index == 5) badge = drafts.length; // show drafts count

    return InkWell(
      onTap: () => setState(() {
        // If leaving Compose, ensure draft save
        if (selectedMenu == 2 && index != 2) {
          _scheduleDraftSave(); // schedule immediate save
        }
        selectedMenu = index;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? Colors.deepPurple.shade50 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? Colors.deepPurple : Colors.black54, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? Colors.deepPurple : Colors.black87,
                  )),
            ),
            if (badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.deepPurple, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  badge > 99 ? '99+' : badge.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    switch (selectedMenu) {
      case 0:
        return _buildInbox();
      case 1:
        return _buildSent();
      case 2:
        return _buildCompose();
      case 3:
        return _buildViewMail();
      case 4:
        return _buildTrash();
      case 5:
        return _buildDrafts();
      default:
        return const SizedBox();
    }
  }

  Widget _buildInbox() {
    if (loadingInbox) return const Center(child: CircularProgressIndicator());
    final displayed = _applySearchFilter(inbox);
    if (displayed.isEmpty) return const Center(child: Text("No inbox mails"));
    return RefreshIndicator(
      onRefresh: () async => await loadInbox(silent: false),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: displayed.length,
        itemBuilder: (context, i) {
          final mail = displayed[i];
          final preview = mail['lastMessagePreview'] ?? "";
          final fromName = (mail['messages'] is List && (mail['messages'] as List).isNotEmpty)
              ? ((mail['messages'].last['from'] is Map) ? (mail['messages'].last['from']['employeeName'] ?? '') : mail['messages'].last['from'].toString())
              : (mail['participants'] != null && (mail['participants'] as List).isNotEmpty ? (mail['participants'][0] ?? '') : '');
          final dateIso = _extractLastActivityDate(mail);
          return _mailCard(
            subject: mail["subject"] ?? "",
            subtitle: "$fromName • ${preview.toString().length > 120 ? '${preview.toString().substring(0, 120)}...' : preview}",
            onTap: () => openMail(mail["_id"]),
            dateIso: dateIso,
            isUnread: mail['unread'] == true || mail['isRead'] == false,
            avatarText: fromName,
          );
        },
      ),
    );
  }

  Widget _buildSent() {
    if (loadingSent) return const Center(child: CircularProgressIndicator());
    final displayed = _applySearchFilter(sent);
    if (displayed.isEmpty) return const Center(child: Text("No sent mails"));
    return RefreshIndicator(
      onRefresh: () async => await loadSent(silent: false),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: displayed.length,
        itemBuilder: (context, i) {
          final mail = displayed[i];
          final preview = mail['lastMessagePreview'] ?? "";
          final dateIso = _extractLastActivityDate(mail);
          return _mailCard(
            subject: mail["subject"] ?? "",
            subtitle: "You • ${preview.toString().length > 120 ? '${preview.toString().substring(0, 120)}...' : preview}",
            onTap: () => openMail(mail["_id"]),
            dateIso: dateIso,
            isUnread: false,
            avatarText: 'You',
          );
        },
      ),
    );
  }

  Widget _buildTrash() {
    if (loadingTrash) return const Center(child: CircularProgressIndicator());
    final displayed = _applySearchFilter(trash);
    if (displayed.isEmpty) return const Center(child: Text("Trash is empty"));
    return RefreshIndicator(
      onRefresh: () async => await loadTrash(silent: false),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: displayed.length,
        itemBuilder: (context, i) {
          final mail = displayed[i];
          final preview = mail['lastMessagePreview'] ?? "";
          final dateIso = _extractLastActivityDate(mail);
          return _mailCard(
            subject: mail["subject"] ?? "",
            subtitle: "${preview.toString().length > 120 ? '${preview.toString().substring(0, 120)}...' : preview}",
            onTap: () => openMail(mail["_id"]),
            dateIso: dateIso,
            avatarText: null,
          );
        },
      ),
    );
  }

  // New: Drafts list view
  Widget _buildDrafts() {
    if (loadingDrafts) return const Center(child: CircularProgressIndicator());
    final displayed = _applySearchFilter(drafts);
    if (displayed.isEmpty) return const Center(child: Text("No drafts"));
    return RefreshIndicator(
      onRefresh: () async => await loadDrafts(silent: false),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: displayed.length,
        itemBuilder: (context, i) {
          final d = displayed[i];
          final subject = d['subject'] ?? "(No subject)";
          final preview = (d['body'] ?? "").toString();
          final dateIso = _extractLastActivityDate(d);
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.deepPurple.shade100,
                child: Text(subject.isNotEmpty ? subject[0].toUpperCase() : "D"),
              ),
              title: Text(subject, style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold)),
              subtitle: Text(preview.length > 120 ? '${preview.substring(0, 120)}...' : preview),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Text(formatRelativeDate(dateIso), style: const TextStyle(color: Colors.black54)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.green),
                    onPressed: () => _openDraftForEdit(d),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteDraft(d['_id']?.toString() ?? ""),
                  ),
                ],
              ),
              onTap: () => _openDraftForEdit(d),
            ),
          );
        },
      ),
    );
  }

  Widget _mailCard({required String subject, required String subtitle, required VoidCallback onTap, dynamic dateIso, bool isUnread = false, String? avatarText}) {
    final dateText = (dateIso != null && dateIso.toString().isNotEmpty) ? formatRelativeDate(dateIso) : null;
    final initials = (avatarText ?? subject).toString().trim().isNotEmpty ? (avatarText ?? subject).toString().trim()[0].toUpperCase() : '?';
    return Card(
      elevation: isUnread ? 3 : 1,
      color: isUnread ? Colors.white : Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          backgroundColor: isUnread ? Colors.deepPurple.shade100 : Colors.grey.shade200,
          child: Text(initials, style: TextStyle(color: isUnread ? Colors.white : Colors.black87)),
        ),
        title: Text(subject,
            style: TextStyle(
              fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
              color: Colors.deepPurple,
            )),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.black54, fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dateText != null)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Text(dateText, style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  /// Reusable Autocomplete field that writes the selected employeeId into [targetCtrl]
  Widget _buildRecipientAutocompleteField(TextEditingController targetCtrl, {String hint = "Recipients (Type name...)"}) {
    return Autocomplete<Map<String, dynamic>>(
      optionsBuilder: (TextEditingValue value) async {
        final query = value.text.split(",").last.trim();
        if (query.isEmpty) return const Iterable.empty();
        final res = await http.get(Uri.parse("https://hrm-backend-rm6c.onrender.com/api/employees/search/$query"));
        if (res.statusCode != 200) return const Iterable.empty();
        List list = json.decode(res.body);
        return list.cast<Map<String, dynamic>>();
      },
      displayStringForOption: (option) => "${option['employeeName']} (${option['employeeId']})",
      onSelected: (option) {
        final empId = option["employeeId"];
        List existing = targetCtrl.text.split(",").map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        if (!existing.contains(empId)) {
          existing.add(empId);
        }
        targetCtrl.text = existing.join(", ");
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        controller.value = targetCtrl.value;
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: _purpleBox(hint),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 350,
              constraints: const BoxConstraints(maxHeight: 300),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final opt = options.elementAt(index);
                  final imagePath = opt["employeeImage"] != null ? "https://hrm-backend-rm6c.onrender.com${opt['employeeImage']}" : null;
                  return ListTile(
                    leading: ClipOval(
                      child: imagePath != null
                          ? Image.network(
                              imagePath,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Image.asset('assets/profile.png', width: 40, height: 40),
                            )
                          : Image.asset('assets/profile.png', width: 40, height: 40),
                    ),
                    title: Text(
                      opt["employeeName"],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                    subtitle: Text(
                      "${opt['employeeId']} • ${opt['position'] ?? ''}",
                      style: const TextStyle(color: Colors.black54),
                    ),
                    onTap: () => onSelected(opt),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // Compose UI - added CC and BCC fields above Subject (now autocomplete-enabled)
  Widget _buildCompose() {
    // if compose is new and clear, ensure no leftover forward flag
    if (!isReplyOrForward &&
        selectedMenu == 2 &&
        attachments.isEmpty &&
        _bodyCtrl.text.isEmpty &&
        _subCtrl.text.isEmpty &&
        _toCtrl.text.isEmpty &&
        _forwardedAttachments.isEmpty) {
      _toCtrl.clear();
      _subCtrl.clear();
      _bodyCtrl.clear();
    }
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // To field with autocomplete
          _buildRecipientAutocompleteField(_toCtrl, hint: "To (Type employee name...)"),
          const SizedBox(height: 8),
          // CC (autocomplete-enabled)
          _buildRecipientAutocompleteField(_ccCtrl, hint: "CC (comma separated employeeIds)"),
          const SizedBox(height: 8),
          // BCC (autocomplete-enabled)
          _buildRecipientAutocompleteField(_bccCtrl, hint: "BCC (comma separated employeeIds)"),
          const SizedBox(height: 12),
          _composeField(_subCtrl, "Subject"),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: _bodyCtrl,
              expands: true,
              maxLines: null,
              decoration: _purpleBox("Type your message..."),
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: pickFiles,
            icon: const Icon(Icons.attach_file),
            label: Text("Attachments (${attachments.length + _forwardedAttachments.length})"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: sending ? null : sendMail,
                icon: const Icon(Icons.send),
                label: const Text("Send"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 20),
              ElevatedButton.icon(
                onPressed: () {
                  // when canceling compose, schedule immediate save (so user can resume later)
                  _scheduleDraftSave();
                  isReplyOrForward = false;
                  setState(() => selectedMenu = 0);
                },
                icon: const Icon(Icons.cancel),
                label: const Text("Cancel"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildAttachmentPreview(),
        ],
      ),
    );
  }

  Widget _composeField(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      decoration: _purpleBox(hint),
    );
  }

  InputDecoration _purpleBox(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.deepPurple.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide.none,
      ),
    );
  }

  // Updated attachment preview to show both local picked attachments and forwarded attachments
  Widget _buildAttachmentPreview() {
    if (attachments.isEmpty && _forwardedAttachments.isEmpty) return const SizedBox();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.deepPurple.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Attachments:",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          // Local (picked) attachments
          ...attachments.asMap().entries.map((entry) {
            final index = entry.key;
            final file = entry.value;
            final isImage = ["png", "jpg", "jpeg"].contains(file.extension?.toLowerCase());
            return Card(
              child: ListTile(
                leading: isImage && file.bytes != null
                    ? Image.memory(
                        file.bytes!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      )
                    : const Icon(Icons.file_present, color: Colors.deepPurple),
                title: Text(file.name),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => setState(() {
                    attachments.removeAt(index);
                    _scheduleDraftSave(); // update draft attachments
                  }),
                ),
              ),
            );
          }),
          // Forwarded attachments (server-side files)
          ..._forwardedAttachments.map((fname) {
            return Card(
              child: ListTile(
                leading: const Icon(Icons.attach_file, color: Colors.deepPurple),
                title: Text(fname),
                subtitle: const Text("Server file"),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => setState(() {
                    _forwardedAttachments.remove(fname);
                    _scheduleDraftSave();
                  }),
                ),
              ),
            );
          })
        ],
      ),
    );
  }

  // Inline composer widget (compact) — used in thread view below the message
  Widget _inlineComposer() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // show recipients compact
          if (_inlineToCtrl.text.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _inlineToCtrl.text.split(",").map((s) => s.trim()).where((s) => s.isNotEmpty).map((id) {
                return Chip(label: Text(id), backgroundColor: Colors.grey.shade100);
              }).toList(),
            ),
          if (_inlineToCtrl.text.isNotEmpty) const SizedBox(height: 6),
          // CC/BCC toggle + compact input if expanded
          Row(
            children: [
              TextButton(
                onPressed: () => setState(() => _inlineShowCc = !_inlineShowCc),
                child: Text(_inlineShowCc ? "Hide CC" : "Add CC"),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(() => _inlineShowBcc = !_inlineShowBcc),
                child: Text(_inlineShowBcc ? "Hide BCC" : "Add BCC"),
              ),
              const Spacer(),
              // Attach button for inline replies
              ElevatedButton.icon(
                onPressed: pickInlineFiles,
                icon: const Icon(Icons.attach_file, size: 18),
                label: Text("Attachments (${_inlineAttachments.length})"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
            ],
          ),
          if (_inlineShowCc) ...[
            const SizedBox(height: 6),
            _smallPillInput(_inlineCcCtrl, "CC (comma separated)"),
          ],
          if (_inlineShowBcc) ...[
            const SizedBox(height: 6),
            _smallPillInput(_inlineBccCtrl, "BCC (comma separated)"),
          ],
          const SizedBox(height: 8),
          // minimal body editor (multiline but compact)
          TextField(
            controller: _inlineBodyCtrl,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: "Write a reply...",
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),

          // Inline attachments preview
          if (_inlineAttachments.isNotEmpty) ...[
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _inlineAttachments.asMap().entries.map((e) {
                final i = e.key;
                final f = e.value;
                final isImage = ["png", "jpg", "jpeg"].contains(f.extension?.toLowerCase());
                return Card(
                  child: ListTile(
                    leading: isImage && f.bytes != null
                        ? Image.memory(f.bytes!, width: 40, height: 40, fit: BoxFit.cover)
                        : const Icon(Icons.file_present, color: Colors.deepPurple),
                    title: Text(f.name),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => setState(() => _inlineAttachments.removeAt(i)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _inlineSending ? null : _sendInlineReply,
                icon: const Icon(Icons.send),
                label: const Text("Send"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple,foregroundColor: Colors.white),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    showInlineReply = false;
                    replyTargetIndex = null;
                    _inlineBodyCtrl.clear();
                    _inlineCcCtrl.clear();
                    _inlineBccCtrl.clear();
                    _inlineToCtrl.clear();
                    _inlineAttachments.clear();
                    _inlineShowCc = false;
                    _inlineShowBcc = false;
                  });
                },
                child: const Text("Cancel"),
              ),
            ],
          )
        ],
      ),
    );
  }

  // small pill-styled text input for inline CC/BCC
  Widget _smallPillInput(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      ),
    );
  }

  // View thread instead of single mail - render messages array and attachments
  Widget _buildViewMail() {
    if (selectedMail == null) return const Center(child: CircularProgressIndicator());
    final thread = selectedMail!;
    final bool isTrash = selectedMenu == 4;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () => _prepareReplyMail(thread),
                icon: const Icon(Icons.reply),
                label: const Text("Reply"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: () => _prepareReplyAll(thread),
                icon: const Icon(Icons.reply_all),
                label: const Text("Reply all"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: () => _prepareForwardMail(thread),
                icon: const Icon(Icons.forward),
                label: const Text("Forward"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              if (!isTrash)
                ElevatedButton.icon(
                  onPressed: () => _moveToTrash(thread["_id"]),
                  icon: const Icon(Icons.delete),
                  label: const Text("Trash"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              if (isTrash) ...[
                ElevatedButton.icon(
                  onPressed: () => _restoreMail(thread["_id"]),
                  icon: const Icon(Icons.restore),
                  label: const Text("Restore"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: () => _deleteForever(thread["_id"]),
                  icon: const Icon(Icons.delete_forever),
                  label: const Text("Delete Forever"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ]
            ],
          ),
          const SizedBox(height: 20),
          // thread header (subject)
          Text(
            thread["subject"] ?? "",
            style: const TextStyle(
              color: Colors.deepPurple,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          // messages list with expand/collapse previews
          Expanded(
            child: ListView.builder(
              itemCount: (thread["messages"] ?? []).length,
              itemBuilder: (context, idx) {
                final msg = thread["messages"][idx];
                final isExpanded = expandedMessages.contains(idx);
                final bodyText = (msg["body"] ?? "").toString();
                final preview = bodyText.split("\n").take(3).join("\n");
                final from = msg['from'] is Map ? msg['from'] : {'employeeName': msg['from'], 'employeeId': msg['from']};
                final fromName = from['employeeName'] ?? from['employeeId'] ?? "";
                final fromId = from['employeeId'] ?? "";

                final isHeaderExpanded = expandedHeaderDetails.contains(idx);

                // message createdAt for display (if present)
                final messageCreated = msg['createdAt'];

                return Column(
                  children: [
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // avatar (safe)
                                ClipOval(
                                  child: (from['employeeImage'] != null)
                                      ? Image.network(
                                          "https://hrm-backend-rm6c.onrender.com${from['employeeImage']}",
                                          width: 44,
                                          height: 44,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Image.asset('assets/profile.png', width: 44, height: 44),
                                        )
                                      : Image.asset('assets/profile.png', width: 44, height: 44),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // 🔥 Gmail-style header with expandable details
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              // Left: name + meta toggle + small icons
                                              Expanded(
                                                child: Row(
                                                  children: [
                                                    Text(
                                                      "$fromName ($fromId)",
                                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    IconButton(
                                                      icon: Icon(
                                                        isHeaderExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                                        color: Colors.grey,
                                                      ),
                                                      onPressed: () {
                                                        setState(() {
                                                          if (isHeaderExpanded) {
                                                            expandedHeaderDetails.remove(idx);
                                                          } else {
                                                            expandedHeaderDetails.add(idx);
                                                          }
                                                        });
                                                      },
                                                    ),
                                                    const SizedBox(width: 6),
                                                    // Small left-aligned action icons (keep functionality)
                                                    IconButton(
                                                      icon: const Icon(Icons.reply, size: 18),
                                                      tooltip: 'Reply',
                                                      onPressed: () {
                                                        currentThreadId = thread['_id']?.toString();
                                                        _prepareReplyMail(thread, targetIndex: idx);
                                                      },
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(Icons.reply_all, size: 18),
                                                      tooltip: 'Reply all',
                                                      onPressed: () {
                                                        currentThreadId = thread['_id']?.toString();
                                                        _prepareReplyAll(thread, targetIndex: idx);
                                                      },
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(Icons.forward, size: 18),
                                                      tooltip: 'Forward',
                                                      onPressed: () {
                                                        _prepareForwardMail(thread);
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),

                                          if (isHeaderExpanded) ...[
                                            const SizedBox(height: 6),

                                            _buildHeaderDetailRow("From:", "$fromName ($fromId)"),

                                            if (msg["to"] != null)
                                              _buildHeaderDetailRow(
                                                "To:",
                                                (msg["to"] as List)
                                                    .map((e) => e is Map ? "${e['employeeName']} (${e['employeeId']})" : e.toString())
                                                    .join(", "),
                                              ),

                                            if (msg["cc"] != null && (msg["cc"] as List).isNotEmpty)
                                              _buildHeaderDetailRow(
                                                "CC:",
                                                (msg["cc"] as List)
                                                    .map((e) => e is Map ? "${e['employeeName']} (${e['employeeId']})" : e.toString())
                                                    .join(", "),
                                              ),

                                            if (msg["bcc"] != null && (msg["bcc"] as List).isNotEmpty)
                                              _buildHeaderDetailRow(
                                                "BCC:",
                                                (msg["bcc"] as List)
                                                    .map((e) => e is Map ? "${e['employeeName']} (${e['employeeId']})" : e.toString())
                                                    .join(", "),
                                              ),

                                            if (messageCreated != null)
                                              _buildHeaderDetailRow("Date:", formatFullDateTime(messageCreated)),

                                            const Divider(),
                                          ],

                                          // message body (preview or full)
                                          Text(isExpanded ? bodyText : preview, style: const TextStyle(fontSize: 15)),
                                          const SizedBox(height: 8),

                                          if (msg["attachments"] != null && (msg["attachments"] as List).isNotEmpty)
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: (msg["attachments"] as List).map<Widget>((file) {
                                                final filename = file["filename"] ?? file.toString().split("/").last;
                                                final fileUrl = "https://hrm-backend-rm6c.onrender.com/uploads/${file['filename'] ?? file['path']?.split('/')?.last}";
                                                final originalName = file["originalName"] ?? filename;
                                                return ListTile(
                                                  contentPadding: EdgeInsets.zero,
                                                  leading: const Icon(Icons.attach_file, color: Colors.deepPurple),
                                                  title: Text(originalName),
                                                  onTap: () async {
                                                    final uri = Uri.parse(fileUrl);
                                                    if (await canLaunchUrl(uri)) {
                                                      await launchUrl(uri);
                                                    } else {
                                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not open attachment")));
                                                    }
                                                  },
                                                );
                                              }).toList(),
                                            ),
                                        ],
                                      ),

                                IconButton(
                                  icon: Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                                  onPressed: () {
                                    setState(() {
                                      if (isExpanded) {
                                        expandedMessages.remove(idx);
                                      } else {
                                        expandedMessages.add(idx);
                                      }
                                    });
                                  },
                                ),
                              ],
                            ),
                            ),
                            ],
                        ),],
                        ),
                      ),
                    ),
                    // render inline composer if targeted here
                    if (showInlineReply && replyTargetIndex == idx) _inlineComposer(),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          // Optionally render thread-level attachments if any (defensive)
          if (thread["attachments"] != null && (thread["attachments"] as List).isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Attachments:",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                ...((thread["attachments"] as List)).map<Widget>((file) {
                  final filename = file["filename"] ?? file.toString().split("/").last;
                  final fileUrl = "https://hrm-backend-rm6c.onrender.com/uploads/${file['filename'] ?? file['path']?.split('/')?.last}";
                  final originalName = file["originalName"] ?? filename;
                  return InkWell(
                    onTap: () async {
                      final uri = Uri.parse(fileUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not open attachment")));
                      }
                    },
                    child: Card(
                      child: ListTile(
                        leading: const Icon(Icons.attach_file, color: Colors.deepPurple),
                        title: Text(originalName),
                      ),
                    ),
                  );
                }),
              ],
            ),
        ],
      ),
    );
  }

  // Helper to render header detail rows (From/To/CC/BCC/Date)
  Widget _buildHeaderDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search mail (subject, sender, preview)',
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(Icons.search, color: Colors.black54),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => loadAll(silent: false),
            ),
            const SizedBox(width: 6),
          ],
        ),
        backgroundColor: Colors.deepPurple,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            selectedMenu = 2; // open compose
            isReplyOrForward = false;
            _toCtrl.clear();
            _ccCtrl.clear();
            _bccCtrl.clear();
            _subCtrl.clear();
            _bodyCtrl.clear();
            attachments.clear();
            _forwardedAttachments.clear();
            _editingDraftId = null;
          });
        },
        backgroundColor: Colors.deepPurple,foregroundColor: Colors.white,
        child: const Icon(Icons.create),
      ),
      body: Row(
        children: [
          Container(
            width: 260,
            padding: const EdgeInsets.all(12),
            color: Colors.grey[100],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile / brand area
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.deepPurple.shade200,
                      child: const Icon(Icons.mail, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('Mail Portal', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _menuButton(Icons.inbox, "Inbox", 0),
                const SizedBox(height: 6),
                _menuButton(Icons.send, "Sent", 1),
                const SizedBox(height: 6),
                _menuButton(Icons.delete, "Trash", 4),
                const SizedBox(height: 6),
                _menuButton(Icons.edit, "Compose", 2),
                const SizedBox(height: 6),
                _menuButton(Icons.drafts, "Drafts", 5),
                const SizedBox(height: 18),
                const Divider(),
                const SizedBox(height: 8),
                Text('Auto-refresh: every 30s', style: TextStyle(color: Colors.black54, fontSize: 12)),
                const SizedBox(height: 6),
                ElevatedButton.icon(
                  onPressed: () => loadAll(silent: false),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh now'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple,foregroundColor: Colors.white,),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: Colors.white,
              child: _buildMainContent(),
            ),
          ),
        ],
      ),
    );
  }
}
