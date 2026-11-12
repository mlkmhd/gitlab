# JSON output, explicit clones, and plan links

## JSON

`scripts/joe.sh` is text-only and exits 2 on `--json`. For JSON, run the raw CLI with `--json`
and poll `postgresai joe result <id> --json` (exit 1 and `"status":"pending"` while running).

## Explicit clones

`postgresai dblab clone create|list|status|reset|destroy` is rarely needed; `joe` manages its
own session clone. Never pass `--protected`. Destroy clones you created if your role allows
it (it needs Admin or AllFeaturesUser); otherwise let auto-deletion handle it.

## Console plan links

`command <id>` is an API handle, not the console's command ID. To share a plan, take the
console link from the JSON result. Newer CLI versions (0.18.1-rc.6 and later) also print it as
a `console: <url>` line, which `scripts/joe.sh` passes through. Older versions have it in the
JSON only:

```shell
postgresai joe result <id> --json | jq -r '"\(.status) \(.console_url)"'
# ok https://console.postgres.ai/gitlab/projects/<project>/sessions/<session>/commands/<commandId>
```

The JSON also has `session_id` and `console_command_id`. `console_url` is `null` or absent
until Joe stores a result row: while the command is `pending`, for an error without a row, and
when only the result upload failed (`joe_message_artifact_post`). Some errors, such as a
statement timeout, still have a link, so check `status` before you share one. After a failed
upload the statement may still have run, so check before you rerun an `exec`. HTTP status
can't verify a link.
