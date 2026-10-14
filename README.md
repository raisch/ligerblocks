# LigerBlocks Minecraft Server

A modded Minecraft server running in Docker on an Ubuntu VPS, using the
[`itzg/minecraft-server`](https://github.com/itzg/docker-minecraft-server) image
to load the LigerBlocks modpack from a local `.mrpack` file.

| | |
|---|---|
| Modpack | LigerBlocks 1.0.0 (`.mrpack`) |
| Minecraft | 1.21.1 |
| Loader | NeoForge 21.1.256 |
| Java | 21 (image tag `java21`) |
| Port | 25565/tcp |
| Project directory | `/opt/minecraft` |

The loader and Minecraft version are read from the modpack, not set by hand.

## Contents of this directory

```
/opt/minecraft
├── docker-compose.yaml    # server definition
├── package.json           # helper scripts (npm run ...)
├── README.md
├── packwiz/               # working files for the modpack (see "Modpack workflow")
├── modpacks/              # exported packs, mounted read-only in the container
│   ├── Ligerblocks-YYYYMMDD-VV.mrpack   # every released version, kept
│   └── Ligerblocks.mrpack -> Ligerblocks-YYYYMMDD-VV.mrpack   # symlink to the current one
└── data/                  # world, config, mods, whitelist (created on first run)
```

## Requirements

- Docker Engine with the Compose plugin (`docker compose version`)
- Node.js and npm, only for the `npm run` helper scripts
  (`sudo apt install npm`). Every script is a plain `docker compose` command,
  so the server can be managed without npm.
- A VPS with enough RAM for `MEMORY` in `docker-compose.yaml`, plus 1-2 GB for
  the OS. Check with `free -h`.

## Installation

1. Copy the project files into `/opt/minecraft`.
2. Place the modpack in `modpacks/`:
   ```
   mkdir -p /opt/minecraft/modpacks
   scp LigerBlocks.mrpack root@<server-ip>:/opt/minecraft/modpacks/Ligerblocks.mrpack
   ```
   The filename must match `MODRINTH_MODPACK` in `docker-compose.yaml`
   exactly. Linux is case-sensitive.
3. Edit `docker-compose.yaml`:
   - `MEMORY`: set below the VPS's total RAM.
   - `WHITELIST` and `OPS`: replace the placeholder with real Minecraft Java
     usernames. A name that doesn't belong to a real Java account makes the
     startup lookup fail.
4. Validate the file, then start the server:
   ```
   cd /opt/minecraft
   docker compose config
   docker compose up -d
   docker compose logs -f
   ```
5. The first boot takes several minutes: it installs NeoForge and downloads
   every mod. The server is ready when the log shows `Done (...)! For help, type "help"`.

## Starting and stopping

| Task | npm script | Direct command |
|---|---|---|
| Start | `npm run server:up` | `docker compose up -d` |
| Stop | `npm run server:down` | `docker compose down` |
| Restart | `npm run server:restart` | `docker compose restart` |
| Status | `npm run server:status` | `docker compose ps` |
| Follow logs | `npm run server:logs` | `docker compose logs -f --tail=100` |
| Update image | `npm run server:update` | `docker compose pull && docker compose up -d` |

The container has `restart: unless-stopped`, so it comes back after a reboot
unless it was stopped on purpose.

## Console and commands

Open an interactive RCON console (type `exit` to leave):

```
npm run server:console
```

Run a single command:

```
docker compose exec minecraft rcon-cli <command>
```

Useful scripts:

| Script | What it does |
|---|---|
| `server:say -- <message>` | Broadcast a message to players |
| `server:save` | Flush the world to disk |
| `server:backup` | Save, then write `backup-YYYY-MM-DD-HHMM.tar.gz` of `data/` |

Arguments after `--` are passed to the underlying command.

## Whitelist and operators

The whitelist is enabled (`ENABLE_WHITELIST: "TRUE"`). Changes made with these
commands apply immediately, with no restart:

```
npm run whitelist:add -- PlayerName
npm run whitelist:remove -- PlayerName
npm run whitelist:list
npm run whitelist:reload     # after hand-editing data/whitelist.json
npm run op:add -- PlayerName
npm run op:remove -- PlayerName
```

`WHITELIST` and `OPS` in `docker-compose.yaml` seed the lists at startup. Once
you manage players with the commands above, `data/whitelist.json` is the source
of truth. Keep the compose values to a minimum so they don't conflict.

Every player needs a Java Edition account. The server runs in online mode, so
names are verified against Mojang.

## Firewall

UFW is enabled with default deny for incoming traffic and these rules:

```
sudo ufw allow 22/tcp      # or: sudo ufw limit 22/tcp
sudo ufw allow 80/tcp      # nginx
sudo ufw allow 25565/tcp   # Minecraft
```

**Docker bypasses UFW for published ports.** The `ports:` mapping in the
compose file exposes 25565 to the internet whether or not UFW lists it. Keep
the whitelist on, and add the UFW rule so the firewall config matches reality.

View blocked connection attempts with `sudo tail -f /var/log/ufw.log`
(or `sudo journalctl -k | grep UFW`).

## Backups

```
npm run server:backup
```

This creates a timestamped archive in the project directory. Archives live on
the same disk as the server, so copy them off the VPS regularly (`scp`, rclone,
or similar). The world can get large, so check free space with `df -h`.

A nightly backup via cron (`crontab -e`):

```
0 4 * * * cd /opt/minecraft && npm run server:backup
```

To restore, stop the server, replace `data/` with the extracted archive's
`data/`, and start it again.

## Modpack workflow (packwiz)

The pack is maintained with [packwiz](https://github.com/packwiz/packwiz), a
command-line tool that stores a modpack as small text files (one per mod) and
exports a `.mrpack`. All work files live in `./packwiz`. Run packwiz commands
from inside that folder, ideally on your local machine, and copy only the
finished `.mrpack` to the server.

Install packwiz with Go (`go install github.com/packwiz/packwiz@latest`, check
the project README for the Go version it needs) or download a prebuilt binary
from the project's GitHub Actions page. Documentation: https://packwiz.infra.link/

### How the pack was created

packwiz has no documented import for Modrinth packs, so the original
`.mrpack` was converted by adding its mods to a new packwiz pack with
`packwiz modrinth add`, then running `packwiz refresh`. Mods not hosted on
Modrinth need `packwiz url add <name> <download-url>` instead.

### Making a change

From `./packwiz`:

```
packwiz modrinth add <modrinth-url-or-slug>   # add a mod (or: packwiz remove <slug>)
packwiz refresh                               # rebuild index.toml and pack.toml
packwiz modrinth export                       # writes a .mrpack in the current folder
```

When adding a mod, accept the prompt to install its required dependencies,
or the server fails on startup with a missing-dependency error. Then check the
mod's `side` in its file under `mods/` (`both`, `server` or `client`). A mod
that must load on the server must not be `client`, or the image skips it and
players get a "channel missing on the server" disconnect.

### Naming and releasing a version

Exported files are renamed to `Ligerblocks-YYYYMMDD-VV.mrpack`, where `VV` is a
two-digit version for that day (`01`, `02`, ...). Every released file stays in
`./modpacks`, so you can roll back by pointing the symlink at an older one.

```
cd ./packwiz
mv <exported-file>.mrpack Ligerblocks-YYYYMMDD-VV.mrpack
cp Ligerblocks-YYYYMMDD-VV.mrpack ../modpacks
cd ../modpacks
ln -sfn Ligerblocks-YYYYMMDD-VV.mrpack Ligerblocks.mrpack
```

`docker-compose.yaml` points at the symlink (`MODRINTH_MODPACK:
"/modpacks/Ligerblocks.mrpack"`), so the compose file never changes between
versions. Use `ln -sfn` rather than `ln -s`: plain `ln -s` fails once the link
already exists. The link must be relative and inside `modpacks/`, because
Docker only sees that folder, so a link to a file elsewhere breaks.

The symlink name must match `MODRINTH_MODPACK` exactly, including
capitalization.

### Applying the new version to the server

1. `npm run server:backup`
2. Release the new file and update the symlink (above).
3. `npm run server:restart`

The image re-reads the pack on startup and installs the loader and mod
versions it specifies. Check the log for `Processing modpack files for ...` and
for the `Done (...)!` line, and look in `data/mods` for leftover jars from
removed mods (`ls data/mods`). Players need the matching version of the pack on
their clients: give them the new `.mrpack` and have them import it in the
Modrinth App or Prism Launcher.

### Rolling back

Point the symlink at the previous file and restart:

```
cd ./modpacks
ln -sfn Ligerblocks-<previous>.mrpack Ligerblocks.mrpack
cd .. && npm run server:restart
```

Restore a backup of `data/` too if the newer version changed the world.

### Keeping the pack in git

The `packwiz/` folder is plain text, so it works well in a git repository: a
diff shows exactly which mods changed between versions. Keep the `.mrpack`
files, `data/` and backups out of the repository (see `.gitignore`).

## Troubleshooting

**YAML error from Compose (`did not find expected key`).** Run `docker compose config`
to find the line. Common causes are a stray quote (for example in `MOTD`),
tabs instead of spaces, or an unquoted value containing a colon.

**Server starts as vanilla and ignores the modpack.** `TYPE: "MODRINTH"` must be
set in the compose environment. Without it the image defaults to vanilla.

**Java version errors.** NeoForge 1.21.1 needs Java 21. Keep the image tag at
`java21`. The `latest` tag moves to newer Java versions.

**`Could not resolve user from Playerdb`.** A name in `WHITELIST` or `OPS`
isn't a real Java account, or the lookup service is unreachable. Verify the name:
```
curl -s https://api.minecraftservices.com/minecraft/profile/lookup/name/<name>
```
You can also use UUIDs (dashed 8-4-4-4-12 format) in place of names.

**Modpack file not found.** Check what the container sees:
`docker compose exec minecraft ls -l /modpacks/`. The filename must match
`MODRINTH_MODPACK` exactly, including capitalization. A symlink works only if
its target is also inside `modpacks/`.

**Crash on startup naming a specific mod.** Some client-only mods crash a
dedicated server. Exclude the mod by name in the compose environment:
```
MODRINTH_EXCLUDE_FILES: "modname"
```
Then `docker compose up -d`. Players keep the mod on their own clients.

**Out-of-memory kills or severe lag.** Check `docker stats --no-stream minecraft`
and `free -h`. Lower or raise `MEMORY` as needed, leaving headroom for the OS.

**Can't connect from outside.** Confirm the container is up (`docker compose ps`),
the log shows `Done`, UFW allows 25565/tcp, and your VPS provider's network
firewall (if any) allows it too.

