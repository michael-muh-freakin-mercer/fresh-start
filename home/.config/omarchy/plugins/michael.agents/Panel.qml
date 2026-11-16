import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy.agents"
  ipcTarget: "omarchy.agents"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Per-provider accent: collectors ship a `color` field on their record
  // (e.g. crush → magenta, openrouter → indigo). Used to tint the bar icon,
  // the hero meta line, and the selected tab in the provider switch.
  // Falls back to the theme's accent when no provider is selected.
  readonly property color providerAccent: {
    if (!provider || !provider.color) return Color.accent
    var c = Qt.color(provider.color)
    return c.a === 0 ? Color.accent : c
  }

  // Per-provider bar glyph (Nerd Font codepoint). Different glyph per tab
  // so the bar widget transforms visually as the user cycles h/l.
  // Falls back to nf-md-sparkles when no provider is selected.
  readonly property string defaultBarGlyph: "󰘣"
  readonly property string providerBarGlyph: provider && provider.barGlyph
    ? provider.barGlyph
    : defaultBarGlyph

  function costAfter(text, label) {
    var match = String(text || "").match(new RegExp("\\$([0-9.]+)\\s*" + label))
    return match ? parseFloat(match[1]) : -1
  }

  readonly property real todayCostParsed: provider ? costAfter(provider.authHelpText || "", "today") : -1
  readonly property real todayCost: Math.max(0, todayCostParsed)
  readonly property real weekCost: provider ? costAfter(provider.authHelpText || "", "this\\s*week") : -1
  readonly property real allTimeCost: provider ? costAfter(provider.authHelpText || "", "all-time") : -1
  readonly property bool hasCostBreakdown: todayCostParsed >= 0 || weekCost >= 0 || allTimeCost >= 0

  readonly property real todayTokens: {
    if (!provider) return 0
    var t = Number(provider.todayTotalTokens || 0)
    if (t > 0) return t
    var days = provider.recentDays || []
    var td = todayDate()
    for (var i = 0; i < days.length; i++) {
      if (String(days[i].date || "") === td) return Number(days[i].messageCount || 0)
    }
    return 0
  }

  readonly property real weekTokens: {
    if (!provider) return 0
    var days = provider.recentDays || []
    var sum = 0
    for (var i = 0; i < days.length; i++) sum += Number(days[i].messageCount || 0)
    return sum
  }

  readonly property real allTimeTokens: {
    if (!provider) return 0
    var usageByModel = provider.modelUsage || ({})
    var sum = 0
    for (var id in usageByModel) {
      var b = usageByModel[id] || ({})
      sum += Number(b.inputTokens || 0) + Number(b.outputTokens || 0)
        + Number(b.cacheReadInputTokens || 0) + Number(b.cacheCreationInputTokens || 0)
    }
    return sum
  }

  readonly property bool activeToday: todayCost > 0 || todayTokens > 0
    || (provider && (Number(provider.todaySessions || 0) > 0 || Number(provider.todayPrompts || 0) > 0))

  // One-word state for the hero's status dot: the fullest alarm wins,
  // then "did anything happen today", then quiet.
  readonly property string statusLabel: !provider
    ? ""
    : alarming ? "AT LIMIT"
    : activeToday ? "ACTIVE TODAY"
    : "QUIET TODAY"
  readonly property color statusColor: !provider
    ? dim
    : alarming ? urgent
    : activeToday ? providerAccent
    : dim

  readonly property string heroPrimaryText: {
    if (!provider) return "$0.00"
    if (hasCostBreakdown) return "$" + todayCost.toFixed(2)
    if (balance) return formatMoney(balance.remaining, balance.currency)
    return usage.formatTokenCount(todayTokens)
  }

  readonly property string heroPrimarySubtext: {
    if (!provider) return ""
    if (hasCostBreakdown) {
      if (todayTokens > 0)
        return "spent today · " + usage.formatTokenCount(todayTokens) + " tokens"
      return todayCost > 0 ? "spent today" : "spent today · no usage yet"
    }
    if (balance) return "prepaid balance remaining"
    if (todayTokens > 0) {
      var sess = Number(provider.todaySessions || 0)
      return "tokens today" + (sess > 0 ? " · " + sess + (sess === 1 ? " session" : " sessions") : "")
    }
    return "tokens today · no usage yet"
  }

  readonly property string chip1Label: hasCostBreakdown ? "7-DAY SPEND" : "7-DAY TOKENS"
  readonly property string chip1Value: hasCostBreakdown
    ? (weekCost >= 0 ? "$" + weekCost.toFixed(2) : "$0.00")
    : usage.formatTokenCount(weekTokens)

  readonly property string chip2Label: hasCostBreakdown ? "ALL-TIME" : "ALL-TIME TOKENS"
  readonly property string chip2Value: hasCostBreakdown
    ? (allTimeCost >= 0 ? "$" + allTimeCost.toFixed(2) : "$0.00")
    : usage.formatTokenCount(allTimeTokens)

  readonly property string chip3Label: {
    if (!provider) return "SESSIONS"
    if (balance && Number(provider.totalSessions || 0) === 0) return "FUNDED"
    return Number(provider.todaySessions || 0) > 0 ? "TODAY SESSIONS" : "ALL SESSIONS"
  }
  readonly property string chip3Value: {
    if (!provider) return "0"
    if (balance && Number(provider.totalSessions || 0) === 0)
      return formatMoney(balance.funded, balance.currency)
    var todaySess = Number(provider.todaySessions || 0)
    var totalSess = Number(provider.totalSessions || 0)
    if (todaySess > 0 && totalSess > todaySess) return todaySess + " / " + totalSess
    if (todaySess > 0) return String(todaySess)
    return String(totalSess)
  }

  // The Overview tab: combines token usage across all local coding agents and
  // uses the authoritative multi-key OpenRouter spend when available (falling
  // back to summing local agent spend if OpenRouter is disabled).
  function overviewRecord(list) {
    var today = 0, week = 0, allTime = 0
    var todaySess = 0, totalSess = 0, prompts = 0, totalPrompts = 0, todayTok = 0
    var daysByDate = ({})
    var models = ({})
    var activeDaysMax = 0
    var hasOpenRouter = false

    for (var j = 0; j < list.length; j++) {
      if (String(list[j].providerId) === "openrouter") {
        hasOpenRouter = true
        var orText = String(list[j].authHelpText || "")
        var orToday = costAfter(orText, "today")
        var orWeek = costAfter(orText, "this\\s*week")
        var orAll = costAfter(orText, "all-time")
        if (orToday > 0) today += orToday
        if (orWeek > 0) week += orWeek
        if (orAll > 0) allTime += orAll
        break
      }
    }

    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      var isAccountRouter = String(p.providerId) === "openrouter"
      var text = String(p.authHelpText || "")
      if (!hasOpenRouter && !isAccountRouter) {
        var tCost = costAfter(text, "today")
        if (tCost > 0) today += tCost
        var w = costAfter(text, "this\\s*week")
        if (w > 0) week += w
        var a = costAfter(text, "all-time")
        if (a > 0) allTime += a
      }

      todaySess += Number(p.todaySessions || 0)
      totalSess += Number(p.totalSessions || 0)
      prompts += Number(p.todayPrompts || 0)
      totalPrompts += Number(p.totalPrompts || 0)
      todayTok += Number(p.todayTotalTokens || 0)
      activeDaysMax = Math.max(activeDaysMax, Number(p.activeDays || 0))

      var days = p.recentDays || []
      for (var d = 0; d < days.length; d++) {
        var date = String(days[d].date || "")
        if (date === "") continue
        daysByDate[date] = (daysByDate[date] || 0) + Number(days[d].messageCount || 0)
      }

      var modelUsage = p.modelUsage || ({})
      for (var modelId in modelUsage) {
        var normKey = usage.normalizeModelKey(modelId)
        var bucket = modelUsage[modelId] || ({})
        var acc = models[normKey]
        if (!acc) acc = models[normKey] = {
          inputTokens: 0, outputTokens: 0,
          cacheReadInputTokens: 0, cacheCreationInputTokens: 0
        }
        acc.inputTokens += Number(bucket.inputTokens || 0)
        acc.outputTokens += Number(bucket.outputTokens || 0)
        acc.cacheReadInputTokens += Number(bucket.cacheReadInputTokens || 0)
        acc.cacheCreationInputTokens += Number(bucket.cacheCreationInputTokens || 0)
      }
    }

    var dates = []
    for (var day in daysByDate) dates.push(day)
    dates.sort()
    var recentDays = []
    for (var r = 0; r < dates.length; r++)
      recentDays.push({ date: dates[r], messageCount: daysByDate[dates[r]] })

    var statusText = "$" + today.toFixed(2) + " today · $" + week.toFixed(2) + " this week · $" + allTime.toFixed(2) + " all-time"

    return {
      providerId: "__overview__",
      providerName: "Overview",
      tagline: "All coding agents combined",
      color: "",
      barGlyph: "󰘣",
      scope: "device",
      ready: true,
      usageStatusText: "",
      authHelpText: statusText,
      limits: [],
      tierLabel: list.length + " agents",
      balance: null,
      todayPrompts: prompts,
      todaySessions: todaySess,
      todayTotalTokens: todayTok,
      recentDays: recentDays,
      totalPrompts: totalPrompts,
      totalSessions: totalSess,
      activeDays: activeDaysMax,
      modelUsage: models,
      hasLocalStats: true,
      hasPromptStats: true,
      syncEnabled: false,
      syncDeviceCount: 0
    }
  }

  readonly property var providers: {
    var real = usage.enabledProviders
    if (real.length === 0) return real
    return [overviewRecord(real)].concat(real)
  }
  // The selection follows the provider, not the slot it happens to sit in: a
  // provider whose first scan lands while the panel is open would otherwise
  // shift the list underneath you and swap out what you were reading.
  property string selectedProviderId: ""
  readonly property int providerIndex: {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].providerId === selectedProviderId) return i
    return 0
  }
  readonly property var provider: providers.length > 0 ? providers[providerIndex] : null

  property bool cursorActive: false

  // Countdowns and "updated" read this instead of Date.now() so the
  // panel keeps telling the truth while it sits open.
  property double nowMs: Date.now()

  readonly property var limits: limitWindows(provider)
  readonly property var models: modelRows(provider)
  readonly property var headline: bindingWindow(provider)
  readonly property var balance: provider ? (provider.balance || null) : null
  // A prepaid account runs low the way a subscription window fills up: the
  // last 10% of the funded credits lights the same alarm.
  readonly property bool balanceAlarming: !!balance && balance.funded > 0
    && balance.remaining / balance.funded <= 0.1
  readonly property bool alarming: (!!headline && headline.percent >= 0.9) || balanceAlarming

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function selectProvider(index) {
    if (providers.length === 0) return
    var wrapped = ((index % providers.length) + providers.length) % providers.length
    selectedProviderId = providers[wrapped].providerId
  }

  function refreshNow() {
    usage.refreshAll(true)
  }

  function launchAgent() {
    live.launchAgent()
    root.close()
  }

  // ---------------------------------------------------------------- limits
  //
  // Both providers report the same two shapes: a short rolling session window
  // and a long weekly one. Everything below normalizes them into one record so
  // the meters and the hero speak a single language.

  // Claude spells its windows out ("Session (5-hour)"), Codex abbreviates
  // them ("5h window", "30m window"). Both have to land on the same record.
  function windowIsLong(text) {
    return text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0
      || text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0
  }

  function windowSpanMs(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0) return 30 * 24 * 3600 * 1000
    if (windowIsLong(text)) return 7 * 24 * 3600 * 1000
    var hours = text.match(/(\d+)\s*-?\s*h(?:our)?\b/)
    if (hours) return Number(hours[1]) * 3600 * 1000
    var minutes = text.match(/(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b/)
    if (minutes) return Number(minutes[1]) * 60 * 1000
    return 0
  }

  function windowTitle(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0) return "Monthly"
    if (windowIsLong(text)) return "Weekly"
    if (text.indexOf("session") >= 0 || windowSpanMs(label) > 0) return "Session"
    var plain = String(label || "").replace(/\s*\(.*\)\s*/, "").trim()
    return plain === "" ? "Limit" : plain
  }

  // A collector that already knows which window a limit belongs to says so,
  // and that beats reading it back out of the label: a model-scoped limit is
  // titled after its model, and a name like "Opus 5 (1M context)" would parse
  // as a one-minute window.
  function limitWindow(label, percent, resetAt, title, detail) {
    return {
      title: String(title || "") !== "" ? String(title) : windowTitle(label),
      percent: Number(percent),
      resetAt: String(resetAt || ""),
      detail: String(detail || ""),
      spanMs: windowSpanMs(label)
    }
  }

  // Burn rate: assume the window keeps filling at the pace it has averaged
  // since it opened. Usage comes in bursts, so until a tenth of the window
  // has passed (30 minutes of a session, ~17 hours of a week) or while
  // nothing is used yet, say nothing rather than extrapolate noise.
  function forecast(w) {
    if (!w || !(w.spanMs > 0) || !(w.percent > 0)) return null
    var remaining = resetMsFor(w)
    var elapsed = w.spanMs - remaining
    if (!(remaining > 0) || elapsed < Math.max(600000, w.spanMs * 0.1)) return null
    var rate = w.percent / elapsed
    var projected = w.percent + rate * remaining
    if (projected >= 1)
      return { warn: true, text: "At this pace: limit in " + formatDuration((1 - w.percent) / rate) }
    return { warn: false, text: "On pace for ~" + Math.round(projected * 100) + "% by reset" }
  }

  function limitWindows(p) {
    if (!p) return []
    var out = []
    var list = p.limits || []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i] || {}
      var percent = Number(entry.percent)
      if (percent >= 0) out.push(limitWindow(entry.label, percent, entry.resetsAt, entry.title, entry.detail))
    }
    return out
  }

  // The window that decides how much room is left — the fullest one, since
  // that is what stops the next prompt.
  function bindingWindow(p) {
    var windows = limitWindows(p)
    var best = null
    for (var i = 0; i < windows.length; i++) {
      if (!best || windows[i].percent > best.percent) best = windows[i]
    }
    return best
  }

  function resetMsFor(w) {
    if (!w || w.resetAt === "") return -1
    var ms = new Date(w.resetAt).getTime()
    return isFinite(ms) ? ms - root.nowMs : -1
  }

  function formatDuration(ms) {
    if (!(ms > 0)) return "now"
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return days + "d " + (hours % 24) + "h"
    if (hours > 0) return hours + "h " + (minutes % 60) + "m"
    return Math.max(1, minutes) + "m"
  }

  // ---------------------------------------------------------------- balance
  //
  // Prepaid agents report a credit ledger instead of rate-limit windows: the
  // record's balance object carries remaining, funded, and spent amounts.

  function currencyPrefix(currency) {
    var code = String(currency || "USD").toUpperCase()
    if (code === "USD") return "$"
    if (code === "EUR") return "€"
    if (code === "GBP") return "£"
    return code + " "
  }

  function formatMoney(value, currency) {
    var amount = Number(value)
    if (!isFinite(amount)) amount = 0
    return currencyPrefix(currency) + amount.toFixed(2)
  }

  function balanceDetailText(b) {
    if (!b || !(b.funded > 0)) return ""
    var text = formatMoney(b.spent, b.currency) + " spent of " + formatMoney(b.funded, b.currency) + " funded"
    if (b.estimated) text += " · estimated"
    return text
  }

  // ---------------------------------------------------------------- content

  // Compact status line under the name: status dot + state, plus plan tier or
  // tagline for immediate context.
  function heroMeta(p) {
    if (!p) return ""
    var base = "\u25CF " + statusLabel
    var tier = String(p.tierLabel || "")
    if (tier !== "" && tier.toLowerCase() !== "local")
      return base + "  ·  " + tier.toUpperCase()
    if (p.tagline && String(p.tagline) !== "")
      return base + "  ·  " + String(p.tagline).toUpperCase()
    return base
  }

  function tabShortLabel(p) {
    if (!p) return ""
    var id = String(p.providerId || "")
    if (id === "__overview__") return "All"
    if (id === "claude") return "Claude"
    if (id === "openrouter") return "Router"
    if (id === "opencode") return "OpenCode"
    return String(p.providerName || id)
  }

  // Local calendar date, recomputed from nowMs so a panel left open across
  // midnight moves the "Today" row with the clock.
  function todayDate() {
    var now = new Date(root.nowMs)
    return now.getFullYear()
      + "-" + String(now.getMonth() + 1).padStart(2, "0")
      + "-" + String(now.getDate()).padStart(2, "0")
  }

  function dayName(date) {
    var parsed = new Date(String(date || "") + "T00:00:00")
    if (isNaN(parsed.getTime())) return String(date || "")
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parsed.getDay()]
  }

  function dayLabel(date, today) {
    if (today) return "Today"
    return dayName(date)
  }

  function dayTooltip(day, today) {
    if (!day) return ""
    var parsed = new Date(String(day.date) + "T00:00:00")
    var label = isNaN(parsed.getTime())
      ? String(day.date)
      : dayName(day.date) + " " + (parsed.getMonth() + 1) + "/" + parsed.getDate()
    var text = label + " · " + usage.formatTokenCount(Number(day.messageCount || 0)) + " tokens"
    // Prompt and session counts only exist for today, so they ride along here
    // instead of taking a section of their own. Billing-API agents never
    // count prompts, and "0 prompts" would read as a quiet day, not a gap.
    if (today && provider && provider.hasPromptStats !== false)
      text += " · " + Number(provider.todayPrompts || 0) + " prompts · "
        + Number(provider.todaySessions || 0) + " sessions"
    return text
  }

  function weekPeak(p) {
    var days = p ? (p.recentDays || []) : []
    var peak = 0
    for (var i = 0; i < days.length; i++) peak = Math.max(peak, Number(days[i].messageCount || 0))
    return peak
  }

  function modelRows(p) {
    var usageByModel = p ? (p.modelUsage || {}) : {}
    var merged = {}
    for (var id in usageByModel) {
      var normKey = usage.normalizeModelKey(id)
      var bucket = usageByModel[id] || {}
      var input = Number(bucket.inputTokens || 0)
      var output = Number(bucket.outputTokens || 0)
      var cacheRead = Number(bucket.cacheReadInputTokens || 0)
      var cacheWrite = Number(bucket.cacheCreationInputTokens || 0)
      var total = input + output + cacheRead + cacheWrite
      if (total <= 0) continue
      if (!merged[normKey]) {
        merged[normKey] = {
          name: usage.friendlyModelName(normKey),
          total: 0,
          input: 0,
          output: 0,
          cacheRead: 0,
          cacheWrite: 0
        }
      }
      merged[normKey].total += total
      merged[normKey].input += input
      merged[normKey].output += output
      merged[normKey].cacheRead += cacheRead
      merged[normKey].cacheWrite += cacheWrite
    }
    var rows = []
    for (var k in merged) rows.push(merged[k])
    rows.sort(function(a, b) { return b.total - a.total })
    return rows.slice(0, 4)
  }

  function modelTooltip(row) {
    if (!row) return ""
    return "In " + usage.formatTokenCount(row.input)
      + " · out " + usage.formatTokenCount(row.output)
      + " · cache read " + usage.formatTokenCount(row.cacheRead)
      + " · cache write " + usage.formatTokenCount(row.cacheWrite)
  }

  // Only speaks up when the numbers cover more than this machine.
  function footerText() {
    if (usage.syncStatusText !== "") return usage.syncStatusText
    if (provider && provider.syncEnabled && provider.syncDeviceCount > 0)
      return "Merged from " + provider.syncDeviceCount + " device" + (provider.syncDeviceCount === 1 ? "" : "s")
    return ""
  }

  // Agents that ship a white mark carry an `assets/<id>-light.svg` twin for
  // light surfaces; marks that work on both (Claude's brand-orange) ship one
  // file. The luminance check decides which candidate to try first.
  function colorChannelLuminance(value) {
    var channel = Number(value)
    if (!isFinite(channel)) return 0
    return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  }

  function colorLuminance(color) {
    return 0.2126 * colorChannelLuminance(color.r)
      + 0.7152 * colorChannelLuminance(color.g)
      + 0.0722 * colorChannelLuminance(color.b)
  }

  // Marks resolve by convention, so a new agent's data file needs nothing
  // from this panel: assets/<id>.svg if it ships one, the module's bar glyph
  // if it doesn't.
  function iconCandidatesForProvider(p, surfaceColor) {
    if (!p) return []
    var id = p.providerId === "__overview__" ? "overview" : p.providerId
    var candidates = []
    if (colorLuminance(surfaceColor || Color.background) >= 0.5)
      candidates.push(Qt.resolvedUrl("assets/" + id + "-light.svg"))
    candidates.push(Qt.resolvedUrl("assets/" + id + ".svg"))
    return candidates
  }

  // Nothing to report, nothing in the bar: Bar.qml collapses a slot whose item
  // is invisible, so the icon appears the moment the first scan finds usage and
  // stays away entirely on a machine that has never run either CLI.
  visible: providers.length > 0 || live.agents.length > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onProviderIndexChanged: if (panelFlick) panelFlick.contentY = 0
  onOpenedChanged: if (opened) {
    cursorActive = false
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    usage.refreshLimits()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Main {
    id: usage
    settings: root.settings
  }

  Live {
    id: live
    detailed: root.opened
  }

  // The bar meter tracks Claude's 5-hour session, the window that most often
  // stops a prompt. Limits-only refreshes are cheap, so keep it fresher than
  // the full 15-minute usage scan.
  readonly property var claudeSession: {
    var list = usage.enabledProviders
    for (var i = 0; i < list.length; i++) {
      if (list[i].providerId !== "claude") continue
      var windows = limitWindows(list[i])
      for (var j = 0; j < windows.length; j++)
        if (windows[j].title === "Session") return windows[j]
    }
    return null
  }
  readonly property bool agentNeedsYou: live.blockedCount > 0

  readonly property string liveHeaderText: {
    var parts = ["AGENTS"]
    if (live.blockedCount > 0) parts.push(live.blockedCount + " NEED YOU")
    if (live.workingCount > 0) parts.push(live.workingCount + " WORKING")
    if (parts.length === 1 && live.agents.length > 0) parts.push(live.agents.length + " IDLE")
    return parts.join("  ·  ")
  }

  function agentStatusText(status) {
    if (status === "blocked") return "needs you"
    if (status === "working") return "working"
    if (status === "idle") return "idle"
    return "starting"
  }

  function agentStatusColor(status) {
    if (status === "blocked") return root.urgent
    if (status === "working") return Color.accent
    return root.dim
  }

  function sinceText(sinceMs) {
    var ms = root.nowMs - Number(sinceMs || 0)
    if (!(ms > 0) || ms < 60000) return "just now"
    return formatDuration(ms)
  }

  readonly property var gatewayNames: ({
    "hermes-gateway": "Hermes",
    "openclaw-gateway": "OpenClaw",
    "paperclipai": "Paperclip"
  })

  Timer {
    interval: 300000
    running: true
    repeat: true
    onTriggered: usage.runUpdate("limits", ["claude"])
  }

  // Cheap enough to keep running: it only re-evaluates text bindings, and a
  // stale "resets in 2h" on a panel that is open is worse than a timer.
  // Agent rows count minutes, so tick a little faster than the limits need.
  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
    function next(): string { root.selectProvider(root.providerIndex + 1); return "ok" }
  }

  readonly property bool pillHasMark: !!root.provider
  readonly property string barMark: "\uDB81\uDF68" // U+F0768 nf-md-atom
  readonly property color barAccent: Color.accent

  Component {
    id: pillMarkComponent
    Item {
      property var candidates: root.iconCandidatesForProvider(root.provider, root.surface)
      property string candidatesKey: candidates.join("\n")
      property int candidateIndex: 0
      onCandidatesKeyChanged: candidateIndex = 0

      Image {
        id: pillMarkImage
        anchors.fill: parent
        source: candidateIndex < candidates.length ? candidates[candidateIndex] : ""
        sourceSize.width: Style.bar.iconCanvas * 2
        sourceSize.height: Style.bar.iconCanvas * 2
        fillMode: Image.PreserveAspectFit
        onStatusChanged: if (status === Image.Error && candidateIndex < candidates.length)
          Qt.callLater(function() { candidateIndex++ })
      }

      Text {
        anchors.centerIn: parent
        visible: pillMarkImage.status !== Image.Ready
        textFormat: Text.PlainText
        text: root.providerBarGlyph
        color: root.providerAccent
        font.family: root.fontFamily
        font.pixelSize: Style.bar.iconFont
      }
    }
  }

  function barPressed(buttonCode) {
    if (buttonCode === Qt.RightButton) root.launchAgent()
    else if (buttonCode === Qt.MiddleButton) root.selectProvider(root.providerIndex + 1)
    else root.toggle()
  }

  BarIconButton {
    id: button
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    bar: root.bar
    // michael: one fixed mark (nf-md-atom) in the theme accent,
    // instead of a glyph that changes with the selected provider tab.
    // The old per-tab version is pillMarkComponent / providerBarGlyph.
    iconComponent: null
    text: root.barMark
    active: root.alarming || root.agentNeedsYou
    foreground: root.barAccent
    tooltipText: root.agentNeedsYou
      ? live.blockedCount + (live.blockedCount === 1 ? " agent needs you" : " agents need you")
      : (root.claudeSession ? "Claude session " + Math.round(sessionRing.percent * 100) + "%" : "")

    onPressed: function(buttonCode) { root.barPressed(buttonCode) }

    // A blocked agent pulses the icon until you answer it.
    SequentialAnimation on opacity {
      running: root.agentNeedsYou
      loops: Animation.Infinite
      onRunningChanged: if (!running) button.opacity = 1
      NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
    }
  }

  // michael: Claude's 5-hour session as a ring around the icon. Provider
  // accent while under 90%, urgent past it; the exact figure is the tooltip.
  Canvas {
    id: sessionRing
    readonly property real percent: root.claudeSession ? root.clamp(root.claudeSession.percent, 0, 1) : 0
    readonly property color tint: percent >= 0.9 ? root.urgent : root.barAccent
    readonly property color track: root.foreground
    visible: !!root.claudeSession
    width: Style.bar.iconCanvas + 6
    height: width
    anchors.centerIn: button
    scale: button.pressScale
    onPercentChanged: requestPaint()
    onTintChanged: requestPaint()
    onTrackChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var lw = 2
      var c = width / 2
      var r = c - lw / 2
      ctx.lineWidth = lw
      ctx.lineCap = "round"
      ctx.strokeStyle = Qt.rgba(track.r, track.g, track.b, 0.18)
      ctx.beginPath()
      ctx.arc(c, c, r, 0, 2 * Math.PI)
      ctx.stroke()
      if (percent > 0) {
        ctx.strokeStyle = tint
        ctx.beginPath()
        ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.max(percent, 0.04))
        ctx.stroke()
      }
    }
  }

  // Old ▰▰▰▱▱ 58% meter, replaced by the ring above.
  Item {
    id: barMeter
    visible: false
    anchors.left: button.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    implicitWidth: meterRow.implicitWidth + Style.space(8)
    width: implicitWidth

    readonly property real percent: root.claudeSession ? root.clamp(root.claudeSession.percent, 0, 1) : 0
    readonly property int filled: percent > 0 ? Math.max(1, Math.round(percent * 5)) : 0
    readonly property color tint: percent >= 0.9 ? root.urgent : root.foreground

    Row {
      id: meterRow
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(5)

      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Repeater {
          model: 5
          Rectangle {
            required property int index
            width: Style.space(4)
            height: Style.space(10)
            radius: Style.space(1)
            color: index < barMeter.filled ? barMeter.tint : root.alpha(root.foreground, 0.22)
          }
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: Math.round(barMeter.percent * 100) + "%"
        color: barMeter.tint
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: barMeter.percent >= 0.9
      }
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      cursorShape: Qt.PointingHandCursor
      onPressed: function(mouse) { root.barPressed(mouse.button) }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(660))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dx !== 0) {
          root.cursorActive = true
          root.selectProvider(root.providerIndex + dx)
        }
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refreshNow() }

      // Subtle top ambient wash anchored behind the Flickable so it never
      // occupies vertical layout space inside the Column.
      Rectangle {
        id: panelBackground
        z: -10
        visible: !!root.provider
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(120)
        radius: Style.cornerRadius

        gradient: Gradient {
          orientation: Gradient.Vertical
          GradientStop {
            position: 0
            color: Qt.rgba(root.providerAccent.r, root.providerAccent.g, root.providerAccent.b, 0.16)
          }
          GradientStop {
            position: 0.55
            color: Qt.rgba(root.providerAccent.r, root.providerAccent.g, root.providerAccent.b, 0.04)
          }
          GradientStop {
            position: 1
            color: "transparent"
          }
        }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ---------- Live agents (herdr) ----------
          Column {
            id: liveSection
            width: parent.width
            spacing: Style.space(6)

            Item {
              width: parent.width
              implicitHeight: Math.max(liveHeader.implicitHeight, newAgentBtn.height)

              PanelSectionHeader {
                id: liveHeader
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.liveHeaderText
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Rectangle {
                id: newAgentBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: newAgentLabel.implicitWidth + Style.space(16)
                height: Style.space(26)
                radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, Style.space(7)) : 0
                color: newAgentMouse.pressed
                  ? root.alpha(root.providerAccent, 0.22)
                  : newAgentMouse.containsMouse ? root.alpha(root.foreground, 0.08) : root.alpha(root.foreground, 0.04)
                border.color: root.alpha(root.foreground, newAgentMouse.containsMouse ? 0.18 : 0.09)
                border.width: 1

                Text {
                  id: newAgentLabel
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: "+  New agent"
                  color: newAgentMouse.containsMouse ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                MouseArea {
                  id: newAgentMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.launchAgent()
                }

                PanelToolTip {
                  visible: newAgentMouse.containsMouse
                  text: "Pick a project and agent (or right-click the bar icon)"
                  fontFamily: root.fontFamily
                }
              }
            }

            Text {
              visible: live.agents.length === 0
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              text: live.herdrAvailable
                ? "No agents running in herdr."
                : "herdr isn't running — start one with New agent."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: live.agents

              LiveAgentRow {
                required property var modelData
                width: liveSection.width
                agentData: modelData
              }
            }
          }

          PanelSeparator {
            visible: live.gateways.length > 0
            foreground: root.foreground
          }

          // ---------- Gateways (systemd user services) ----------
          Column {
            id: gatewaySection
            visible: live.gateways.length > 0
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader {
              text: "GATEWAYS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: live.gateways

              GatewayRow {
                required property var modelData
                width: gatewaySection.width
                gateway: modelData
              }
            }
          }

          PanelSeparator {
            visible: root.providers.length > 0
            foreground: root.foreground
          }

          // ---------- Provider switch (top segmented dock) ----------
          Rectangle {
            id: tabStripTrack
            visible: root.providers.length > 1
            width: parent.width
            implicitHeight: Style.space(48)
            radius: Style.cornerRadius
            color: root.alpha(root.foreground, 0.04)
            border.color: root.alpha(root.foreground, 0.09)
            border.width: 1

            Row {
              id: providerSwitch
              anchors.fill: parent
              anchors.margins: Style.space(3)
              spacing: Style.space(3)

              readonly property real cellWidth: root.providers.length > 0
                ? (width - spacing * (root.providers.length - 1)) / root.providers.length
                : 0

              Repeater {
                model: root.providers

                ProviderTab {
                  required property var modelData
                  required property int index

                  width: providerSwitch.cellWidth
                  height: providerSwitch.height
                  providerData: modelData
                  selected: index === root.providerIndex
                  hasCursor: root.cursorActive && index === root.providerIndex
                  onClicked: {
                    root.cursorActive = true
                    root.selectProvider(index)
                  }
                  onHoveredChanged: if (hovered) root.cursorActive = true
                }
              }
            }
          }

          // ---------- Hero: provider mark · name · status + tier ----------
          Item {
            visible: !!root.provider
            width: parent.width
            implicitHeight: Math.max(heroMark.height, heroTextCol.implicitHeight)

            Item {
              id: heroMark
              property var candidates: root.iconCandidatesForProvider(root.provider, root.surface)
              property string candidatesKey: candidates.join("\n")
              property int candidateIndex: 0
              onCandidatesKeyChanged: candidateIndex = 0

              width: Style.space(32)
              height: Style.space(32)
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter

              Rectangle {
                anchors.fill: parent
                radius: Style.space(8)
                color: root.alpha(root.providerAccent, 0.12)
                border.color: root.alpha(root.providerAccent, 0.28)
                border.width: 1
              }

              Image {
                id: heroMarkImage
                anchors.centerIn: parent
                width: Style.space(20)
                height: Style.space(20)
                source: heroMark.candidateIndex < heroMark.candidates.length ? heroMark.candidates[heroMark.candidateIndex] : ""
                sourceSize.width: Style.space(40)
                sourceSize.height: Style.space(40)
                fillMode: Image.PreserveAspectFit
                onStatusChanged: if (status === Image.Error && heroMark.candidateIndex < heroMark.candidates.length)
                  Qt.callLater(function() { heroMark.candidateIndex++ })
              }

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                visible: heroMarkImage.status !== Image.Ready
                text: root.providerBarGlyph
                color: root.providerAccent
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
              }
            }

            Column {
              id: heroTextCol
              anchors.left: heroMark.right
              anchors.leftMargin: Style.space(12)
              anchors.right: refreshBtn.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: root.provider ? root.provider.providerName : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
                elide: Text.ElideRight
              }

              Row {
                spacing: Style.space(6)

                Rectangle {
                  width: Style.space(6)
                  height: Style.space(6)
                  radius: width / 2
                  color: root.statusColor
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: {
                    if (!root.provider) return ""
                    var s = root.statusLabel
                    var tier = String(root.provider.tierLabel || "")
                    if (tier !== "" && tier.toLowerCase() !== "local")
                      return s + "  ·  " + tier.toUpperCase()
                    var tag = String(root.provider.tagline || "")
                    if (tag !== "") return s + "  ·  " + tag
                    return s
                  }
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 0.6
                }
              }
            }

            Rectangle {
              id: refreshBtn
              width: Style.space(28)
              height: Style.space(28)
              radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, Style.space(7)) : 0
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              color: refreshMouse.pressed
                ? root.alpha(root.providerAccent, 0.22)
                : refreshMouse.containsMouse
                  ? root.alpha(root.foreground, 0.08)
                  : "transparent"
              border.color: refreshMouse.containsMouse ? root.alpha(root.foreground, 0.18) : "transparent"
              border.width: 1

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "󰑐"
                color: refreshMouse.containsMouse ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }

              MouseArea {
                id: refreshMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.refreshNow()
              }

              PanelToolTip {
                visible: refreshMouse.containsMouse
                text: "Refresh usage (r)"
                fontFamily: root.fontFamily
              }
            }
          }

          // ---------- Primary metric card ----------
          Rectangle {
            visible: !!root.provider
            width: parent.width
            implicitHeight: todayBlock.implicitHeight + Style.space(20)
            radius: Style.cornerRadius
            color: root.alpha(root.providerAccent, 0.06)
            border.color: root.alpha(root.providerAccent, 0.20)
            border.width: 1

            Column {
              id: todayBlock
              anchors.centerIn: parent
              width: parent.width - Style.space(24)
              spacing: Style.space(2)

              Text {
                id: todayAmount
                textFormat: Text.PlainText
                text: root.heroPrimaryText
                color: root.alarming ? root.urgent : root.providerAccent
                font.family: root.fontFamily
                font.pixelSize: 36
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                anchors.horizontalCenter: parent.horizontalCenter
              }

              Text {
                textFormat: Text.PlainText
                text: root.heroPrimarySubtext
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                horizontalAlignment: Text.AlignHCenter
                anchors.horizontalCenter: parent.horizontalCenter
              }
            }
          }

          // ---------- Stat chips: 7-day · all-time · sessions ----------
          Row {
            id: chipRow
            visible: !!root.provider
            width: parent.width
            spacing: Style.spacing.md

            readonly property real cellWidth: root.provider
              ? (width - spacing * 2) / 3
              : 0

            StatChip {
              width: chipRow.cellWidth
              label: root.chip1Label
              value: root.chip1Value
            }
            StatChip {
              width: chipRow.cellWidth
              label: root.chip2Label
              value: root.chip2Value
            }
            StatChip {
              width: chipRow.cellWidth
              label: root.chip3Label
              value: root.chip3Value
            }
          }

          Text {
            visible: root.providers.length === 0
            width: parent.width
            topPadding: Style.space(24)
            text: "No AI coding subscriptions found.\nAgents show up here once you've used them."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          // ---------- Status (only when an explicit auth/endpoint error exists) ----------
          BorderSurface {
            visible: !!root.provider && !root.hasCostBreakdown
              && String(root.provider.usageStatusText || "") !== ""
              && String(root.provider.usageStatusText || "") !== "Spend"
              && String(root.provider.usageStatusText || "") !== "Quiet today"
              && String(root.provider.usageStatusText || "") !== "Active"
              && String(root.provider.usageStatusText || "") !== "Today's run"
            width: parent.width
            implicitHeight: statusText.implicitHeight + Style.spacing.xl * 2
            color: root.alpha(root.urgent, 0.10)
            borderSpec: Border.flat(root.alpha(root.urgent, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              id: statusText
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: root.provider ? String(root.provider.authHelpText || "") : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ---------- Balance / limits ----------
          PanelSeparator {
            visible: balanceSection.visible || limitsSection.visible
            foreground: root.foreground
          }

          Column {
            id: balanceSection
            visible: !!root.balance
            width: parent.width
            spacing: Style.space(8)

            readonly property real ratio: root.balance && root.balance.funded > 0
              ? root.clamp(root.balance.remaining / root.balance.funded, 0, 1)
              : -1

            PanelSectionHeader {
              width: parent.width
              text: "PREPAID BALANCE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(balanceLabel.implicitHeight, balanceValue.implicitHeight)

              Text {
                id: balanceLabel
                textFormat: Text.PlainText
                text: root.balanceDetailText(root.balance) || "Remaining credit"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: balanceValue
                textFormat: Text.PlainText
                text: root.balance ? root.formatMoney(root.balance.remaining, root.balance.currency) + " left" : ""
                color: root.balanceAlarming ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Meter {
              visible: balanceSection.ratio >= 0
              width: parent.width
              value: balanceSection.ratio
              alarming: root.balanceAlarming
              fillColor: root.providerAccent
            }
          }

          Column {
            id: limitsSection
            visible: root.limits.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: root.provider && root.provider.providerId === "openrouter" ? "KEY BUDGETS" : "RATE LIMITS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.limits

              LimitRow {
                required property var modelData
                width: limitsSection.width
                window: modelData
              }
            }
          }

          // ---------- Usage ----------
          PanelSeparator {
            visible: usageSection.visible
            foreground: root.foreground
          }

          Column {
            id: usageSection
            visible: !!root.provider && (root.provider.hasLocalStats !== false || (root.provider.recentDays && root.provider.recentDays.length > 0))
            width: parent.width
            spacing: Style.spacing.md

            readonly property var days: root.provider ? (root.provider.recentDays || []) : []
            readonly property real peak: Math.max(1, root.weekPeak(root.provider))
            readonly property bool hasActivity: days.length > 0 && root.weekPeak(root.provider) > 0

            Item {
              width: parent.width
              implicitHeight: usageHeader.implicitHeight

              PanelSectionHeader {
                id: usageHeader
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "LAST 7 DAYS"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Text {
                visible: usageSection.hasActivity
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: usage.formatTokenCount(root.weekTokens) + " tokens"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Rectangle {
              visible: !usageSection.hasActivity
              width: parent.width
              implicitHeight: Style.space(38)
              radius: Style.cornerRadius
              color: root.alpha(root.foreground, 0.03)
              border.color: root.alpha(root.foreground, 0.07)
              border.width: 1

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "No recorded token activity in the last 7 days"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Row {
              id: dayHistogram
              visible: usageSection.hasActivity
              width: parent.width
              height: Style.space(78)
              spacing: Style.space(6)

              Repeater {
                model: usageSection.days

                Item {
                  required property var modelData
                  required property int index

                  width: usageSection.days.length > 0
                    ? (dayHistogram.width - dayHistogram.spacing * (usageSection.days.length - 1)) / usageSection.days.length
                    : 0
                  height: dayHistogram.height

                  readonly property var day: modelData
                  readonly property real dayTokens: Number(modelData.messageCount || 0)
                  readonly property real ratio: dayTokens / usageSection.peak
                  readonly property bool today: String(modelData.date || "") === root.todayDate()

                  Column {
                    anchors.fill: parent
                    spacing: Style.space(4)

                    Text {
                      id: barTopValue
                      width: parent.width
                      textFormat: Text.PlainText
                      text: dayTokens > 0 ? usage.formatTokenCount(dayTokens) : ""
                      color: today ? root.foreground : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Math.max(9, Style.font.caption - 1)
                      font.bold: today
                      horizontalAlignment: Text.AlignHCenter
                      elide: Text.ElideRight
                    }

                    Item {
                      width: parent.width
                      height: parent.height - dayLabel.implicitHeight - barTopValue.implicitHeight - parent.spacing * 2

                      Rectangle {
                        anchors.fill: parent
                        radius: Style.space(3)
                        color: root.alpha(root.foreground, 0.04)
                      }

                      Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: dayTokens > 0
                          ? Math.max(Style.space(4), parent.height * root.clamp(ratio, 0, 1))
                          : Style.space(2)
                        radius: Style.space(3)
                        color: dayTokens === 0
                          ? root.alpha(root.foreground, 0.12)
                          : today
                            ? root.providerAccent
                            : root.alpha(root.providerAccent, 0.62)

                        Behavior on height {
                          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                        }
                      }
                    }

                    Text {
                      id: dayLabel
                      textFormat: Text.PlainText
                      text: root.dayLabel(day ? day.date : "", today)
                      color: today ? root.foreground : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: today
                      horizontalAlignment: Text.AlignHCenter
                      width: parent.width
                    }
                  }

                  MouseArea {
                    id: dayHover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                  }

                  PanelToolTip {
                    visible: dayHover.containsMouse
                    text: root.dayTooltip(day, today)
                    fontFamily: root.fontFamily
                  }
                }
              }
            }
          }

          // ---------- Models ----------
          PanelSeparator {
            visible: modelSection.visible
            foreground: root.foreground
          }

          Column {
            id: modelSection
            visible: root.models.length > 0 && modelTotal() > 0
            width: parent.width
            spacing: Style.spacing.md

            readonly property real total: modelTotal()

            function modelTotal() {
              var sum = 0
              for (var i = 0; i < root.models.length; i++) sum += root.models[i].total
              return sum
            }

            function segmentColor(index) {
              var palette = [
                root.providerAccent,
                Qt.lighter(root.providerAccent, 1.35),
                root.alpha(root.providerAccent, 0.58),
                root.alpha(root.foreground, 0.38)
              ]
              return palette[index % palette.length]
            }

            Item {
              width: parent.width
              implicitHeight: modelHeader.implicitHeight

              PanelSectionHeader {
                id: modelHeader
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "TOP MODELS"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: usage.formatTokenCount(modelSection.total) + " total"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            // Proportional stacked bar across top models
            Rectangle {
              width: parent.width
              implicitHeight: Style.space(8)
              radius: height / 2
              color: root.track
              clip: true

              Row {
                anchors.fill: parent
                spacing: 1

                Repeater {
                  model: root.models

                  Rectangle {
                    required property var modelData
                    required property int index

                    height: parent.height
                    width: modelSection.total > 0
                      ? Math.max(2, (modelSection.width - (root.models.length - 1)) * (modelData.total / modelSection.total))
                      : 0
                    color: modelSection.segmentColor(index)

                    Behavior on width {
                      NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }
                  }
                }
              }
            }

            // Clean structured model rows with share bar, color dot, name, and token count
            Column {
              width: parent.width
              spacing: Style.space(5)

              Repeater {
                model: root.models

                Item {
                  required property var modelData
                  required property int index

                  width: modelSection.width
                  implicitHeight: Style.space(26)

                  readonly property real share: root.models[0].total > 0
                    ? modelData.total / root.models[0].total
                    : 0
                  readonly property int pct: modelSection.total > 0
                    ? Math.round((modelData.total / modelSection.total) * 100)
                    : 0

                  Rectangle {
                    anchors.fill: parent
                    radius: Style.space(6)
                    color: modelRowHover.containsMouse
                      ? root.alpha(root.foreground, 0.08)
                      : root.alpha(root.foreground, 0.035)
                  }

                  Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * root.clamp(parent.share, 0, 1)
                    radius: Style.space(6)
                    color: root.alpha(modelSection.segmentColor(index), 0.14)

                    Behavior on width {
                      NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }
                  }

                  Rectangle {
                    id: rowDot
                    width: Style.space(7)
                    height: Style.space(7)
                    radius: width / 2
                    color: modelSection.segmentColor(index)
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(9)
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    id: rowModelName
                    textFormat: Text.PlainText
                    text: modelData.name
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                    anchors.left: rowDot.right
                    anchors.leftMargin: Style.space(8)
                    anchors.right: rowModelTokens.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    id: rowModelTokens
                    textFormat: Text.PlainText
                    text: usage.formatTokenCount(modelData.total) + "  (" + parent.pct + "%)"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(9)
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  MouseArea {
                    id: modelRowHover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                  }

                  PanelToolTip {
                    visible: modelRowHover.containsMouse
                    text: root.modelTooltip(modelData)
                    fontFamily: root.fontFamily
                  }
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            topPadding: Style.space(2)
            text: root.footerText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // Compact icon + short-label tab button for the top segmented switch bar.
  component ProviderTab: Item {
    id: tabItem
    property var providerData: null
    property bool selected: false
    property bool hasCursor: false
    readonly property bool hovered: tabMouse.containsMouse

    readonly property color tabAccent: {
      if (!providerData || !providerData.color) return Color.accent
      var c = Qt.color(providerData.color)
      return c.a === 0 ? Color.accent : c
    }

    signal clicked()

    property var candidates: root.iconCandidatesForProvider(providerData, root.surface)
    property string candidatesKey: candidates.join("\n")
    property int candidateIndex: 0
    onCandidatesKeyChanged: candidateIndex = 0

    Rectangle {
      anchors.fill: parent
      radius: Math.max(Style.space(4), Style.cornerRadius - Style.space(3))
      color: tabMouse.pressed
        ? root.alpha(tabItem.tabAccent, 0.28)
        : tabItem.selected
          ? root.alpha(tabItem.tabAccent, 0.18)
          : (tabItem.hovered || tabItem.hasCursor)
            ? root.alpha(root.foreground, 0.08)
            : "transparent"
      border.color: tabItem.selected
        ? root.alpha(tabItem.tabAccent, 0.75)
        : (tabItem.hovered || tabItem.hasCursor)
          ? root.alpha(root.foreground, 0.22)
          : "transparent"
      border.width: 1

      Behavior on color { ColorAnimation { duration: 120 } }
    }

    Column {
      anchors.centerIn: parent
      width: parent.width - Style.space(4)
      spacing: Style.space(2)

      Item {
        width: Style.space(16)
        height: Style.space(16)
        anchors.horizontalCenter: parent.horizontalCenter

        Image {
          id: tabIconImg
          anchors.fill: parent
          source: tabItem.candidateIndex < tabItem.candidates.length ? tabItem.candidates[tabItem.candidateIndex] : ""
          sourceSize.width: Style.space(32)
          sourceSize.height: Style.space(32)
          fillMode: Image.PreserveAspectFit
          opacity: tabItem.selected || tabItem.hovered ? 1.0 : 0.75
          onStatusChanged: if (status === Image.Error && tabItem.candidateIndex < tabItem.candidates.length)
            Qt.callLater(function() { tabItem.candidateIndex++ })
        }

        Text {
          anchors.centerIn: parent
          visible: tabIconImg.status !== Image.Ready
          textFormat: Text.PlainText
          text: tabItem.providerData && tabItem.providerData.barGlyph ? tabItem.providerData.barGlyph : root.defaultBarGlyph
          color: tabItem.selected ? tabItem.tabAccent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.iconSmall
        }
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.tabShortLabel(tabItem.providerData)
        color: tabItem.selected ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Math.max(9, Style.font.caption - 1)
        font.bold: tabItem.selected
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }
    }

    MouseArea {
      id: tabMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tabItem.clicked()
    }
  }

  // One labeled value chip for the hero stat row.
  component StatChip: Item {
    id: chip
    property string label: ""
    property string value: ""

    implicitHeight: chipColumn.implicitHeight + Style.space(18)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.04)
      border.color: root.alpha(root.foreground, 0.10)
      border.width: 1
    }

    Column {
      id: chipColumn
      anchors.centerIn: parent
      spacing: Style.space(2)
      width: parent.width - Style.space(16)

      Text {
        textFormat: Text.PlainText
        text: chip.label
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Math.max(9, Style.font.caption - 1)
        font.bold: true
        font.letterSpacing: 0.5
        width: parent.width
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        text: chip.value
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        width: parent.width
        elide: Text.ElideRight
      }
    }
  }

  // One running herdr agent: status dot, mark, project, state and how long it
  // has been in it. Clicking jumps to its pane.
  component LiveAgentRow: Rectangle {
    id: agentRow
    property var agentData: ({})

    readonly property string status: String(agentData.status || "")
    readonly property color statusColor: root.agentStatusColor(status)

    implicitHeight: Style.space(40)
    radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, Style.space(7)) : 0
    color: agentMouse.containsMouse
      ? root.alpha(root.foreground, 0.08)
      : status === "blocked" ? root.alpha(root.urgent, 0.10) : root.alpha(root.foreground, 0.03)
    border.color: status === "blocked" ? root.alpha(root.urgent, 0.45) : root.alpha(root.foreground, 0.07)
    border.width: 1

    Rectangle {
      id: agentDot
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(7)
      height: width
      radius: width / 2
      color: agentRow.statusColor

      SequentialAnimation on opacity {
        running: agentRow.status === "working" || agentRow.status === "blocked"
        loops: Animation.Infinite
        onRunningChanged: if (!running) agentDot.opacity = 1
        NumberAnimation { to: 0.3; duration: 800; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 800; easing.type: Easing.InOutSine }
      }
    }

    Image {
      id: agentMark
      anchors.left: agentDot.right
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(18)
      height: width
      source: Qt.resolvedUrl("assets/" + String(agentRow.agentData.agent || "") + ".svg")
      sourceSize.width: width * 2
      sourceSize.height: height * 2
      fillMode: Image.PreserveAspectFit
    }

    Text {
      anchors.centerIn: agentMark
      visible: agentMark.status !== Image.Ready
      textFormat: Text.PlainText
      text: "󰚩"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.icon
    }

    Column {
      anchors.left: agentMark.right
      anchors.leftMargin: Style.space(10)
      anchors.right: agentState.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: String(agentRow.agentData.project || "")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: String(agentRow.agentData.agent || "")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    Column {
      id: agentState
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      Text {
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: root.agentStatusText(agentRow.status)
        color: agentRow.statusColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Text {
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: root.sinceText(agentRow.agentData.sinceMs)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      id: agentMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        live.focusAgent(String(agentRow.agentData.paneId || ""))
        root.close()
      }
    }

    PanelToolTip {
      visible: agentMouse.containsMouse
      text: "Jump to " + String(agentRow.agentData.cwd || "").replace(/^\/home\/[^/]+/, "~")
      fontFamily: root.fontFamily
    }
  }

  // One gateway service: up/down, memory, autostart, and start/stop/restart.
  component GatewayRow: Item {
    id: gatewayRow
    property var gateway: ({})

    readonly property bool running: gateway.active === true
    readonly property string unit: String(gateway.unit || "")

    implicitHeight: Style.space(30)

    Rectangle {
      id: gatewayDot
      anchors.left: parent.left
      anchors.leftMargin: Style.space(2)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(7)
      height: width
      radius: width / 2
      color: gatewayRow.running ? Color.accent : "transparent"
      border.color: gatewayRow.running ? Color.accent : root.dim
      border.width: 1
    }

    Text {
      id: gatewayName
      anchors.left: gatewayDot.right
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.gatewayNames[gatewayRow.unit] || gatewayRow.unit
      color: gatewayRow.running ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    Text {
      anchors.left: gatewayName.right
      anchors.leftMargin: Style.space(8)
      anchors.right: gatewayActions.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: {
        var parts = [gatewayRow.running ? Number(gatewayRow.gateway.memoryMB || 0) + " MB" : String(gatewayRow.gateway.state || "stopped")]
        parts.push(gatewayRow.gateway.autostart === true ? "starts at login" : "manual")
        return parts.join("  ·  ")
      }
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Row {
      id: gatewayActions
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      PanelActionButton {
        visible: gatewayRow.running
        iconText: "󰑐"
        tooltipText: "Restart"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: live.gatewayCommand("restart", gatewayRow.unit)
      }

      PanelActionButton {
        iconText: gatewayRow.running ? "󰓛" : "󰐊"
        tooltipText: gatewayRow.running ? "Stop" : "Start"
        foreground: root.foreground
        hoverColor: gatewayRow.running ? root.urgent : root.foreground
        fontFamily: root.fontFamily
        onClicked: live.gatewayCommand(gatewayRow.running ? "stop" : "start", gatewayRow.unit)
      }
    }
  }

  // A limit window: label and percentage, meter, and reset countdown.
  component LimitRow: Column {
    id: limitRow
    property var window: null

    readonly property bool alarming: window && window.percent >= 0.9

    spacing: Style.space(5)

    Item {
      width: parent.width
      implicitHeight: Math.max(limitLabel.implicitHeight, limitValue.implicitHeight)

      Text {
        id: limitLabel
        textFormat: Text.PlainText
        text: limitRow.window ? limitRow.window.title : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.right: limitMetaRight.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
      }

      Row {
        id: limitMetaRight
        spacing: Style.space(8)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        Text {
          textFormat: Text.PlainText
          visible: text !== ""
          text: {
            if (limitRow.window && limitRow.window.detail) return limitRow.window.detail
            var remainingMs = root.resetMsFor(limitRow.window)
            return remainingMs > 0 ? "resets in " + root.formatDuration(remainingMs) : ""
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          id: limitValue
          textFormat: Text.PlainText
          text: limitRow.window && limitRow.window.percent >= 0
            ? Math.round(limitRow.window.percent * 100) + "%"
            : "—"
          color: limitRow.alarming ? root.urgent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }

    Meter {
      width: parent.width
      value: limitRow.window ? limitRow.window.percent : -1
      alarming: limitRow.alarming
      fillColor: root.providerAccent
    }

    Text {
      readonly property var pace: root.forecast(limitRow.window)
      visible: !!pace
      width: parent.width
      textFormat: Text.PlainText
      text: pace ? pace.text : ""
      color: pace && pace.warn ? root.urgent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  // Rounded track showing the percentage of the allowance used.
  component Meter: Item {
    id: meter
    property real value: -1
    property bool alarming: false
    property color fillColor: root.providerAccent
    property real thickness: Math.max(Style.space(6), Math.round(Style.spacing.controlHeight * 0.20))

    implicitHeight: thickness

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meter.value > 0
        ? Math.max(meterTrack.height, meterTrack.width * root.clamp(meter.value, 0, 1))
        : 0
      color: meter.alarming ? root.urgent : meter.fillColor

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }
  }
}
