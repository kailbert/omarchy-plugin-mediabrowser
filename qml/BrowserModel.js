.pragma library

function naturalParts(value) {
  return String(value || "").toLocaleLowerCase().split(/(\d+)/).map(function(part) {
    return /^\d+$/.test(part) ? Number(part) : part
  })
}

function naturalCompare(a, b) {
  var aa = naturalParts(a), bb = naturalParts(b)
  for (var i = 0; i < Math.min(aa.length, bb.length); i++) {
    if (aa[i] === bb[i]) continue
    if (typeof aa[i] === "number" && typeof bb[i] === "number") return aa[i] - bb[i]
    return String(aa[i]).localeCompare(String(bb[i]))
  }
  return aa.length - bb.length
}

function displayRows(entries, filter, sortMode, descending, foldersFirst) {
  var needle = String(filter || "").toLocaleLowerCase()
  var rows = entries.filter(function(row) {
    return !needle || String(row.name || "").toLocaleLowerCase().indexOf(needle) !== -1
  }).slice()
  rows.sort(function(a, b) {
    if (foldersFirst && (a.kind === "folder") !== (b.kind === "folder")) return a.kind === "folder" ? -1 : 1
    var result = 0
    if (sortMode === "modified") result = Number(a.mtime || 0) - Number(b.mtime || 0)
    else if (sortMode === "size") result = Number(a.size || 0) - Number(b.size || 0)
    else if (sortMode === "type") result = naturalCompare(a.mime || a.kind, b.mime || b.kind)
    else result = naturalCompare(a.name, b.name)
    if (result === 0) result = naturalCompare(a.name, b.name)
    return descending ? -result : result
  })
  return rows
}

function formatBytes(value) {
  var n = Number(value || 0)
  if (n < 1024) return n + " B"
  var units = ["KB", "MB", "GB", "TB"]
  var i = -1
  do { n /= 1024; i++ } while (n >= 1024 && i < units.length - 1)
  return (n >= 10 ? n.toFixed(0) : n.toFixed(1)) + " " + units[i]
}

function formatDuration(seconds) {
  var value = Math.max(0, Math.floor(Number(seconds || 0)))
  var h = Math.floor(value / 3600), m = Math.floor((value % 3600) / 60), s = value % 60
  return (h ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(s).padStart(2, "0")
}

function parentPath(path) {
  var value = String(path || "").replace(/\/+$/, "")
  if (!value || value === "/") return "/"
  var at = value.lastIndexOf("/")
  return at <= 0 ? "/" : value.substring(0, at)
}

function basename(path) {
  var value = String(path || "").replace(/\/+$/, "")
  if (!value || value === "/") return "/"
  return value.substring(value.lastIndexOf("/") + 1)
}
