//models/notifications.js

const mongoose = require("mongoose");

const notificationSchema = new mongoose.Schema({
  category: {
    type: String,
    required: true,
    enum: ["message", "performance", "meeting", "event", "holiday", "leave"]
  },

  // 🔹 Holiday-only fields
  holidayType: {
    type: String,
    enum: ["FIXED", "FLOATING"],
    required: function () {
      return this.category === "holiday";
    }
  },

  month: {
    type: String,
    enum: [
      "January", "February", "March", "April", "May", "June",
      "July", "August", "September", "October", "November", "December"
    ],
    // Made required for most categories as the UI filters by month
    required: true 
  },

  day: {
    type: Number,
    min: 1,
    max: 31,
    required: function () {
      return this.category === "holiday";
    }
  },

  year: {
    type: Number,
    // Now required for all categories to support the Year dropdown filter
    required: true, 
    index: true
  },

  state: {
    type: String,
    default: "TN"
  },

  // 🔹 Content field
  message: {
    type: String,
    // Required for almost everything to display text in the notification card
    required: true 
  },

  // 🔹 Target Employee
  empId: {
    type: String,
    // Optional for global notifications, required for direct messages/performance
    required: function () {
      return this.category === "message" || this.category === "performance";
    }
  },
  receiverId: { type: String, default: "" },
  reviewId: { type: String, default: "" },
  senderId: { type: String, default: "" },
  senderName: { type: String, default: "" },
  flag: { type: String, default: "" },
  communication: { type: String, default: "" },
  attitude: { type: String, default: "" }, 
  technicalKnowledge: { type: String, default: "" },
  business: { type: String, default: "" },
  empName: { type: String, default: "" },
  // ✅ Attachments
  attachments: [
    {
      filename: String,      // original file name
      originalName: String,  // field added to match route logic
      path: String,          // server path
      mimetype: String,
      size: Number
    }
  ],

  // ✅ Read tracking for badge
  isRead: {
    type: Boolean,
    default: false,
    index: true
  },

  createdAt: { type: Date, default: Date.now }

});

module.exports = mongoose.model("Notification", notificationSchema);