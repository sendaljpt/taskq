.pragma library

// Deadline parsing and countdown formatting for the tasks widget.
// Kept free of QML so it can be tested with plain node.

var DAY = 24 * 60 * 60 * 1000
var HOUR = 60 * 60 * 1000
var MINUTE = 60 * 1000

var WEEKDAYS = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

// Parses "17:00", "5pm" or "9.30" into [hours, minutes]; null otherwise.
function parseTime(text) {
  var m = /^(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)?$/.exec(text)
  if (!m) return null
  var hours = Number(m[1])
  var minutes = m[2] ? Number(m[2]) : 0
  if (!m[2] && !m[3]) return null
  if (m[3] && (hours < 1 || hours > 12)) return null
  if (m[3] === "pm" && hours < 12) hours += 12
  if (m[3] === "am" && hours === 12) hours = 0
  if (hours > 23 || minutes > 59) return null
  return [hours, minutes]
}

function atTime(date, time) {
  var d = new Date(date.getFullYear(), date.getMonth(), date.getDate())
  if (time) d.setHours(time[0], time[1], 0, 0)
  else d.setHours(23, 59, 0, 0)
  return d
}

// Turns what the user typed into a deadline timestamp (ms).
// Returns null for "clear the deadline" and NaN when it can't be read.
//
//   +2h, 2h 30m, 1d, +1d 4h      relative to now
//   17:00, 5pm                   today (tomorrow if already past)
//   today, tomorrow [17:00]      end of day unless a time is given
//   fri, friday [9am]            the next such day
//   12/10 [17:00]                day/month, this year (next year if past)
//   2026-10-12 [17:00]           ISO date
function parse(input, now) {
  var text = String(input || "").trim().toLowerCase()
  if (text === "" || text === "none" || text === "clear") return null
  now = now || new Date()

  var relative = /^\+?\s*((?:\d+\s*[dhm]\s*)+)$/.exec(text)
  if (relative) {
    var total = 0
    var part, re = /(\d+)\s*([dhm])/g
    while ((part = re.exec(relative[1])) !== null)
      total += Number(part[1]) * (part[2] === "d" ? DAY : part[2] === "h" ? HOUR : MINUTE)
    return total > 0 ? now.getTime() + total : NaN
  }

  var words = text.split(/\s+/)
  var head = words[0]
  var rest = words.slice(1).join(" ")
  var time = rest ? parseTime(rest) : null
  if (rest && !time) return NaN

  var onlyTime = parseTime(text)
  if (onlyTime) {
    var t = atTime(now, onlyTime)
    if (t.getTime() <= now.getTime()) t = new Date(t.getTime() + DAY)
    return t.getTime()
  }

  if (head === "today" || head === "tonight") return atTime(now, time).getTime()
  if (head === "tomorrow" || head === "tmr" || head === "besok")
    return atTime(new Date(now.getTime() + DAY), time).getTime()

  for (var i = 0; i < WEEKDAYS.length; i++) {
    if (head.indexOf(WEEKDAYS[i]) !== 0) continue
    // Today counts if that time is still ahead; otherwise next week.
    var ahead = (i - now.getDay() + 7) % 7
    var when = atTime(new Date(now.getTime() + ahead * DAY), time)
    if (when.getTime() <= now.getTime()) when = atTime(new Date(now.getTime() + (ahead + 7) * DAY), time)
    return when.getTime()
  }

  var dm = /^(\d{1,2})\/(\d{1,2})(?:\/(\d{4}))?$/.exec(head)
  if (dm) {
    var year = dm[3] ? Number(dm[3]) : now.getFullYear()
    var d = new Date(year, Number(dm[2]) - 1, Number(dm[1]))
    if (d.getMonth() !== Number(dm[2]) - 1) return NaN
    var result = atTime(d, time)
    if (!dm[3] && result.getTime() < now.getTime()) result.setFullYear(year + 1)
    return result.getTime()
  }

  var iso = /^(\d{4})-(\d{2})-(\d{2})$/.exec(head)
  if (iso) {
    var di = new Date(Number(iso[1]), Number(iso[2]) - 1, Number(iso[3]))
    if (di.getMonth() !== Number(iso[2]) - 1) return NaN
    return atTime(di, time).getTime()
  }

  return NaN
}

// "2d 4h 30m", "4h 5m", "12m", "<1m". Leading zero units are dropped.
function span(ms) {
  var minutes = Math.floor(Math.abs(ms) / MINUTE)
  if (minutes < 1) return "<1m"
  var d = Math.floor(minutes / 1440)
  var h = Math.floor((minutes % 1440) / 60)
  var m = minutes % 60
  var parts = []
  if (d > 0) parts.push(d + "d")
  if (d > 0 || h > 0) parts.push(h + "h")
  parts.push(m + "m")
  return parts.join(" ")
}

// Countdown label for a deadline.
function countdown(due, nowMs) {
  var left = due - nowMs
  return left >= 0 ? span(left) + " left" : "overdue " + span(left)
}

// "overdue", "urgent" (under 2 hours), "warning" (under 6 hours) or "ok".
function status(due, nowMs) {
  var left = due - nowMs
  if (left < 0) return "overdue"
  if (left < 2 * HOUR) return "urgent"
  if (left < 6 * HOUR) return "warning"
  return "ok"
}

// "Fri 10 Oct 17:00" for previews and tooltips.
function describe(due) {
  var d = new Date(due)
  var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  var hh = ("0" + d.getHours()).slice(-2)
  var mm = ("0" + d.getMinutes()).slice(-2)
  return days[d.getDay()] + " " + d.getDate() + " " + months[d.getMonth()] + " " + hh + ":" + mm
}

// "12/10 17:00": the editable form of a deadline, readable by parse().
function editable(due) {
  var d = new Date(due)
  var hh = ("0" + d.getHours()).slice(-2)
  var mm = ("0" + d.getMinutes()).slice(-2)
  return d.getDate() + "/" + (d.getMonth() + 1) + "/" + d.getFullYear() + " " + hh + ":" + mm
}
