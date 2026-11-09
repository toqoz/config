# Development Model Profiles

These are provisional candidate pools informed by reference material and later
discussion, not user-approved capability restrictions or proved benchmarks. Merge
activities with similar reasoning and spending needs; do not create a profile
for every activity. Independence, waiting tolerance, and quota remain filters.

| ID | Requirement and resource target | OpenAI | Anthropic | DeepSeek |
|---|---|---|---|---|
| R0 | Exact mechanical work; minimize consumption, deterministic tools first | Luna low; Terra 6.1 non-reasoning | — | V4.1 Flash non-reasoning |
| R1 | Bounded local reasoning and focused checks; low consumption | Terra 6.1 medium; Sol 6.1 low; Luna low with capable review (trial) | Haiku 5.5 high | V4.1 Flash cloud low (build 1017; observed near Sol); high/max with capable review |
| R2 | Own an outcome across interfaces or resolve source-based choices; scale effort to difficulty | Sol 6.1 medium/high/xhigh; Astra medium (interactive) | Opus 5.5 medium/high; Sonnet 5.5 high/xhigh | V4.1 Flash low/medium with capable Sol/Sonnet review; high/max for waitable bulk |
| R3 | Difficult hypotheses, subtle consequential judgment; accept more consumption and waiting | Sol 6.1 max; Astra high | Opus 5.5 xhigh/max; Sonnet 5.5 max (command-driven verification) | — |

R0 describes mechanical work, not a permanent limitation on its listed models.
A lighter author plus capable review can replace a stronger solo author when
errors are detectable and repair is reliable. Conversely, repeated repair,
expensive context transfer, or hard-to-detect defects can favor a stronger author.
A reviewer providing another viewpoint need not be stronger; one compensating
for the author's limitations must be able to detect its likely errors.

Terra and Luna are expected to appear as narrowly scoped delegated runs: R0
mechanical work, R1 bounded reasoning and focused checks, a bounded
implementation, or a narrow complementary review. The user does not plan to use
them as the coordinator, as the author owning a whole outcome, or for ordinary
cross-interface development and substantial design. A higher class may still
delegate a bounded sub-task to Terra; that does not make Terra the owner. Do not
promote them back into the starting rows for those roles without new evidence.

Treat Luna coding plus review and other untested combinations as candidates to
evaluate, not as established equivalents or forbidden routes. The handoff's
claims about model weaknesses and excluded efforts are opinions to validate,
not authorization rules. An unlisted candidate is not prohibited by this table.
Do not add a model to every activity or keep a strong author doing bulk work
merely to minimize handoffs. Choose and compare complete routes.

## Apply the starting assignments

Use these starting rules, not a per-task economic calculation. They are design
preferences to validate, not measured optimal routes. Explicit task choices win.

| Role requirement | Starting choice | Other eligible choices by context |
|---|---|---|
| Explicitly requested t-mode intake | Sol 6.1 low | DeepSeek V4.1 Flash low (`ollama/deepseek-v4.1-flash:cloud`, build 1017); explicit thread model choices win |
| Exact mechanical edit | Intake or deterministic tool | R0 when bulk execution actually needs a worker |
| Established bounded implementation | Terra 6.1 medium | Sol 6.1 low; Haiku 5.5 high; DeepSeek Flash low/medium with capable review; high/max for waitable bulk when shifting quota is useful |
| Ordinary development or investigation across interfaces | Sol 6.1 medium | Sol high for harder reasoning; Sonnet high; DeepSeek Flash low/medium plus capable review when checking and repair are tractable |
| Substantial source-based design or difficult investigation | Sol 6.1 high/xhigh | Opus 5.5 high; Astra medium for an interactive judgment |
| Hard hypotheses or subtle consequential judgment | Sol 6.1 max or Astra high | Opus 5.5 xhigh; choose vendor with the independent evaluation role in mind |
| Narrow complementary review, without compensating for a weak author | Haiku high after OpenAI; Terra medium or Sol low after Anthropic | Choose capable alternatives within R1; promote if the review needs deeper reasoning |
| Standard independent review or review compensating for a cheaper author | Sonnet 5.5 high after OpenAI; Sol 6.1 medium after Anthropic/DeepSeek | Opus medium after OpenAI; raise review capability when detecting likely errors requires it |
| High-consequence independent evaluation or difficult adjudication | Opus 5.5 xhigh after OpenAI; Sol 6.1 max/Astra high after Anthropic | Other R3 candidates preserving required independence; max only for the reasoning need |
| Bounded technical classification assessment | Sol 6.1 medium, read-only | Raise effort only when the scope question itself is difficult |
| Poteto coordinator | Opus 5.5 high | R2/R3 as explicitly selected; its workers use poteto's own preferences |

Use Sol 6.1 low as the starting model of a t-mode coordinator thread, with
DeepSeek V4.1 Flash low on the `ollama/deepseek-v4.1-flash:cloud` route (build
1017) as the alternative; do not spawn another router or switch a running thread
to enforce it. This governs the t-mode thread only and
does not set the model for ordinary non-t-mode development threads, which start
from Sol 6.1 medium. Terra low is an R0 mechanical author and Terra/Luna stay
within scoped delegation, so neither is a general thread default: one day of use
reported t-mode intake, brief writing, and ordinary development under Terra low
as inadequate, against earlier diagnostics that still favored it for retaining
named repair evaluators at mechanical work. Choosing Sol
as coordinator does not make a Sol author's review independent; select the
evaluator by vendor as usual. These are user observations, not a capability or
monetary cost ranking.

Implementation difficulty selects the author; detection difficulty and the purpose
of independence select the evaluator. A narrow complementary scan does not satisfy
a required compensation review simply because it is from another vendor. Where
runtime verification is needed, put it in that evaluator's brief and choose a
model capable of operating the surface. Do not insert a design role solely because
a change has high consequences. Never let the author choose its review exemption.

Choose provider candidates before dispatch, filtering for required independence,
capability, waiting tolerance, and known headroom. At high consequences, reserve
the independent review vendor first. Use the table's choices to resolve known
tradeoffs; complex economic comparisons belong to design/maintenance, not intake.

## Quota and constraints

- Current user-reported headroom: Codex > Claude approximately equal to DeepSeek.
  Meet capability and independence needs first, then favor available headroom.
  Put implementation volume on Codex; reserve Claude for useful design or
  complementary review; use DeepSeek for bounded work that can wait. Do not add
  DeepSeek drafting plus another finishing pass merely to distribute usage.
- This is a changeable preference, not percentages or a provider mandate.
  Update from a newer user statement or observed limit error; do not poll quota.
  Do not infer API/subscription billing from a model or driver name.
- Vendor means the model maker (OpenAI, Anthropic, DeepSeek), not its CLI or T3
  provider. Reviews use a different vendor than implementation; prefer a final
  reviewer different from design. Do not waive required diversity to save quota.
- The user wants capable Sol or Sonnet review for DeepSeek development work.
  Include that review when considering this route; it can also satisfy other
  independent-check needs. Do not generalize this to a permanent prohibition
  on DeepSeek roles or a universal review-of-every-output requirement.
- Resolve effort/mode from actual provider capabilities. DeepSeek is reachable
  through more than one provider instance with different levels:
  `ollama/deepseek-v4.1-flash:cloud` exposes thinking off/minimal/low/medium/high
  (default low), while `opencode-go/deepseek-v4.1-flash` exposes low/high/max.
  Low is a real level on both; do not reinterpret the label or silently equate it
  with a different mode. `1017` names the build of the DeepSeek Flash model the
  user evaluated on the ollama cloud route, not a different route to substitute;
  the catalog also carries similarly numbered builds, so match the provider
  instance rather than the build number. The user's one-day report places that
  build's low near Sol on ordinary development and selects it as the intake
  alternative; treat that as an observation to validate, not a measured benchmark.
  Evaluate latency in the route's context rather than permanently excluding a
  vendor from interactive work.
- Suggestions to exclude particular models/efforts in the handoff are hypotheses,
  not bans. Explicit user constraints and actual host capabilities still govern.

## Dispatch

Class candidates are an authorized selection pool, not a fixed default plus a
requirement to ask about every alternative. Select the appropriate candidate
before dispatch; explicit current-task model/effort choices win. Resolve actual
provider/model/option IDs from the host catalog only when dispatching, reusing
known capabilities under host rules. Never invent or silently change a target
after an unavailable-model error; follow host replacement rules. Report missing
mandatory coverage rather than substituting the author's vendor. Continue
unrelated authorized work when an optional phase is unavailable.

Follow the host's native/delegated boundary and completion instructions. Use
standard speed unless requested or required by the selected workflow. Poteto
runs retain their own bundled/saved model configuration.
