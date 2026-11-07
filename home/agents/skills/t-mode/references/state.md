# Persistent Intake State

Use for concurrent work items or a task that spans resumptions. Keep simple
single-run work in context. Reuse an established project record when it holds
the fields below; do not create a competing tracker for poteto.

## One current record

The intake coordinator alone writes
`<workspace>/.agents/state/t-mode/<session-key>/state.md`. Choose a unique key
once; preserve its absolute path in summaries and handoff briefs. Workers return
evidence without editing this record. A replacement coordinator takes ownership
only after the previous writer has stopped under host lifecycle rules. The
Writer field is an identity, not a lock or additional authority.

Keep these fields compact. Unknown values stay unknown; never invent host IDs.

```markdown
# Intake state
Session: <scope or host thread reference>
Writer: <coordinator identity or returned host reference>
Revision: <monotonic number>
Recorded through: <last incorporated request/result reference>

## <stable work ID> — <goal>
- Owner: <role, model/effort, returned task/thread references or not dispatched>
- Evaluator: <role, model/effort, returned references or not dispatched>
- Latest artifact: <exact tree/commit or scoped artifact identity and path>
- Checks: <name; requirement source; target; assigned role; pending/pass/unknown; evidence>
- Latest decision: <decision; reason/source; supersedes what, if any>
- Permissions: <allowed/conditional/revoked actions and source>
- Execution: <operation and target; not started/started/confirmed/unknown; evidence>
- Next: <open condition and responsible role, or complete>
```

Requirement sources explain why a check exists; result evidence explains whether
it passed. A new artifact does not inherit the old artifact's verdict. Keep
enough completed state to avoid repeating work; link detailed history elsewhere.
Record current decisions and their actual sources, not a retelling of
superseded permissions; link history when needed rather than reconstructing it.
Delivered results belong to completed evidence, not the open-check list.
Assign every open check to a role before dispatch; a missing assignment is a
coordination task, not a reason to waive the check.

## Update on transitions

Update before dispatch and after a relevant result, artifact change, decision,
or permission change; not every message. Save a complete record at each safe
boundary, using a temporary file and rename where supported. Incorporate results
only for the work and artifact they cover. A late result for an older artifact
is history, not approval of the current artifact.

Before an authorized external or non-repeatable operation, record it as started
with its target. Afterward record the result and evidence. A resumed started or
unknown operation needs a check of the actual outcome (git/remote/PR state, for
example) before any retry. A missing result is not proof the operation failed.

## Resume from the same record

Carry the absolute path, revision, and open work IDs through compaction or
handoff, rather than generating a second verdict-only summary. On resume, read
the whole record, including completed items; open IDs guide actions, not the
scope of restoration. Then reconcile newer user instructions and actual
artifact/evidence pointers. The file records prior instructions; it grants no
new authority and does not prove that an operation happened.

Compare revision with the pointer and session/Writer with the known scope. A lower file revision
is stale; recover intervening updates before acting on affected work. A higher
revision or changed Writer needs reconciliation, not rollback to the summary.
On confirmed ownership transfer, update Writer and increment revision.

If the path is lost, recover it from the scoped thread or established project
record. Do not choose another session's file by recency. If the file is missing
or stale, recover the missing source/results and mark affected fields and
permissions unknown; continue only independent work whose authorization is
established elsewhere. Do not repeat a recorded completed action
or relax a check merely to repair missing context.

This is a file-based checkpoint, not an automatic compaction hook or scheduler.
