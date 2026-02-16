//routes/notifications.js 

const express = require('express');
const router = express.Router();
const Notification = require("../models/notifications");
const multer = require('multer');
const path = require('path');
const fs = require('fs');

// =======================
// MULTER CONFIG (Attachments)
// =======================
const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    const uploadDir = 'uploads/notifications';
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    cb(null, Date.now() + '-' + file.originalname);
  }
});

const upload = multer({ storage });

// 🔹 Get ALL notifications for a specific employee with optional month & category filter
router.get('/employee/:empId', async (req, res) => {
  try {
    const { empId } = req.params;
    const { month, year, category } = req.query; 

    // This ensures we find items where the employee is either the subject (empId) 
    // or the one receiving a message (receiverId)
    let query = {
      $or: [
        { empId: empId },
        { receiverId: empId }
      ]
    };

    if (category) query.category = category;
    if (month) query.month = { $regex: new RegExp(`^${month}$`, 'i') };
    if (year) query.year = Number(year);

    const notifications = await Notification.find(query).sort({ createdAt: -1 });
    
    // Always return an array, even if empty, so Flutter doesn't crash
    res.json(notifications || []);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: "Server error" });
  }
});

// 🔹 HOLIDAYS
// Employee holidays
router.get('/holiday/employee/:empId', async (req, res) => {
  try {
    const { empId } = req.params;
    const { month, year } = req.query;

    const query = {
      category: "holiday",
      $or: [{ empId }, { empId: null }, { empId: "" }]
    };

    if (month) {
      query.month = { $regex: new RegExp(`^${month}$`, 'i') };
    }

    if (year) {
      query.year = Number(year);
    }

    const holidays = await Notification.find(query)
      .sort({ year: 1, month: 1, day: 1 });

    if (!holidays.length) {
      return res.status(404).json({ message: "No holiday notifications found" });
    }

    res.json(holidays);
  } catch (err) {
    console.error("Error fetching employee holiday notifications:", err);
    res.status(500).json({ message: "Server error" });
  }
});

// Admin holidays
router.get('/holiday/admin/:month', async (req, res) => {
  try {
    const { month } = req.params;
    const { year } = req.query;

    const query = {
      category: "holiday",
      month: { $regex: new RegExp(`^${month}$`, 'i') }
    };

    if (year) {
      query.year = Number(year);
    }

    const holidays = await Notification.find(query).sort({ createdAt: -1 });

    if (!holidays.length) {
      return res.status(404).json({ message: "No holiday notifications for admin" });
    }

    res.json(holidays);
  } catch (err) {
    console.error("Error fetching admin holiday notifications:", err);
    res.status(500).json({ message: "Server error" });
  }
});

// 1. Performance → Admin view (Optimized)
router.get('/performance/admin/:adminId', async (req, res) => {
    const { adminId } = req.params;
    const { month, year } = req.query;
    try {
        const query = {
          category: "performance",
          empId: adminId,  // 👈 Only show the copy owned by the Admin
          // receiverId: { $ne: adminId } // 👈 Ensures it's a 'Sent' record
        };

        if (month) query.month = { $regex: new RegExp(`^${month}$`, 'i') };
        if (year) query.year = Number(year);

        const notifications = await Notification.find(query).sort({ createdAt: -1 });
        res.json(notifications || []);
    } catch (err) {
        res.status(500).json({ message: 'Server error' });
    }
});

// 2. Performance → Employee view
router.get('/performance/employee/:month/:empId', async (req, res) => {
  const { month, empId } = req.params;
  const { year } = req.query; // ✅ Added year filter support
  try {
    const query = {
      category: "performance",
      month: { $regex: new RegExp(`^${month}$`, 'i') },
      $or: [{ empId }, { empId: null }, { empId: "" }],
    };

    if (year) query.year = Number(year);

    const notifications = await Notification.find(query).sort({ createdAt: -1 });

    if (!notifications.length) {
      return res.status(404).json({ message: "No performance notifications for this employee" });
    }

    res.json(notifications);
  } catch (err) {
    console.error("Error fetching performance for employee:", err);
    res.status(500).json({ message: 'Server error' });
  }
});

// ==========================================
// 3. PERFORMANCE: SUPER ADMIN VIEW (All Reviews)
// ==========================================
// ✅ UPDATED SUPERADMIN ROUTE
router.get('/performance/superadmin/all', async (req, res) => {
    try {
        const { month, year } = req.query;
        let query = { category: "performance" };

        if (month) query.month = { $regex: new RegExp(`^${month}$`, 'i') };
        if (year) query.year = Number(year);

        const notifications = await Notification.find(query).sort({ createdAt: -1 });
        res.json(notifications);
    } catch (err) {
        res.status(500).json({ message: "Server error" });
    }
});

// 1️⃣ Get holidays by YEAR (Holiday Master main fetch)
router.get('/holiday/year/:year', async (req, res) => {
  try {
    const { year } = req.params;

    const holidays = await Notification.find({
      category: "holiday",
      year: Number(year),
      state: "TN"
    }).sort({ month: 1, day: 1 });

    if (!holidays.length) {
      return res.json({ data: [], message: "NO_RECORDS" });
    }

    res.json({ data: holidays });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: "Server error" });
  }
});

// 2️⃣ Clone holidays from previous year
router.post('/holiday/clone', async (req, res) => {
  try {
    const { fromYear, toYear } = req.body;

    if (fromYear === toYear) {
      return res.status(400).json({ message: "Same year clone not allowed" });
    }

    const exists = await Notification.findOne({
      category: "holiday",
      year: toYear
    });

    if (exists) {
      return res.status(409).json({ message: "Target year already exists" });
    }

    const prevHolidays = await Notification.find({
      category: "holiday",
      year: fromYear
    });

    if (!prevHolidays.length) {
      return res.status(404).json({ message: "Previous year not found" });
    }

    const cloned = prevHolidays.map(h => ({
      category: "holiday",
      holidayType: h.holidayType,
      year: toYear,
      month: h.month,
      day: h.day,
      message: h.message,
      state: "TN"
    }));

    await Notification.insertMany(cloned);

    res.json({ message: "Holiday cloned successfully" });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: "Server error" });
  }
});

// UPDATE holiday
router.put('/holiday/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const { year, month, day, message, holidayType } = req.body;

    await Notification.findByIdAndUpdate(id, {
      year,
      month,
      day,
      message,
      holidayType
    });

    res.json({ message: "Holiday updated" });
  } catch (err) {
    res.status(500).json({ message: "Server error" });
  }
});

// DELETE holiday
router.delete('/holiday/:id', async (req, res) => {
  try {
    await Notification.findByIdAndDelete(req.params.id);
    res.json({ message: "Holiday deleted" });
  } catch (err) {
    res.status(500).json({ message: "Server error" });
  }
});

// 3️⃣ Add / Edit single holiday (popup save)
router.post('/holiday', async (req, res) => {
  try {
    const { year, month, day, message, holidayType } = req.body;

    const holiday = new Notification({
      category: "holiday",
      year,
      month,
      day,
      message,
      holidayType,
      state: "TN"
    });

    await holiday.save();
    res.status(201).json({ message: "Holiday saved" });
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: "Server error" });
  }
});

// ✅ Add a new notification
router.post('/', async (req, res) => {
  try {
    const { month, year, category, message, empId, senderName, senderId, flag , communication, attitude, technicalKnowledge, business, empName, receiverId } = req.body;
    if (!message || !empId || !category) {
      return res.status(400).json({ message: "Required fields missing" });
    }
    const newNotification = new Notification({ 
      month, 
      year: year || new Date().getFullYear(), // Handle year if missing
      category, 
      message, 
      empId,
      receiverId: receiverId || "",
      senderName: senderName || "",
      senderId: senderId || "",
      flag: flag || "" ,
      // 🔹 Save Performance Specifics
      communication: communication || "",
      attitude: attitude || "",
      technicalKnowledge: technicalKnowledge || "",
      business: business || "",
      empName: empName || ""
    });

    await newNotification.save();
    res.status(201).json({ message: 'Notification added successfully' });
  } catch (err) {
    console.error('Error adding notification:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

// =======================
// ADD NOTIFICATION WITH ATTACHMENTS
// =======================
router.post('/with-files', upload.array('attachments'), async (req, res) => {
  try {
    const { month, year, category, message, empId, senderName, senderId, flag ,
      communication, attitude, technicalKnowledge, business, empName, receiverId} = req.body;

    if (!message || !empId || !category) {
      return res.status(400).json({ message: "Required fields missing" });
    }

    const attachments = (req.files || []).map(file => ({
      filename: file.filename,
      originalName: file.originalname,
      path: file.path,
      mimetype: file.mimetype,
      size: file.size
    }));

    const newNotification = new Notification({
      month,
      year: year || new Date().getFullYear(),
      category,
      message,
      empId,
      receiverId: receiverId || "",
      senderName: senderName || "",
      senderId: senderId || "",
      flag: flag || "",
      attachments,
      // 🔹 Save Performance Specifics
      communication: communication || "",
      attitude: attitude || "",
      technicalKnowledge: technicalKnowledge || "",
      business: business || "",
      empName: empName || ""
    });

    await newNotification.save();

    res.status(201).json({
      message: "Notification with attachments saved",
      data: newNotification
    });
  } catch (err) {
    console.error("Attachment upload error:", err);
    res.status(500).json({ message: "Server error" });
  }
});

// 🔹 Get unread notification count for badge
router.get('/unread-count/:empId', async (req, res) => {
  try {
    const { empId } = req.params;

    const count = await Notification.countDocuments({
      isRead: false,
      $or: [
        { empId: empId },
        { receiverId: empId },
        { category: "holiday" } 
      ]
    });

    res.json({ count });
  } catch (err) {
    console.error("Unread count error:", err);
    res.status(500).json({ message: "Server error" });
  }
});

// 🔹 Mark all notifications as read for employee
router.put('/mark-read/:empId', async (req, res) => {
  try {
    const { empId } = req.params;

    await Notification.updateMany(
      {
        isRead: false,
        $or: [
          { empId: empId },
          { receiverId: empId },
          { category: "holiday" } 
        ]
      },
      { $set: { isRead: true } }
    );

    res.json({ message: "Notifications marked as read" });
  } catch (err) {
    console.error("Mark read error:", err);
    res.status(500).json({ message: "Server error" });
  }
});



module.exports = router;