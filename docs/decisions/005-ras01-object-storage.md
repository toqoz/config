# 005. ras01 の S3 互換ストレージ（VersityGW + Standalone IAM）

- Status: Accepted（リポジトリ側のプロビジョニングのみ。ras01 への適用は未実施）
- Date: 2026-11-12
- 対象: versitygw 1.9.0（nixpkgs pin）、awscli2 2.36.31
- 関連: [nixos/object-storage/README.md](../../nixos/object-storage/README.md), [hosts/ras01/object-storage.nix](../../hosts/ras01/object-storage.nix)

## Context

エージェント間の大容量データ受け渡し（`handoff`）と、人に見せる成果物（`published`）の置き場を Tailnet 内に用意したい。IAM の user / role / policy / bucket は公開リポジトリで宣言し、認証情報は Git・Nix store・unit 定義・argv・ログから完全に分離する。Vault や外部 Secrets SaaS は使わない。

実装前に upstream を一次ソースで確認した（ソースは v1.9.0、リリースノートは v1.10 / v1.11）。

- nixpkgs に versitygw 1.9.0 はあるが、NixOS module は無い。
- `versitygw iam` が Standalone IAM を提供する。公開 IAM API（SigV4、root 認証）と、gateway 専用の private endpoint（unix socket か mTLS のみ）を持つ。
- root 認証情報はフラグか環境変数（`ROOT_ACCESS_KEY_ID` / `ROOT_SECRET_ACCESS_KEY`）でしか渡せない。ファイル指定のオプションは無い。
- gateway は IAM ユーザーのリクエストごとに socket 越しで署名鍵の導出とポリシー評価を行う。1.9.0 にはキャッシュが無く、IAM に届かない、または 10 秒以内に応答が無ければ HTTP 500 で拒否する。gateway 自身の root（`ROOT_ACCESS_KEY_ID`）だけは gateway 内で解決される（`auth/iam_standalone.go` の `DeriveSigningKey`）。
- gateway が IAM の private endpoint を呼ぶときの署名鍵は `--iam-standalone-access` / `--iam-standalone-secret`（環境変数 `VGW_IAM_STANDALONE_ACCESS` / `VGW_IAM_STANDALONE_SECRET`）で root とは別に渡せる。private endpoint は IAM の root だけを受け付ける。bucket の所有者は gateway の root の access key id に固定される。
- STS `AssumeRole`、managed policy、group は未実装。access key は 1 ユーザー 2 本まで、inline policy は 1 ユーザー合計 2048 byte まで。
- IAM 状態は `iam.json`（0600、secret 平文）。POSIX backend はメタデータを `user.*` xattr に持つ。
- v1.11 で gateway に署名鍵キャッシュ（既定 120 秒）が入る。

ras01 は TPM2 を持たない Raspberry Pi 3 で、SD カードは暗号化されていない。

## Decision

`nixos/object-storage/` に NixOS module `services.objectStorage` を置き、`hosts/ras01/object-storage.nix` で宣言する。

### サービス

- `versitygw-root-credentials`（oneshot）が `/var/lib/versitygw-root/root-credentials`（0400、2 行：key id と secret）を初回だけ生成する。既にあれば何もしない。
- `versitygw-iam` と `versitygw` は別ユーザーで動く。どちらも `LoadCredential=` で root 認証情報を受け取り、ラッパーが exec 先のプロセスにだけ環境変数として渡す。IAM API は `127.0.0.1:7071`、private socket は `/run/versitygw/iam.sock`（0660、gateway ユーザーは `versitygw-iam` グループ）。
- S3 は `:7070` で待ち受け、firewall で `tailscale0` にだけ開ける。
- root は IAM 専用の認証情報にする。gateway には `with-root-credentials --gateway` で、IAM 呼び出し用に本物の root を、gateway 自身の root には同じ access key id と起動ごとに生成する乱数の secret を渡す。この secret は gateway プロセスの中にしか無く、どこにも保存しない。誰も gateway の root として署名できないので、認証付きの S3 リクエストはすべて IAM に問い合わせて初めて認可される。IAM が停止・クラッシュ・hang のどれでも、root を含む新しい S3 リクエストは認可されない。
- IAM 障害前に認可された転送は完了してよく、upload の commit も許容する。gateway は IAM の停止・クラッシュ・hang に連動して強制終了しない。起動時は gateway が IAM を Wants で起動し、その後に起動する。通常の停止・再起動は upstream の SIGTERM による graceful shutdown を使い、shutdown timeout は 10 秒とする。upstream は停止中に進行中のリクエストを cancel する場合があり、gateway 自身の停止時に転送の完了は保証しない。
- bucket は予約済みの管理ユーザー `versitygw-reconcile`（`s3:CreateBucket` を宣言済み bucket に、`s3:ListAllMyBuckets` を `*` に許可）が作る。access key は reconcile の 1 回の実行中だけ存在し、終了時に削除する。
- gateway は `--iam-cache-disable` 付きで起動する。1.9.0 では効果が無いが、1.11 以降のキャッシュによる revoke 遅延と fail-closed の弱化を防ぐ。

### 宣言と reconcile

- Nix から desired-state JSON を生成し、`versitygw-reconcile`（oneshot、DynamicUser）が AWS CLI で収束させる。unit が JSON の store path を参照するので、宣言を変えて switch すると再実行される。
- managed policy が無いため、共通ポリシーは Nix 側で再利用し、各 identity の inline policy として書き込む。1 ポリシーにつき Allow 文 1 つで、Resource は `arn:aws:s3:::B` と `arn:aws:s3:::B/*`。
- 管理対象は IAM path `/nix-managed/` とタグ `managed-by=nix` で区別する。別の状態ファイルは持たない（backup / restore でずれない）。
- 作成と差分更新だけを行う。削除はせず、access key には触れない。宣言から消えたものは drift として記録し、残す。同名の非管理 identity は conflict として失敗させ、変更しない。

### Access key

`provision-s3-credential create|rotate|revoke|list` だけが key を発行・削除する。secret は 0600 の新規ファイルに一度だけ書き、標準出力には key id しか出さない。書き込み先のディレクトリは物理パスに解決し、以降の操作はすべてそのパスで行う。そのディレクトリと祖先は、root（または実行ユーザー）以外が書き換えられないものに限る。他のユーザーが途中でファイルを差し替えられないようにするため。書き出せなかった key は IAM から消し直す。rotate は 2 本目を足し、revoke は新しい key が使われたことを IAM の LastUsed で確認してから古い key を消す。

### Root 認証情報の保管方式

A（root 専用ファイル）を採用する。

- B（TPM2 で暗号化した systemd credential）は、ras01 に TPM2 が無いので使えない。
- C（ホスト鍵で暗号化した systemd credential）は、ホスト鍵が同じ暗号化されていない SD カードにあるため、カード盗難に対して守りにならない。しかも `iam.json` がユーザーの secret を平文で持つので、root だけ暗号化しても効果が薄い。

### Backup / restore

`versitygw-backup` がサービスを止めて、`/var/lib/versitygw` と `/var/lib/versitygw-root` を xattr 付きで 0600 の tar.gz にまとめる。restore は、展開前に tar のエントリ種別（通常ファイルとディレクトリだけ）を確かめ、private な staging に展開して、許可した構造以外のエントリが無いこと、必須ファイルがあり形式が正しいことを確かめる。そのあとでサービスを止め、現状を `*.pre-restore-<時刻>` に退避して入れ替え、所有者と権限を付け直してサービスを起動する。gateway が応答し、復元した root で IAM への署名付きリクエストが通るまでを restore の完了とし、失敗したら元の状態に戻して起動し直す。

## Consequences

- 公開リポジトリを読むだけでは、データにも認証情報にも届かない。ただし、このリポジトリの任意のコードを ras01 にデプロイできる者は秘密を読める。デプロイ権限はリポジトリの読み取りと分けて扱う。
- SD カードが暗号化されていないため、物理的に盗まれると root 認証情報と全ユーザーの secret が読める。ディスク暗号化は未解決のリスク。
- fail-closed は新しいリクエストの認可に適用する。IAM の新しい応答なしに新しい S3 リクエストを認可せず、保存した root も S3 の署名には使えない。障害前に認可された転送の完了と upload の commit は受け入れる。gateway は公開直前の IAM 再確認を行わない。IAM が hang すると、新しいリクエストは upstream の 10 秒 timeout で HTTP 500 になり、`systemctl restart versitygw-iam` で復旧する。クラッシュ時は systemd が IAM を再起動する。
- この性質は upstream が gateway 自身の root だけを内部で解決し、ほかの access key はすべて IAM に問い合わせること、SIGTERM 時の drain に依存する。versitygw を更新するときはこれらを確かめ直す。
- reconcile が同時に 2 回走ると、互いの一時 key を消して失敗することがある。やり直せば収束する。
- root 認証情報は IAM と gateway の相互認証に使うだけで、`iam.json` を暗号化しない。失っても、新しい root を生成すれば既存ユーザーと key はそのまま使える。
- role は reconcile されるが、OIDC（`AssumeRoleWithWebIdentity`）を入れるまで使えない。
- 宣言から消した user / policy / bucket は自動では消えない。将来、明示的な削除許可を加える。

## 検証

- `t/object-storage.test.mts`：本物の versitygw と awscli で、収束、2 回目の無変更、key の不変、他 bucket の拒否、root では S3 に署名できないこと、IAM の停止中と hang（SIGSTOP）中に root を含む新しい認証付き S3 リクエストが拒否されること、bucket 作成用 key が実行後に残らないこと、rotate / revoke、出力に secret が出ないことを確認する。backup / restore は Linux で実行する（darwin の GNU tar は xattr 非対応）。
- `checks.aarch64-darwin.ras01-object-storage`：IAM の loopback 限定、socket 経由の接続と IAM cache の無効化、gateway が `--gateway` モード（使えない root secret）で起動し、IAM の後に起動し、通常の graceful shutdown を使うこと、tailscale0 限定の firewall、`LoadCredential` だけによる受け渡し、user ごとの bucket 範囲を評価で確認し、スクリプトを shellcheck する。
- 使い捨ての OrbStack NixOS マシンで実際に switch し、reboot、宣言変更、rollback、IAM の停止・クラッシュ・hang での新規リクエスト拒否と復旧、新規インストールへの restore、journal / argv / unit / closure に secret が無いことを確認した（`.agents/share/versitygw-ras01/vm/`、リポジトリ外）。
