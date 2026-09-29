# lan-sync

Folder sync between your own devices on a local network: rsync over SSH with
neighbor auto-discovery (arp/avahi), pull/push/mirror support, and a safe
dry-run by default.

The idea: if your devices can see each other on the LAN, routing the same
traffic through a cloud relay buys you nothing. Lower latency, no server load,
no dependency on anyone else's uptime — it works on top of SSH you already run.

## Commands

```bash
./lan_sync.sh discover                      # who is alive on the LAN (arp + avahi)
./lan_sync.sh preview <host> <src> <dst>    # dry-run: what would be copied
./lan_sync.sh push    <host> <src> <dst>    # local -> neighbor
./lan_sync.sh pull    <host> <src> <dst>    # neighbor -> local
./lan_sync.sh mirror  <host> <src> <dst>    # exact mirror (+ --delete)
```

Workflow: run `preview` first, review the plan, then `push`/`pull`.

## Configuration via environment variables

```bash
LAN_SYNC_USER=alice             # SSH user on the neighbors
LAN_SYNC_PORT=22                # SSH port
LAN_SYNC_EXCLUDE=".git,node_modules,.DS_Store"
```

## Example

```console
$ ./lan_sync.sh discover
Hosts found:
  192.168.1.50    nas
  192.168.1.62    imac
  192.168.1.71    xps

$ LAN_SYNC_USER=alice ./lan_sync.sh preview 192.168.1.50 ~/docs /home/alice/docs
DRY-RUN (nothing is copied). Plan /Users/alice/docs -> 192.168.1.50:/home/alice/docs
```

## Requirements

- bash, rsync, ssh; key-based login on the neighbors (`ssh-copy-id`)
- optionally `avahi-browse` (Linux) / built-in Bonjour (macOS) — for host names

No extra daemon needed: it runs on top of plain SSH.

## License

MIT
