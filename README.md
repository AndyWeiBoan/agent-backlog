# agent-backlog

**A shared to-do list for you and your AI coding agents — living inside tmux.**

[繁體中文](README.zh-TW.md) · English

Zero dependencies. No database, no JSON store, no Node, no Python, no `fzf`, no `jq`.
Just tmux and POSIX tools you already have.

![agent-backlog](assets/demo.png)

---

## The idea in one line

> **One backlog item *is* one tmux window.**

The window name is the title. The body lives in a tmux window option. That's the
whole data model — the list *is* your window list, filtered.

Because of that, an item and *the place where the work happens* are the **same
object**. There is no record pointing at a workspace; there is just the workspace.

- Press `Enter` — you don't "open a record", you **walk into the window**
- Press `C-g` — a Claude Code instance starts **in that window**, with the item's
  text as its prompt
- Your agent's `list` reports what is actually running there (`zsh` = not started
  yet), queried live from tmux — not a status field that drifts out of sync

## Why it exists

When you're working with an AI agent, action items surface constantly. You need a
list that **both of you can see**, where items can be **handed to a separate agent
instance**, and which you can **take over by hand** at any moment.

Claude Code's built-in TodoWrite doesn't do that — it's step-tracking inside a
single session. This is the other thing: work items that outlive the session, that
a human can grab, and that live where the work happens.

## Requirements

- **macOS or Linux** (anything else is refused at load time)
- **tmux ≥ 3.0** — tested on 3.4 and 3.6a

That's it. Uses only `sh` `awk` `sed` `stty` `dd` `od` `cut` `tr` `wc` `grep`
`mkfifo` `mktemp` — all POSIX, all already on your machine.

## Install

### TPM

```tmux
set -g @plugin 'AndyWeiBoan/agent-backlog'
run '~/.tmux/plugins/tpm/tpm'
```

Then `prefix + I`.

> TPM itself needs `bash` and `git`. That's TPM's requirement, not this plugin's —
> the manual route below needs neither.

### Manual

```tmux
run-shell ~/path/to/agent-backlog/agent-backlog.tmux
```

Then `tmux source-file ~/.tmux.conf`.

> `source-file` does **not** remove bindings you deleted from your config.
> If you change keys, `tmux unbind <old-key>` explicitly.

### For your agent (optional)

```sh
claude mcp add agent-backlog -- sh ~/path/to/agent-backlog/scripts/mcp-server.sh
```

The MCP server is **also zero-dependency** — POSIX `sh` + `awk`, including its own
JSON parser. See [How it works](#how-it-works).

## Usage

`prefix + A` opens the list. (Both cases are bound — tmux keys are case sensitive,
and a key bound only as `A` does *nothing at all* when you press `a`, with no error.)

| Key | Action |
|---|---|
| *type* | filter (substring; CJK works) |
| `↑` `↓` | move selection (`C-p` / `C-n` too) |
| `C-e` `C-y` | scroll preview one line |
| `C-d` `C-u` | scroll preview half page |
| `C-f` `C-b` | scroll preview full page |
| `Enter` | switch to that item's window |
| `C-g` | dispatch: start `claude` there and paste the item in |
| `C-t` | cycle status (pending → blocked → done) |
| `C-x` | delete (asks `y`/`n` first) |
| `Tab` | toggle scope: this session ⇄ all sessions |
| `C-r` | reload the list |
| `ESC` `C-c` | leave, returning to where you came from |
| `prefix` + `⌥←` `⌥→` | resize the divider (tmux's own binding; width is remembered) |

Add an item from the shell:

```sh
echo '## Symptoms
KYC thumbnails fail to load in prod, 82 hits in 7d.' \
  | sh scripts/add.sh prod-kyc-thumbnail-missing
```

Back up / restore (items live in tmux server memory — see
[Trade-offs](#trade-offs-and-side-effects)):

```sh
sh scripts/backup.sh              # → ~/agent-backlog-<timestamp>.dump
sh scripts/restore.sh <file>      # skips items that already exist
```

## Configuration

| Option | Default | Meaning |
|---|---|---|
| `@agent_backlog_key` | `A` | key after `prefix` |
| `@agent_backlog_root_key` | — | prefix-less keys, space separated |
| `@agent_backlog_no_key` | — | `on` = bind nothing, do it yourself |
| `@agent_backlog_scope` | `session` | `session` or `global` |
| `@agent_backlog_compat` | — | `on` = also read legacy `@prompt` / `@status` |
| `@agent_backlog_lang` | `en` | `zh-TW` switches the UI to Traditional Chinese |

Want `Ctrl+/` instead of a prefix key:

```tmux
set -g @agent_backlog_root_key 'C-/ C-_'
```

> **Bind both.** With extended keys (CSI u) off, terminals send `0x1F` for
> `Ctrl+/`, which tmux calls `C-_`. Binding only `C-/` does nothing in most
> terminals.

Rolling your own binding — pass `#{session_id}`, `run-shell` expands it at
key-press time:

```tmux
set -g @agent_backlog_no_key on
bind-key -n C-o run-shell "sh #{@agent_backlog_path}/scripts/open.sh '#{session_id}'"
```

## For agents (MCP)

Six tools: `list` `show` `add` `dispatch` `peek` `set_status`.

There is deliberately **no `delete`** — deleting is a human action.

Registering as MCP buys **discoverability**, not capability: a shell script does
the same work, but a fresh Claude Code session has no idea it exists. As an MCP
server, every session loads the tools and their descriptions automatically.

The agent is scoped the same way you are — it derives its own session from the
inherited `TMUX_PANE`. Without that, you'd see 0 items while your agent sees 11,
which breaks the one thing this project is for.

## How it works

**Storage is tmux itself.** Each item is a window carrying two user options:

| Option | Holds |
|---|---|
| `@agent_backlog_prompt` | the raw markdown (also the dispatch prompt) |
| `@agent_backlog_status` | pending / running / blocked / done (any string) |

"Is this an item?" == "does this window have a prompt option?" No sync, no second
source of truth.

**The UI is a window with two panes.** Left: a POSIX-shell loop reading keys with
`stty raw` + `dd`, filtering with `awk`, painting the list. Right: a preview pane
fed through a fifo.

**Scrolling is delegated to tmux.** The preview pane sits in copy-mode; the chooser
just sends `send-keys -X page-down`. Wrapping, East-Asian character widths, and the
`[n/m]` scroll indicator are all tmux's job, so they're correct for free.

**Markdown rendering is 169 lines of awk** (`md.awk`) — headings, lists, inline
code, blockquotes, fenced blocks with keyword-level SQL/C# highlighting. Byte-for-byte
identical output across BWK awk (macOS), busybox awk, and gawk.

**The MCP server speaks JSON-RPC in shell.** Generating JSON is easy (fixed escaping,
UTF-8 passes through). Parsing is the hard part — but only a handful of field paths
matter, so `json_get.awk` is a small tokenizer that flattens one JSON line into
`path<TAB>value`, including `\uXXXX` decoding (some clients escape all non-ASCII;
without decoding, every CJK character becomes `?`).

Roughly 1,500 lines total.

## Trade-offs and side effects

Read this part. Some of these are deliberate, and one of them can lose data.

### Items are not persistent

They live in the tmux server's memory. **Reboot, or `kill-server`, and they are
gone.** Closing an item's window deletes that item — there is no second copy.

Use `scripts/backup.sh` if the content matters. Persistence via
`tmux-resurrect` hooks is planned, not built.

### N items means N windows

Twenty items is twenty idle windows in your window list. That's the cost of making
the item and its workspace the same object. If you keep dozens of long-lived items,
this design will annoy you.

### While the list is open, it takes over your keys

The chooser window sets tmux's `key-table`, which makes it **skip your entire root
key table** (`bind -n ...`). Without that, common bindings like `C-d`, `C-p`, `C-t`
would be intercepted before reaching the list. `prefix` still works normally.

`key-table` is a *session*-level option, so it is saved and restored on exit, and a
hook restores it whenever you switch away to another window. If the chooser is ever
killed in a way that skips cleanup, run `tmux set-option -u key-table`.

### It installs session-level hooks while open

`client-resized`, `client-attached`, `client-detached`, `after-resize-pane`,
`after-select-window`, `window-pane-changed` — all scoped to the session, all
removed on exit. They exist to redraw on resize and to bounce focus out of the
preview pane (which reads no keys, so focus landing there looks like a freeze).

### Dispatch really runs an agent

`C-g` types `claude` into that window and pastes the item as a prompt. It spends
tokens. It needs `claude` on the PATH of *that pane's interactive shell* — not the
tmux server's PATH.

### Scope defaults to per-session

You only see items whose windows live in your current session. `Tab` toggles to
all sessions; `@agent_backlog_scope global` changes the default.

### Not covered

Tables aren't rendered (needs East-Asian width math). Fuzzy matching is substring,
not subsequence. JSON-RPC batching is unsupported. Nothing crosses machines — scope
ends at a single tmux server.

## Migrating from a legacy `@prompt` / `@status` setup

```tmux
set -g @agent_backlog_compat on
```

Compat mode reads the old keys too, and writes status back to whichever key an item
already uses — so both tools see one copy of the data and can't drift apart.

`scripts/migrate.sh` copies old keys to the new namespace (deliberately keeping the
old ones). That produces **two copies**, which will diverge; run it only when you've
decided to move for good.

## Uninstall

```sh
tmux unbind A
tmux kill-window -t '[backlog]' 2>/dev/null
for h in client-resized client-attached client-detached after-resize-pane \
         after-select-window window-pane-changed; do
    tmux set-hook -u "$h"
done
tmux set-option -u key-table
```

Your items are windows; keeping or closing them is up to you.

## Documentation

Design rationale, research results, and a long list of things that bit us during
development live in [docs/](docs/). Implementation details:
[docs/07-implementation.md](docs/07-implementation.md).

## License

MIT
