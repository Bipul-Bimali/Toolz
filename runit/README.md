# runit

Run a command fully detached and check on it later. Built for automation (n8n, cron, CI) that starts a long-running command over SSH, then polls its status before moving on.

Plain bash, no dependencies beyond standard Linux tools.

## Usage

```bash
./runit.sh '<command>'                       # start; prints ONLY the PID
./runit.sh status <pid>                      # STATE=running | finished EXIT=<n> | died_no_exit_code
./runit.sh send <pid> [text]                 # send a line to the job's stdin (no text = Enter)
./runit.sh log <pid> [console|stdout|stderr] [lines]   # default: console, 20 lines
./runit.sh ls                                # list all jobs
./runit.sh kill <pid>                        # send SIGTERM to the job
```

Make it executable once with `chmod +x runit.sh`, or run it as `bash runit.sh ...`.

### Example

```bash
$ ./runit.sh 'sleep 30 && echo done'
48213

$ ./runit.sh status 48213
STATE=running

$ ./runit.sh status 48213
STATE=finished EXIT=0

$ ./runit.sh log 48213
done
```

## Status values

| Output | Meaning |
|---|---|
| `STATE=running` | The job is still alive |
| `STATE=finished EXIT=<n>` | The job ended; `<n>` is its exit code |
| `STATE=died_no_exit_code` | The wrapper is gone but never recorded an exit code (killed with SIGKILL, host rebooted, etc.) |
| `STATE=unknown` | No job with that PID exists (exit code 1) |

## Using it from n8n (SSH node)

1. **Start:** run `/path/to/runit.sh 'your command'` and store the stdout as the PID.
2. **Poll:** in a loop with a Wait node, run `/path/to/runit.sh status <pid>`.
3. **Branch** on the output:
   - contains `STATE=running`: wait and poll again
   - contains `STATE=finished EXIT=0`: continue
   - anything else: fail or alert, and fetch details with `runit.sh log <pid> stderr 50`

Use the same SSH user for every node, because job state lives in that user's home directory.

## Where state lives

Each job gets its own directory, `~/.runit/<PID>/`. Override the location with the `RUNIT_HOME` environment variable.

| File | Contents |
|---|---|
| `cmd` | The command that was run |
| `stdout`, `stderr` | Output streams, separately |
| `console.out` | stdout and stderr combined, in arrival order |
| `started`, `ended` | Timestamps |
| `exit_code` | Written when the job finishes |
| `job.pid`, `child.pid` | PIDs of the wrapper and the command |
| `run.in` | FIFO used by `send` |

Directories are never deleted automatically. To clean up jobs older than 7 days:

```bash
find ~/.runit -maxdepth 1 -mindepth 1 -mtime +7 -exec rm -rf {} +
```

## Notes and limitations

- **Quoting:** all arguments are joined into one command string, so quote the whole command: `./runit.sh 'cmd1 && cmd2'`.
- **`kill`** sends SIGTERM to the command only, not to child processes it may have spawned.
- **`send`** writes to the job's stdin through a FIFO and gives up after 2 seconds if nothing is reading.
- **Reboots:** a job killed by a reboot shows as `died_no_exit_code`.

## Requirements

`bash`, GNU coreutils, and `setsid` (util-linux). All are present on most Linux distributions.
