// models/attendance.js
const mongoose = require("mongoose");

const AttendanceSchema = new mongoose.Schema(
  {
    employeeId: { type: String, required: true },

    // ✅ Store date as STRING so it always follows DD-MM-YYYY format
    date: { type: String, required: true },

    status: {
      type: String,
      enum: ["Absent", "Login", "Logout"], // ✅ "Absent" still included
      default: "Absent",
    },

    // ✅ Times are kept as strings since you already send formatted times from frontend
    loginTime: { type: String, default: "Not logged in yet" },
    logoutTime: { type: String, default: "Not logged out yet" },
    breakTime: { type: String, default: "-" }, // ✅ Added breakTime

    // ✅ Reasons stay as simple strings
    loginReason: { type: String, default: "-" },
    logoutReason: { type: String, default: "-" },
  },
  { timestamps: true } // ✅ Adds createdAt & updatedAt for sorting history
);

module.exports = mongoose.model("Attendance", AttendanceSchema);
