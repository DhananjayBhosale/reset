# Changelog

The latest release is on the [Releases page](https://github.com/msfbeast/reset/releases/latest). Older builds are kept but not listed; this file is the history.

## 0.3.14 — each account's own plan

- A plan price per Claude account: the value multiple compares Team's usage with Team's price and Pro's with Pro's, and All adds them up. A price set before stays with the account Claude Code is signed in to.
- A used-up weekly limit (read from the Claude desktop app) shows until the latest it can lift, worked out from when it last reset, instead of a note beside "ready".
- The dashboard's Providers list shows a second Claude account, and its small arcs no longer draw as a blob.
- The unit tests run on GitHub for every push and pull request.

## 0.3.13 — the menu bar follows the account you're using

- With two Claude accounts, the menu bar showed a green "Pro ready" just because the second account was unused, hiding the signed-in account's countdown, what's left and the run-out warning. While that account's window runs, the menu bar now shows only it.

## 0.3.12 — costs per account

- With more than one Claude account, the dashboard has an All / Team / Pro switch: costs, sessions, projects, this week's windows, the heatmap and the share card for just that account.
- Snapshot tests draw the dashboard, the menu bar pill and every widget look and compare them with reference images, so layout slips like the arc running through the countdown fail the tests.

## 0.3.11 — two accounts, and VoiceOver

- Separate Claude accounts get separate entries: for example "Claude · Team" (the account the Claude Code CLI is signed in to, with live usage, the forecast and auto-start) and "Claude · Pro", each with its own window from its own sessions, plus the Claude desktop app's readings for the second one, including a weekly limit.
- VoiceOver: the menu bar pill speaks ("Claude: 2 hours 46 minutes until the reset, 42 percent left"), dashboard switches say whether they're on, and charts and bars are described or skipped.
- Every "slow down" from Anthropic is logged, to check whether 2-minute polling ever trips the limit.

## 0.3.10 — gentler on Anthropic's limits

- Live usage remembers when Anthropic asks it to slow down, across restarts and app updates, instead of asking again straight away. After a restart, the last reading shows immediately if it's recent.
- While you're using Claude Code, live usage now updates every 2 minutes (every 5 when idle). Once a minute could trip Anthropic's rate limit.

## 0.3.9 — fresher, steadier

- Live usage updates more often while you're using Claude Code and every 5 minutes when idle: fresher numbers when they move, fewer requests overall. (Every minute at first; 0.3.10 makes it every 2.)
- When you're running out, the red pill shows what's left and when it runs out ("86% · out 9:29") instead of a countdown that read like a second clock time.
- Auto-start and Start now wait for a working network instead of timing out offline and using up their tries.
- Antigravity's last reading stays visible while the app is closed, labelled with when it was seen.

## 0.3.8 — your window at a glance

- A colored pill in the menu bar: orange "2:46 · 42%" as usual, red when the window is nearly empty or your pace runs out before the reset ("38% · out 10:07"), green "ready" when a fresh window is waiting, a warning sign while Claude Code is signed out, and a moon with the time a weekly limit lifts. Settings → Appearance switches back to plain text.
- The run-out warning survives restarts, and a window you've already been warned about doesn't warn again.

## 0.3.7 — clearer Settings, honest estimates

- Settings in four tabs: General, Automation, Appearance, Advanced. Live usage sits at the top.
- When Reset is guessing, it says so and why ("estimated · live usage off"). Without a usage reading, cards say "~70% of time left" instead of passing the clock off as usage.
- Report a problem: a GitHub issue pre-filled with versions and on/off states, never usage numbers, paths, project names or your phone topic.
- The dashboard's window arc no longer runs through the countdown on narrow windows.

## 0.3.6 — Start now

- A Start now button in the countdown and Fuse widgets when a fresh window is waiting.

## 0.3.5 — the Fuse

- Fuse widget: your window as a burning fuse, with where today's pace runs out and how much to slow down to make the reset.
- Auto-start keeps the Mac awake for the few seconds a run takes, so a run started while the Mac sleeps on battery finishes on time.

## 0.3.4 — fewer, better widgets

- Seven polished widgets instead of 22. Arrival and Game Boy read properly when a fresh window is waiting.

## 0.3.3

- Auto-start keeps a retry in progress, or a start waiting on a sign-in, across a restart.
- A way to preview the log-format warning without breaking anything.

## 0.3.2 — auto-start tells you when it fails

- Every auto-start run gets a clear result (started, signed out, limit not reset yet, timed out, or failed with a reason), saved so an overnight failure is still visible in the morning.
- Signed out: one notification, a banner with Fix, and the waiting window starts right after you sign in.

## 0.3.1

- A warning when Claude Code changes how it writes its logs, instead of quietly undercounting.
- Pacing budgets show in the terminal status line and the menu.
- Release builds are stripped: smaller, and without the build machine's folder paths.

## 0.3 — pacing budgets

- The MCP server gains `set_budget` and `clear_budget`: give a task a cap and an optional model to switch to; `get_claude_usage` then says when to wrap up and when to downshift. Shown on the dashboard with a Clear button.
- Mac notifications fire at the actual reset time; dashboard switches work; widgets stay current.
- A format-drift check with anonymised samples of every log format Reset reads.
- Fixes: mascot panels no longer pile up in memory, a future-dated transcript row can't crash the app, tool counts no longer inflate on re-reads, a stale weekly limit clears from live data.

## 0.2 — one-minute setup

- First-run setup: pick your tools, sign Claude Code in, set up phone alerts with a QR code, add your plan price.
- Redesigned menu; sign-in warnings with a one-click fix; Stay awake; much faster scanning; update checks.

## 0.1 — first public release

- Menu bar countdown to your next Claude window, live or estimated.
- Phone alerts through ntfy that arrive while your Mac sleeps.
- Limit forecast and optional auto-start of the next window.
- Dashboard: value vs plan, cache savings, windows, token mix, sessions and projects.
- Widgets, looks, animated mascots (unofficial fan art), a share card for X.
- Claude Code status line and MCP server.
