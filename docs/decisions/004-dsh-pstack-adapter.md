# 004. DSH で pstack を使う（設定アダプター方式）

- Status: Accepted (P0 implemented 2026-11-05)
- Date: 2026-11-05
- 対象: pstack-claude 0.9.102 (`356c6e0f978df729eb16f227d795f34d221c5aad`)
- 関連: [home/pi/pstack-models.md](../../home/pi/pstack-models.md), [home/agents/agent-skills/default.nix](../../home/agents/agent-skills/default.nix)

## Context

pstack は Claude Code のツール言語（`Agent` / `AskUserQuestion` / `Skill` / `Task` / モデル別名 `opus`・`sonnet`・`haiku`・`fable`）で書かれたスキル群で、ハーネスごとに `plugins/pstack/skills/poteto-mode/references/<harness>-tools.md` というアダプター1枚を足して移植している。対応済みは Claude Code / Codex / Pi / GitHub Copilot / Muse で、**DSH 向けのアダプターは無い**。

一方 DSH 側の接点はすべてファイルベースで、pstack の要求とほぼ一致する。

| pstack が必要とするもの | DSH の対応 |
|---|---|
| スキル探索パス | `~/.agents/skills/`（`$DSH_AGENTS_HOME`）と `<repo>/.agents/skills/`（`packages/skill/skill-filesystem`） |
| セッション開始時のルーティング指示 | user-global instruction `$DSH_HOME/AGENTS.md` と `~/.agents/AGENTS.md` を自動ロード（`packages/context/agent-instructions`） |
| スキルの自動発火制御 | frontmatter `disable-model-invocation` / `user-invocable` が正規キー |
| サブエージェント | `subagent`（per-call provider/model）、`subagent_codex`・`subagent_claude_code`（DSH 同梱プラグイン、ロード済み） |
| 人間への質問 / 定期起床 | `ask_user_question` / `schedule_create` |

要件は3つ。

1. Codex と Claude を pstack の panel / 判断役として使いたい。**新規プラグインは書かず、既存プラグインで**。
2. `poteto-mode` は明示実行、または難しいタスクのときだけ使いたい（カタログ上は上流の description に任せ、難タスク時の判断はポリシー行で指示する）。
3. `unslop` / `deslop` のようなスキルは、適切なタイミングで自動発火してほしい。

## Decision

**DSH プラグインは作らない。設定（nix + Markdown）だけで済ませる。**

pstack 側のスキル本文はハーネス非依存に書かれているので、足りないのは (a) スキルの取り込み、(b) ツール名・モデル別名の対応表、(c) ルーティングポリシーの3点だけ。いずれもファイル配置で表現でき、DSH 本体にも pstack 本体にも手を入れない。

### 全体像

```
nix (この repo)                         DSH ランタイム
├─ pkgs.fetchgit pstack@356c6e0f ──┐
│                                 ├─→ ~/.agents/skills/*        (スキルカタログ)
│                                 └─→ ~/.agents/pstack-src       (agents/, models.json の参照先)
├─ home/agents/skills/pstack-dsh/SKILL.md ─→ ~/.agents/skills/pstack-dsh  (対応表)
└─ ~/.agents/AGENTS.md (3行) ─────────────→ user-global instruction (ポインタ)
                                             ↓
                                   モデルが pstack スキルを読み、
                                   pstack-dsh の表で DSH ツールに翻訳
                                             ↓
                              subagent_claude_code / subagent_codex / subagent
```

### 1. 取り込み（nix）

`programs.agent-skills.sources` に pstack を追加する。

```nix
# 既存の pin と同じ流儀で fetchgit。全リポジトリを store に置く（skills 外の
# plugins/pstack/agents/*.md と models.json を参照するため）。
pstack = pkgs.fetchgit {
  url = "https://github.com/michael-denyer/pstack-claude";
  rev = "356c6e0f978df729eb16f227d795f34d221c5aad";
  hash = "sha256-..."; # 実装時に確定
};

programs.agent-skills.sources.pstack = {
  path = pstack;
  subdir = "plugins/pstack/skills";
};

home.file.".agents/pstack-src".source = pstack;  # エージェント定義の参照先
```

- `skills.enable` の許可リストで常用分に絞る（既存 `anthropic.nix` と同じ仕組み）。全 65 スキルを入れると description だけでプロンプトが膨らむため、初期セットは `poteto-mode`, `unslop`, `deslop`, `sharpen`, `correct`, `principle-*`, `tdd`, `technical-writing`, `recall`, 使う workflow 程度。
- 名前衝突は無し（`home/agents/skills/` と pstack 65 スキルの積集合は空、2026-11-05 確認）。
- スキルは store の実ファイルを symlink するので `references/` `scripts/` もそのまま解決する。`poteto-mode` が前提にする `../<name>/SKILL.md` も兄弟として辿れる。

### 2. 対応表（`pstack-dsh` スキル）

`home/agents/skills/pstack-dsh/SKILL.md` を新設し、本文に以下を置く。description で「pstack スキルを使うときに読む」と宣言するので、必要時だけロードされる（常時トークンを払わない）。

- ツール対応: `Skill`→`skill` / `Read|Write|Edit`→`read|write|edit` / `Bash`→`bash` / `Grep|Glob`→`grep|glob` / `WebFetch|WebSearch`→`web_fetch|web_search` / `Agent`→`subagent` / `SendMessage`→`send_message` / `list_agents`→`list_agents` / `stop_agent`→`interrupt_agent` / `TodoWrite`→`todo_write` / `AskUserQuestion`→`ask_user_question` / `ScheduleWakeup`→`schedule_create`
- `subagent_type`: レジストリが無いので `~/.agents/pstack-src/plugins/pstack/agents/<name>.md` の本文をプロンプト先頭に置く。`general-purpose` は何も足さない。
- `readonly: true`: 同等機能が無いのでプロンプトで「ファイルを変更しない」と明示する。
- `isolation: worktree`: `cwd` を worktree に向ける（無ければ `git worktree add` を先に実行）。DSH に自動隔離は無い。
- モデル別名 → バックエンド（下記）。
- 運用ポリシー: prose を書いたら `unslop`、差分を残したら `deslop` を読む。

### 3. モデル別名 → 既存バックエンド

pstack のティアは `models.json` で `opus`=default / `fable`=strongest / `sonnet`=worker / `haiku`=panel 4枠目。

| 別名 | 用途 | DSH |
|---|---|---|
| `opus` | default / strongest judgment / bug-fix | `subagent_claude_code` |
| `fable` | strongest の2本目 | `subagent_codex` |
| `sonnet` | worker（feature, refactoring, explorer） | `subagent`（`ollama-cloud/deepseek-v4.1-flash`） |
| `haiku` | panel の安価な4枠目 | `subagent_codex` または deepseek |

制約（実装時に表へ明記する）:

- `subagent_codex` / `subagent_claude_code` は `model` を**インスタンス config で固定**し、per-call の model / effort を受け付けない（`NO_START_CAPABILITIES`）。別名ごとに実モデルを撃ち分けたい場合は `cordis.patch.yml` で `providerName` / `toolName` を変えたインスタンスを増やす（コード不要）。
- `@xhigh` などの effort 指定は無視される。表では「effort は落とす」と書く。
- 製品系バックエンドは一発実行で `send_message` による追撃ができない。一方向レビュー（`interrogate`, `arena` の judge）には十分。
- panel のベンダー多様性は claude / codex / deepseek の3系統で確保できる。

### 4. 設定形式: config（plugin ではない）

**結論: nix の設定 + Markdown で表現する。DSH プラグインは作らない。**

判断基準は「adapter の実体がデータか、振る舞いか」。DSH がスキル・指示・frontmatter をファイルから読む以上、必要なのはデータの配置であって実行時の注入ではない。プラグインが買うのは「ファイルを置かずに動的生成する」能力だけで、いまは要らない。

| 役割 | 形式 | 置き場所 |
|---|---|---|
| pstack の取り込み | nix（`programs.agent-skills.sources` + `home.file`） | `home/agents/pstack/default.nix`（[home/base.nix](../../home/base.nix) の imports に追加） |
| ツール・別名の対応表 | Markdown スキル1枚 | `home/agents/skills/pstack-dsh/SKILL.md` |
| 運用ポリシー | Markdown 3行 | `~/.agents/AGENTS.md`（`home.file`） |

対応表を YAML や JSON にしない理由: 読み手がモデルなので、機械可読形式にすると解釈する実装（＝プラグイン）が別途必要になる。pstack 自身も `<harness>-tools.md` という散文＋表で同じことをしている。

#### 却下した代替

| 代替 | 却下理由 |
|---|---|
| DSH プラグイン（cordis バンドル）でスキル登録・指示注入 | npm バンドル化、DSH の engines 制約、ビルドと配布の維持が増える。得られるのは「動的生成」だけで、いまは静的で足りる |
| `dsh-tools.md` を pstack 側の `references/` に置く | store は不変。フォーク維持になる |
| `pstack-models.md` 相当のシートを新設してパース | パーサが要る＝プラグイン。ロール表は Markdown の表で十分 |
| agent-skills の `transform` で `poteto-mode` の description を書き換える | 上流の description が既に「poteto / スタイル指定時」だけを誘発する文言で、要件を満たしている。書き換えは文字列一致に依存して静かに外れ得るうえ、テストで固定する保守が増える |

#### プラグインへ昇格する条件

次のどれかが実際に観測されたときだけ考える。

1. セッション開始時の注入が `AGENTS.md` では不安定、または複数プロファイル共通で配りたい
2. provider 設定から別名を動的解決したい（モデル更新への追随が表の保守より安いと分かった）
3. `subagent_type` を DSH の agent preset として登録したい（プロンプト前置では足りないと分かった）

### 5. ルーティング

**(a) poteto-mode は上流のまま（transform しない）**

上流の description は既に「poteto / `/poteto-mode` / このスタイルで」という明示要求だけを誘発する文言なので、カタログ上の自動発火は実質的に明示時のみになる。要件2の「明示実行」側はこれで満たせるため、`transform` による書き換えはしない。

- 書き換えをやめる利点: nix の文字列置換が不要になり、上流文言の変更で「一致せず無変換のまま通る」事故も、transform 後 description を固定するテストも要らなくなる。
- 失うのは「難しいタスクで自動的に入る」方。これはカタログ文言ではなく `~/.agents/AGENTS.md` のポリシー行（下記）でモデルに指示する。DSH のスキルロードはモデル判断なので、指示文でも同じ効果が期待でき、文言変更に強い。
- 自動発火が実際に鬱陶しければ、そのとき `disable-model-invocation: true`（DSH 正規キー）を transform で足して完全明示に落とす。

**(b) unslop / deslop は自動**

DSH のスキルは description 一致でモデルが自分で読む。`unslop`（"Cut AI tells from any writing."）、`deslop`、`sharpen`、`correct` は現状の description のままで適切なタイミングに発火する。pstack も元々この設計なので追加実装は不要。`pstack-dsh` にポリシー2行を置くのが補強。

**(c) ポインタ**

`~/.agents/AGENTS.md`（nix の `home.file` で管理）に3行だけ置く。

```markdown
- pstack スキルを使うときは、先に `pstack-dsh` スキルを読む。
- poteto-mode は明示要求時に使う。難しいタスク（複数ファイル・設計判断・曖昧・高リスク）では使うか検討する。
- prose を書いたら unslop、差分を残したら deslop を読む。
```

## 前提（adapter の関知外）

Claude / Codex の導入、認証、課金区分はこの adapter の関心ではない。adapter は「pstack の別名を DSH のどのツールに振るか」だけを定義し、そのバックエンドが実際に使えるかは前提条件として扱う。

- 2026-11-05 時点で Codex は forge01 で利用可（`codex 0.164.0`、`~/.codex/auth.json`）。Claude は未導入・未認証で、`home/agents/claude-code` は [home/home.nix](../../home/home.nix)（remilis）のみ。
- 別名表の `subagent_claude_code` の行は、Claude が使えるようになるまで実質未使用。表からは消さない（切り替えは設定ではなく環境側の作業なので）。

## 実装

P0 は次の4ファイルで構成する。

| ファイル | 内容 |
|---|---|
| [home/agents/pstack/default.nix](../../home/agents/pstack/default.nix) | pin（rev + hash）、`sources.pstack`、`~/.agents/pstack-src`、`~/.agents/AGENTS.md`、採用スキル 45 件（うち `principle-*` 24 件） |
| [home/agents/skills/pstack-dsh/SKILL.md](../../home/agents/skills/pstack-dsh/SKILL.md) | ツール対応、subagent の翻訳、別名→バックエンド表、運用ポリシー |
| [home/base.nix](../../home/base.nix) | `./agents/pstack` を imports に追加 |
| [t/agent-pstack.test.mts](../../t/agent-pstack.test.mts) | DSH と Pi の rev 一致、hash 形式、スキル一覧の重複、必須スキル、frontmatter |

採用セットは `enabled` リストで管理する。`poteto-mode` が `../principle-*/SKILL.md` を siblings として参照するため、principles は 24 件すべて有効にしてある。

## 検証

1. `nix flake check` + `nix run .#build-forge01`（および remilis）。
2. 新規 DSH セッションで skill カタログに pstack の採用分と `pstack-dsh` が出ること。
3. smoke: `poteto-mode` を明示指定して、`subagent_codex` / `subagent`（Claude が使える環境では `subagent_claude_code`）を撃ち分けること。簡単なタスクでは自動で入らないこと。
4. prose を書かせて `unslop` がロードされること、差分を残して `deslop` がロードされること。
5. `t/` に nix 評価の回帰テストを追加（採用スキル一覧の固定）。transform を使わないので description の固定は不要。

## Consequences

- pstack を DSH で使うための可動部分が「nix 1ブロック + Markdown 2ファイル」に収まり、DSH 本体・pstack 本体のフォーク維持が不要。`transform` も使わないので、上流の文言変更に追随するコードを持たない。
- 半面、以下は設定では埋まらないので運用で吸収する: 自動ルーティングの確実性（AGENTS.md 依存）、per-call の model/effort、agent type レジストリ、worktree 隔離、panel の厳密なモデル指定。
- モデル別名表はモデル更新で陳腐化する。表が原因で誤動作したら、そのとき初めて DSH プラグイン化（provider 設定から別名を動的解決）を検討する。プラグイン化の判断ラインは「注入の不安定さ」か「別名解決の陳腐化」が実際に観測されたとき。

## Phases

| Phase | 内容 | 前提 |
|---|---|---|
| P0 | pstack 取り込み + `pstack-dsh` + `~/.agents/AGENTS.md`（unslop/deslop ポリシー含む） | 無し（Codex は既に可。Claude 行は環境が整うまで未使用） |
| P1 | 必要なら `cordis.patch.yml` に Claude/Codex の追加インスタンス（別名ごとのモデル） | P0 の運用観察 |
| P2 | （adapter の外）Claude / Codex の導入・認証・課金区分の整備 | 任意 |

## Open questions

- `skills.enable` の初期セット（65 全部か、常用 15〜20 か）。
- ポインタは user-global（`~/.agents/AGENTS.md`）か、repo の `home/agents/AGENTS.md` に寄せるか。
- panel の同時起動数の上限をどこで制御するか。

## References

- DSH `@deepseek-ai/dsh-subagent-claude-code` README — 「Native Claude settings and authentication remain authoritative」、`env` は credential-scrubbed な親環境への上書き: `packages/subagent/subagent-claude-code/README.md`
- pstack-claude `plugins/pstack/skills/poteto-mode/references/pi-tools.md` — 本 adapter が倣うハーネス別マッピングの体裁
- pstack-claude `plugins/pstack/models.json` — ティア（`opus`/`fable`/`sonnet`/`haiku`）と Pi/Codex のモデル対応
- DSH `packages/skill/skill-filesystem` — `~/.agents/skills` と `<repo>/.agents/skills` のスキル探索
- DSH `packages/context/agent-instructions` — `$DSH_HOME/AGENTS.md` と `~/.agents/AGENTS.md` の user-global instruction
- agent-skills-nix `programs.agent-skills` — `sources` / `subdir` / `skills.enable` の各オプション

