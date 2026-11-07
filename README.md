# envdesk

A small native Mac app for the API keys scattered across your `.env` files and shell profile. Pick a project, paste a key, and it lands in the right file. Browse every key you have, masked, behind Touch ID.

It's one Swift file with no dependencies, no network access and no account. It only reads and writes plain files on your Mac.

## What it does

- **Projects.** Add a folder, and envdesk finds its `.env.local`, `.env`, `.env.development.local` and similar files, one level down too. Switch between projects from a picker.
- **Mac variables.** Keys in `~/.zshenv` are shared across every project. Saving one there also runs `launchctl setenv`, so apps started from Finder see it too.
- **Add or update a key.** Choose a name (or pick a common one, like `OPENAI_API_KEY`), paste the value, tick where it goes, and press Save. The key's line is replaced in place, and every other line, comment and order is kept.
- **Paste many at once.** Paste `KEY=VALUE` lines, a whole `.env` file, or a JSON credentials file. Nested JSON is flattened, so a Google OAuth client file with the prefix `GOOGLE_OAUTH_` gives `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET`. Delete the rows you don't need.
- **Browse safely.**
  - Values are masked.
  - Show and Copy ask for Touch ID or your password, then stay unlocked for 5 minutes.
  - A shown value hides again after 20 seconds.
  - The clipboard clears itself after 30 seconds, unless you've copied something else since.
- **Catch mistakes.**
  - A warning appears when a project's env file isn't ignored by git, so it could be committed.
  - A "differs" badge appears when the same name has different values in different files.
- **Export `.env.example`** with names only, to commit for teammates.
- **Backups.** Every change keeps a `.bak` copy beside the file, and files are set to owner-only (`600`).

## Install

Needs macOS 14 or later and the Xcode command line tools (`xcode-select --install`).

```sh
git clone https://github.com/YashSharmaa/envdesk.git
cd envdesk
./build.sh                # builds ~/Applications/envdesk.app
./build.sh /Applications  # or install it for every user
open ~/Applications/envdesk.app
```

The app is signed ad hoc on your own Mac, so Gatekeeper doesn't block it. The first time it opens a folder in Documents or Desktop, macOS asks for permission.

## Good to know

- These are plain-text files, as your tools expect. envdesk makes them easier and safer to manage, but it doesn't encrypt them. For secrets that must be encrypted at rest, use the macOS Keychain or a secrets manager.
- Values are written in single quotes (`NAME='value'`). That's read correctly by Node (`--env-file`), dotenv, Next.js, Vite, Python's python-dotenv, and zsh.
- Running apps don't see a change until they restart. Terminals need reopening.
- Only `~/.zshenv` is handled for shell variables. Bash and fish profiles aren't, yet.
- The project list is in `~/.config/envdesk/projects.json`.

## Contributing

Issues and pull requests are welcome. Everything is in `Sources.swift`.

## Licence

MIT. See [LICENSE](LICENSE).
