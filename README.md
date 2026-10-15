<p align="center"><img src="docs/icon.png" width="128" alt="Reset icon"></p>

<h1 align="center">Reset</h1>

<p align="center">Know exactly when your AI usage window resets, get pinged on your phone when it does, and see what your usage is actually worth.</p>

<p align="center"><img src="docs/share-card.png" width="720" alt="Reset share card"></p>

Reset is a free, open source macOS app for people who live inside Claude Code (with Codex, Gemini CLI and Antigravity support too). It sits in your menu bar, counts down to your next fresh window, and turns your local usage logs into a dashboard, desktop widgets and a card you can post.

Everything it reads stays on your Mac.

## What it does

- **Countdown to your next window.** A menu bar timer for Claude's 5-hour session window, exact when live usage is on and estimated from your activity when it isn't.
- **Phone alerts while your Mac sleeps.** Reset queues each reset alert on an [ntfy](https://ntfy.sh) server ahead of time, so it arrives on your phone even with the lid closed.
- **Limit forecast.** At your current pace, will you hit the limit before the reset? Reset warns you once per window, on your Mac and your phone.
- **Auto-start.** Optional. When a window runs out, Reset sends a one-word prompt so the next window starts right away instead of when you wake up.
- **Dashboard.** API-price value of your usage against your plan, cache savings, every 5-hour window of the week, token mix, when you build, cost per session and per project, and what used each session (main thread, subagents, each MCP server).
- **22 desktop widgets** and **8 looks** for the status card.
- **Mascots.** Animated desktop pets whose mood and health bar follow your usage: fresh, focused, tired, asleep at the limit, waking at the reset.
- **Share card.** A 1200 × 675 image of your month for X.
- **Claude Code integration.** A status line for your terminal and an MCP server, so Claude can check how much window is left and pace itself.

<p align="center"><img src="docs/dashboard.png" width="820" alt="Dashboard"></p>

<p align="center"><img src="docs/widgets.png" width="820" alt="Widgets"></p>

<p align="center"><img src="docs/looks.png" width="560" alt="Looks"></p>

## Install

**Download:** grab `Reset-0.1.dmg` from [Releases](https://github.com/msfbeast/reset/releases/latest), open it and drag Reset to Applications.

Reset isn't notarized yet, so macOS blocks the first launch. Open Reset once, close the warning, then go to **System Settings → Privacy & Security** and click **Open Anyway** next to Reset. You only do this once. (Or run `xattr -dr com.apple.quarantine /Applications/Reset.app` in Terminal.)

The download is ad-hoc signed, so its widgets won't appear. For widgets, build it yourself as below.

**Build from source** (about two minutes):

You need macOS 14 or later, Xcode 16 or later, and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
git clone https://github.com/msfbeast/reset.git
cd reset
./scripts/build.sh --install
```

That builds an ad-hoc signed app and copies it to `/Applications`.

**Widgets need a real signature.** macOS only lists widgets from apps signed with an Apple Development certificate. If you're signed in to Xcode with any Apple ID (a free one works), pass your team ID:

```bash
TEAM=ABCDE12345 ./scripts/build.sh --install
```

Find your team ID in Xcode under Settings → Accounts, or in Keychain Access on your "Apple Development" certificate.

## Setting it up

Open **Settings** from the menu bar item.

| Feature | How |
|---|---|
| Exact Claude usage | Turn on **Live usage from your Claude account**. Reset reads the sign-in that the Claude Code CLI stores in your Keychain and asks Anthropic for your current usage every 3 minutes. If it says the sign-in expired, run `claude auth login` once. |
| Phone alerts | Install the free ntfy app, subscribe to a long random topic name, and enter the same topic under **Phone alerts**. Anyone who knows the topic can read it, so make it unguessable. |
| Auto-start | Tick **Auto-start** for Claude. It runs `claude -p "hi" --model haiku` once when a window you were watching runs out, while the Mac is awake. Each run uses a little of your quota. |
| Value multiple | Press **Add your plan price** on the dashboard and enter what you pay per month. |
| Status line | Add to `~/.claude/settings.json`: `"statusLine": {"type": "command", "command": "cat \"$HOME/Library/Application Support/Reset/statusline.txt\""}` |
| MCP server | `claude mcp add --scope user reset -- /Applications/Reset.app/Contents/MacOS/reset-mcp` |

## Privacy

Reset reads local files only:

- Claude Code transcripts in `~/.claude/projects`. Reset scans them for usage and keeps only token counts, models, timestamps, tool and MCP names, project folders and session titles, in a cache in `~/Library/Application Support/Reset`. Your prompts and Claude's replies are never stored.
- `~/Library/Application Support/Claude/plan-usage-history.json` from the Claude desktop app
- Codex session logs in `~/.codex/sessions`
- Antigravity's local language server, while Antigravity is open

It only sends anything off your Mac for two optional features, and only to the place you'd expect:

- **Live Claude usage** sends Claude Code's sign-in to `api.anthropic.com` to read your usage. Reset never stores, refreshes or rewrites that sign-in.
- **Phone alerts** send the alert text to the ntfy server you choose.

No analytics, no accounts, no servers of its own.

## How the numbers work

- **Cost** is the API list price of your tokens (input, cache writes split into 5-minute and 1-hour, cache reads, output, and advisor calls), not what you're billed on a subscription. Prices live in `Reset/Usage/Pricing.swift`.
- **De-duplication.** Claude Code writes one transcript row per streamed content block, and resumed sessions copy rows between files. Reset counts each response once, by message id, keeping the row with the final output count.
- **Window estimate.** Without live usage, a window is assumed to open at your first message after the previous one ended, rounded down to 10 minutes, and run 5 hours. Exact reset times from Claude Code's own limit messages override the estimate.

## Demo mode

For screenshots and screen recordings, start Reset with made-up data:

```bash
open -a Reset --args -demo YES
```

Nothing is read, written, alerted or auto-started while demo mode is on.

## Trademarks

Reset is an independent project and is not affiliated with, endorsed by or sponsored by Anthropic, OpenAI or Google. Claude, Codex, Gemini and Antigravity are trademarks of their owners. The mascots are unofficial fan art based on those products' logos; you can turn them off in Settings. If you represent one of these companies and want the fan art changed or removed, please open an issue.

## License

MIT. See [LICENSE](LICENSE).
