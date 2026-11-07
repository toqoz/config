"""Prepare or publish an exact-snapshot GitHub release PR; no branch writes."""
import argparse
from contextlib import contextmanager
from datetime import datetime
import fcntl
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.parse import urlparse

from release_body import BodyConflict, render_list, splice

FIELDS = 'number,url,title,body,baseRefName,headRefName,baseRefOid,headRefOid,state,isDraft,isCrossRepository'


def command(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def git(*args):
    return command('git', *args).strip()


def gh(*args):
    return json.loads(command('gh', *args))


def remote_identity(url):
    if '://' in url:
        parsed = urlparse(url)
        host, path = parsed.hostname or '', parsed.path
    elif re.match(r'[^/]+@[^:]+:', url):
        host, path = url.split('@', 1)[1].split(':', 1)
    else:
        return ('local', str(Path(url).resolve()))
    return (host.lower(), path.strip('/').removesuffix('.git').lower())


def snapshot(base, head):
    for branch in (base, head):
        git('check-ref-format', '--branch', branch)
    if base == head:
        raise ValueError('Base and head must differ')
    git('fetch', '--no-tags', 'origin', *[f'+refs/heads/{branch}:refs/remotes/origin/{branch}' for branch in (base, head)])
    base_sha = git('rev-parse', f'refs/remotes/origin/{base}^{{commit}}')
    head_sha = git('rev-parse', f'refs/remotes/origin/{head}^{{commit}}')
    bases = git('merge-base', '--all', base_sha, head_sha).splitlines()
    if len(bases) != 1:
        raise ValueError('Release comparison needs one unambiguous merge base')
    return dict(base=base, head=head, base_sha=base_sha, head_sha=head_sha, merge_base=bases[0])


def records(snap):
    data = command('git', 'log', '--merges', '--format=%H%x00%s%x00%an%x00%b%x00', snap['base_sha']+'..'+snap['head_sha'], '--')
    fields = data.split('\0')
    if fields[-1].strip():
        raise ValueError('Incomplete git log record')
    fields.pop()
    if len(fields) % 4:
        raise ValueError('Malformed git log record')
    return [(fields[i+1], fields[i+2], fields[i+3]) for i in range(0, len(fields), 4)]


def read_pr(repo, number):
    return gh('pr', 'view', str(number), '--repo', repo, '--json', FIELDS)


def validate_pr(pr, snap):
    if pr['state'] != 'OPEN' or pr.get('isDraft') or pr.get('isCrossRepository'):
        raise ValueError('Release PR must be open, ready, and within this repository')
    if (pr['baseRefName'], pr['headRefName']) != (snap['base'], snap['head']):
        raise ValueError('PR branch pair changed')
    return pr['headRefOid'] == snap['head_sha']


def write_text(path, text):
    with path.open('w', encoding='utf-8', newline='') as stream:
        stream.write(text)


@contextmanager
def local_lock(path):
    with path.open('a') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield


def validate_review_source(repo, pr, snap, review):
    if (review.get('url'), review.get('repo')) != (pr['url'], repo):
        raise ValueError('Review record belongs to another PR')
    source = review.get('source', '')
    prefix = pr['url']+'#pullrequestreview-'
    if not isinstance(source, str) or not source.startswith(prefix) or not source[len(prefix):].isdigit():
        raise ValueError('Review source must be a published GitHub review on this PR')
    remote = gh('api', f"repos/{repo}/pulls/{pr['number']}/reviews/{source[len(prefix):]}")
    if remote.get('html_url') != source or remote.get('commit_id') != snap['head_sha']:
        raise ValueError('Published GitHub review does not cover this PR head')
    if remote.get('state') not in ('COMMENTED', 'APPROVED', 'CHANGES_REQUESTED'):
        raise ValueError('GitHub review is unpublished or dismissed')
    if remote['state'] == 'CHANGES_REQUESTED' and review.get('outcome') != 'blocking':
        raise ValueError('GitHub review has blocking findings')
    matches = re.findall(r'^<!-- release-review-source (.+) -->\r?$', remote.get('body', ''), re.MULTILINE)
    if len(matches) != 1:
        raise ValueError('GitHub review is missing comparison/provenance metadata')
    details = json.loads(matches[0])
    if not isinstance(details, dict):
        raise ValueError('GitHub review metadata must be an object')
    for key in ('head_sha', 'base_sha', 'merge_base', 'reviewer', 'scope', 'independent', 'outcome'):
        if key not in details or details[key] != review.get(key):
            raise ValueError('GitHub review metadata does not match '+key)
    for key in ('head_sha', 'base_sha', 'merge_base'):
        if details[key] != snap[key]:
            raise ValueError('GitHub review does not cover current '+key)


def save_prepared(state, result, pr, title, body, evidence):
    with tempfile.NamedTemporaryFile(dir=state, prefix='prepared-', suffix='.json', delete=False) as file:
        path = Path(file.name)
    prepared = dict(result, dry_run=True, title=title, body=body, expected=pr, evidence=evidence)
    backup = path.with_suffix('.backup.md')
    if pr:
        write_text(backup, pr['body'])
        prepared['backup'] = str(backup)
    write_text(path, json.dumps(prepared, ensure_ascii=False, indent=2)+'\n')
    return dict(prepared, prepared_record=str(path))


def cleanup_prepared(state, path):
    path = Path(path).resolve()
    if path.parent != state.resolve() or not re.fullmatch(r'prepared-[a-zA-Z0-9_-]+\.json', path.name):
        raise ValueError("Cleanup is restricted to this helper's prepared files")
    path.with_suffix('.backup.md').unlink(missing_ok=True)
    path.with_suffix('.body.md').unlink(missing_ok=True)
    path.unlink()


def confirm_prepared(args, repo, state):
    path = Path(args.confirm_prepared).resolve()
    if path.parent != state.resolve() or not path.name.startswith('prepared-'):
        raise ValueError('Prepared record is outside the helper state directory')
    prepared = json.loads(path.read_text())
    if not isinstance(prepared, dict):
        raise ValueError('Prepared record must be a JSON object')
    if prepared.get('repo') != repo or (prepared.get('base'), prepared.get('head')) != (args.base, args.head):
        raise ValueError('Prepared record belongs to another release')
    snap = snapshot(args.base, args.head)
    if any(prepared.get(key) != value for key, value in snap.items()):
        raise ValueError('Release changed; keep recovery data and prepare again')
    url = args.pr_url or prepared.get('url')
    if not url or prepared.get('url') not in (None, url):
        raise ValueError('Supply the actual PR URL for this prepared update')
    actual = read_pr(repo, url)
    if not validate_pr(actual, snap) or actual['body'] != prepared['body'] or actual['title'] != prepared['title']:
        raise ValueError('Published body or head differs; recovery data was retained')
    if prepared.get('evidence'):
        validate_review_source(repo, actual, snap, prepared['evidence'])
    cleanup_prepared(state, path)
    return dict(action='confirmed', number=actual['number'], url=actual['url'], cleanup='complete', **snap)


def publish(args, repo, state):
    review = json.loads(Path(args.review_record).read_text()) if args.review_record else None
    if review is not None and not isinstance(review, dict):
        raise ValueError('Review record must be a JSON object')
    report = Path(args.review_summary).read_bytes().decode('utf-8') if args.review_summary else None
    for attempt in range(2):
        snap = snapshot(args.base, args.head)
        if git('rev-list', '--count', snap['base_sha']+'..'+snap['head_sha']) == '0':
            if review:
                raise ValueError('Cannot publish review: no releasable changes remain')
            return dict(action='no-changes', **snap)
        found = gh('pr', 'list', '--repo', repo, '--state', 'open', '--base', args.base, '--head', args.head, '--json', 'number,url,isCrossRepository', '--limit', '100')
        if len(found) >= 100:
            raise ValueError('PR search reached its limit; inspect matching PRs before publishing')
        found = [pr for pr in found if not pr.get('isCrossRepository')]
        if len(found) > 1:
            raise ValueError('Multiple open PRs match this branch pair')
        pr = read_pr(repo, found[0]['number']) if found else None
        if pr and not validate_pr(pr, snap):
            continue
        if review is not None:
            if not pr:
                raise ValueError('Create the release PR before publishing its review')
            validate_review_source(repo, pr, snap, review)
        generated = render_list(args.base, args.head, snap, records(snap))
        updated, status, migrated = splice(pr['body'] if pr else '', generated, snap,
                                           review=review, report=report, append_managed=args.append_managed)
        prefix = args.base[:1].upper()+args.base[1:]+' Release '
        title = prefix+datetime.now().strftime('%Y/%m/%d')
        if pr and not re.fullmatch(re.escape(prefix)+r'\d{4}/\d{2}/\d{2}', pr['title']):
            title = pr['title']
        result = dict(number=pr['number'] if pr else None, url=pr['url'] if pr else None,
                      repo=repo, body_review_claim=status, migrated=migrated, **snap)
        changed = not pr or updated != pr['body'] or title != pr['title']
        result['action'] = 'created' if not pr else ('updated' if changed else 'unchanged')
        if args.dry_run:
            return save_prepared(state, result, pr, title, updated, review)
        if snapshot(args.base, args.head) != snap:
            continue
        if pr and read_pr(repo, pr['number']) != pr:
            continue
        if not changed:
            return dict(result, cleanup='not-needed')
        prepared = save_prepared(state, result, pr, title, updated, review)
        path = Path(prepared['prepared_record'])
        candidate = path.with_suffix('.body.md')
        write_text(candidate, updated)
        # Keep recovery files on any publication/read-back failure.
        try:
            if pr:
                command('gh', 'pr', 'edit', str(pr['number']), '--repo', repo, '--title', title, '--body-file', str(candidate))
                url = pr['url']
            else:
                url = command('gh', 'pr', 'create', '--repo', repo, '--base', args.base, '--head', args.head, '--title', title, '--body-file', str(candidate)).strip()
            actual = read_pr(repo, url)
        except (OSError, ValueError, subprocess.CalledProcessError):
            print('Recovery data retained at '+str(path), file=sys.stderr)
            raise
        result.update(number=actual['number'], url=actual['url'])
        try:
            result['snapshot_current'] = validate_pr(actual, snap)
        except ValueError:
            result['snapshot_current'] = False
        result['body_confirmed'] = actual['body'] == updated and actual['title'] == title
        if result['snapshot_current'] and result['body_confirmed'] and review:
            try:
                validate_review_source(repo, actual, snap, review)
                result['source_confirmed'] = True
            except (ValueError, OSError, subprocess.CalledProcessError):
                result['source_confirmed'] = False
        if all(result.get(key, True) for key in ('snapshot_current', 'body_confirmed', 'source_confirmed')):
            cleanup_prepared(state, path)
            result['cleanup'] = 'complete'
        else:
            result.update(cleanup='retained', prepared_record=str(path), backup=prepared.get('backup'))
        return result
    raise ValueError('PR body or branch tips changed repeatedly; no update published')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('base')
    parser.add_argument('head')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--append-managed', action='store_true', help='Use only after approval to append to an unmanaged body')
    parser.add_argument('--review-record')
    parser.add_argument('--review-summary')
    parser.add_argument('--confirm-prepared')
    parser.add_argument('--pr-url')
    args = parser.parse_args()
    if bool(args.review_record) != bool(args.review_summary):
        parser.error('--review-record and --review-summary must be supplied together')
    if args.confirm_prepared and (args.dry_run or args.review_record or args.append_managed):
        parser.error('--confirm-prepared cannot be combined with publication options')
    if args.pr_url and not args.confirm_prepared:
        parser.error('--pr-url requires --confirm-prepared')
    try:
        git('rev-parse', '--show-toplevel')
        root = Path(git('rev-parse', '--path-format=absolute', '--git-common-dir')).parent
        info = gh('repo', 'view', '--json', 'nameWithOwner,url')
        if remote_identity(git('remote', 'get-url', 'origin')) != remote_identity(info['url']):
            raise ValueError('GitHub repository does not match origin')
        repo = info['nameWithOwner']
        identity = hashlib.sha256(repo.encode()).hexdigest()[:16]
        state = root/'.agents/state/github-release-pr'/identity
        state.mkdir(parents=True, exist_ok=True)
        lock = hashlib.sha256((args.base+'\0'+args.head).encode()).hexdigest()[:16]+'.lock'
        with local_lock(state/lock):
            result = confirm_prepared(args, repo, state) if args.confirm_prepared else publish(args, repo, state)
        print(json.dumps(result, ensure_ascii=False))
        return 0 if all(result.get(key, True) for key in ('snapshot_current', 'body_confirmed', 'source_confirmed')) else 1
    except (BodyConflict, ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        detail = error.stderr if isinstance(error, subprocess.CalledProcessError) else str(error)
        print('Release PR stopped: '+str(detail).strip(), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
