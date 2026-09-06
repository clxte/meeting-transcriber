# Transcript Delivery

Send each finished transcript to an HTTP endpoint you control, so a downstream
consumer — a summarizer, a CRM sync, an archive — can act on it without polling
the app or watching a folder.

Off by default. Enable it in **Settings → Output → Transcript Delivery**.

## Why a POST and not a folder

The transcript file is written up to three times under the same name: an
unlabelled draft as soon as transcription returns, the labelled version once
diarization finishes, and a third time with the real speaker names after the
naming dialog is resolved — which can be hours later, or up to a day via the
stale-naming cleanup. A folder watcher sees three writes and cannot tell which is
final.

The POST fires on the job's transition to `done`, which is the one moment at
which "this transcript is final" is true. It carries the speaker names the user
actually confirmed.

## Configuration

| Setting | Meaning |
|---|---|
| Send transcript to a server | Master switch. Off by default. |
| Endpoint | Where to POST. Must be `https`, unless the host is `localhost` / `127.0.0.1`. |
| Bearer Token | Sent as `Authorization: Bearer <token>`. Optional. Stored in the Keychain. |

Plaintext to a remote host is refused before anything is sent: a transcript is
verbatim meeting speech, and the pipeline goes as far as `chmod 600` on the file
on disk. Loopback stays allowed so an endpoint can be developed locally.

## Request

```
POST <your endpoint>
Content-Type: application/json
Authorization: Bearer <token>        # omitted when no token is configured
Idempotency-Key: <jobId>
```

```json
{
  "jobId": "6F9619FF-8B86-D011-B42D-00CF4FC964FF",
  "meetingTitle": "Acme — quarterly review",
  "appName": "zoom.us",
  "startedAt": "2026-09-06T12:00:00Z",
  "enqueuedAt": "2026-09-06T13:04:11Z",
  "participants": ["Alice Martin", "Bob Chen"],
  "transcript": "[Alice Martin] Let's start with...\n[Bob Chen] Sure...",
  "warnings": []
}
```

All eight keys are always present. Nullable fields are sent as an explicit
`null`, never omitted, so the shape does not change between a recorded meeting
and an imported file.

### Field notes

- **`startedAt`** — wall-clock meeting start, captured by the recorder. **This is
  the field to join on.** It lines up with a calendar entry, which is the only
  reliable way to resolve who a meeting was with. `null` for imported files and
  for jobs recovered after a crash, which have no real meeting start.
- **`enqueuedAt`** — when the job entered the pipeline. Always present. A coarse
  fallback only: for an import it can be days after the meeting, so do not treat
  it as a meeting time.
- **`meetingTitle`** — the window title when one could be read, otherwise a
  placeholder built from the app name. The real title needs the Screen Recording
  grant. Do not assume it names the meeting or the counterparty.
- **`appName`** — the app the audio came from. Names the channel, not the client.
- **`participants`** — roster names when they could be read. Teams only today,
  needs the Accessibility grant, and empty far more often than not.
- **`transcript`** — the full text, speaker-labelled as `[Name]` when diarization
  ran. Names are the ones confirmed in the naming dialog, or auto-assigned ones
  (`Speaker 1`, …) when it was skipped. Voices enrolled in Settings → Speakers are
  matched automatically and appear under their real names with no dialog at all.
- **`warnings`** — non-fatal problems recorded during processing (echo bleed, a
  capture channel that went silent). Worth surfacing next to the transcript,
  since they bear on how much to trust it.

## Responses the app expects

Any `2xx` counts as delivered. Return it as soon as you have durably accepted the
payload — do not hold the connection open while you summarize.

| Status | App behaviour |
|---|---|
| `2xx` | Success. Done. |
| `429`, `5xx` | Retried, up to 3 attempts total, backing off 2s then 8s. |
| other `4xx` | Not retried — a bad token or a moved endpoint will not fix itself. The user is notified. |
| transport failure | Retried on the same schedule. |

After the attempts are spent the user gets a "Transcript Delivery Failed"
notification. Nothing is lost: the `.txt` stays in the output folder either way.
There is no persistent retry queue — a delivery missed while the laptop was
offline is not sent later.

## Idempotency

`Idempotency-Key` carries the `jobId` and is stable across retries, so a retry
whose response was lost in flight is recognisable as the same delivery rather
than a second meeting. Key your inserts on it if duplicates would matter.

## Resolving who the meeting was with

The app cannot tell you reliably. `meetingTitle` is often a room code,
`appName` names the channel, and `participants` is Teams-only and usually empty.

Join on `startedAt` against your calendar instead: the calendar event gives you
the invitee email addresses, and those are what match a CRM contact. That lookup
belongs in your endpoint, not in the app.

## Turning off protocol generation

If your consumer produces its own summary, set **Settings → Output → LLM
Provider** to `None`. The pipeline then skips protocol generation entirely and
keeps the transcript, which is delivered exactly as described above.

## See also

- `docs/automation-api.md` — the pull-based `/v1` API, for driving the app rather
  than being notified by it.
