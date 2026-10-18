# 003. Chrome を Managed Policy 付きで使う

- Status: Superseded（Managed Policy 管理を廃止）
- Date: 2026-04-14

## 現在の方針

Chrome 本体は引き続き Homebrew cask で導入するが、Managed Policy の生成・配置と拡張機能の強制インストールは行わない。サインイン設定と拡張機能は Chrome 側で手動管理する。

配置先の plist が消失する問題の再発を受け、管理を簡素化する。消失原因は未確定。

以前の設定が残っている環境では、`/Library/Managed Preferences/com.google.Chrome.plist` のみを手動で削除し、Chrome を完全終了して再起動する。ほかの Managed Preferences や configuration profile は削除しない。

以下は廃止前の判断の記録。

## Context

- ブラウザは Safari を使いたかったが、一部のユースケースで無理があった
  - Google Workspace (Drive / Meet 等) の動作が不安定
  - external domain → `localhost` に戻ってきた時に session cookie が ITP で落ち、OAuth 検証が成立しない
- `ungoogled-chromium` を試したが、`clients2.google.com` を遮断するため、extension の自動インストールが出来ない

## Decision

Google Chrome を Homebrew cask で入れ、`/Library/Managed Preferences/com.google.Chrome.plist` に Managed Policy を nix-darwin の `postActivation` 経由で配置する (`darwin/apps/chrome.nix`)。

- Policy は Nix attribute set で記述し `lib.generators.toPlist { escape = true; }` で plist 化
- `BrowserSignin = 0` で Google アカウント sign-in を抑止
- 必須 extension は `ExtensionSettings` で `force_installed` 指定。ID は `my.chromeForceInstallExtensions` option に集約し、所有元の app module (例: 1Password) が自分の ID を append する
- Chrome 本体の更新は Homebrew cask 経由 (Chrome の auto-update に任せる)

## Consequences

- 新しいマシンでも `darwin-rebuild switch` 一発で sign-in 抑止と必須 extension が揃う
- 新しい必須 extension は所有元 module への 1 行 append で済む
- Chrome 以外の Chromium 系 (Edge / Brave 等) は対象外。必要になったら個別に policy plist を追加
- macOS の Managed Preferences 機構に依存

## References

- 実装: `darwin/apps/chrome.nix`
- 関連コミット
  - `82f2194` install google-chrome
  - `9788ad0` chore(browser): switch from Google Chrome to Chromium
  - `2adff33` chore(browser): switch from Chromium to Google Chrome with managed policy
- Chrome Enterprise: Policy List
  - https://chromeenterprise.google/policies/
- Chrome Enterprise: ExtensionSettings
  - https://chromeenterprise.google/policies/#ExtensionSettings
