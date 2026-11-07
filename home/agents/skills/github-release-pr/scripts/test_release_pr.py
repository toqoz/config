"""Local git integration tests; all GitHub operations use a file-backed fake gh."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('create-release-pr')
FAKE_GH = r'''#!/usr/bin/env python3
import json,os,subprocess,sys
from pathlib import Path
p=Path(os.environ['FAKE_GH_STATE']);s=json.loads(p.read_text());a=sys.argv[1:]
s.setdefault('calls',[]).append(a);p.write_text(json.dumps(s))
def opt(name,default=None):
 return a[a.index(name)+1] if name in a else default
def oid(branch):
 return subprocess.check_output(['git','rev-parse','refs/remotes/origin/'+branch],text=True).strip()
def body():
 return Path(opt('--body-file')).read_bytes().decode() if '--body-file' in a else opt('--body','')
if a[:2]==['repo','view']:
 out={'nameWithOwner':'test/repo','url':s['origin']}
elif a[:2]==['pr','list']:
 out=s.get('prs',[])
elif a[:2]==['pr','create']:
 pr={'number':1,'url':'https://github.invalid/test/repo/pull/1','title':opt('--title'),'body':body(),'baseRefName':opt('--base'),'headRefName':opt('--head'),'baseRefOid':oid(opt('--base')),'headRefOid':oid(opt('--head')),'state':'OPEN','isDraft':False,'isCrossRepository':False}
 pr['number']=max([x['number'] for x in s.get('prs',[])]+[0])+1
 pr['url']='https://github.invalid/test/repo/pull/'+str(pr['number'])
 s.setdefault('prs',[]).append(pr);out=pr['url']
elif a[:2]==['pr','view']:
 s['views']=s.get('views',0)+1;pr=next(x for x in s['prs'] if a[2] in (str(x['number']),x['url']))
 if not s.get('freeze_oids'): pr['headRefOid']=oid(pr['headRefName'])
 if not s.get('freeze_oids') and not s.get('freeze_base'): pr['baseRefOid']=oid(pr['baseRefName'])
 pr.update(s.get('view_changes',{}).get(str(s['views']),{}));out=pr
elif a and a[0]=='api':
 s['review_reads']=s.get('review_reads',0)+1
 out=s['reviews'][a[1].split('/')[-1]]
 out.update(s.get('review_changes',{}).get(str(s['review_reads']),{}))
elif a[:2]==['pr','edit']:
 pr=next(x for x in s['prs'] if a[2] in (str(x['number']),x['url']))
 if '--body-file' in a or '--body' in a: pr['body']=body()
 if '--title' in a: pr['title']=opt('--title')
 out=''
else:
 raise SystemExit('Unexpected gh command: '+str(a))
p.write_text(json.dumps(s));print(json.dumps(out) if not isinstance(out,str) else out)
'''

class ReleasePRTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        self.origin = self.root / 'origin.git'
        subprocess.run(['git', 'init', '--bare', '-q', str(self.origin)], check=True)
        self.git('init', '-q', '-b', 'main')
        self.git('config', 'user.name', 'Test Author')
        self.git('config', 'user.email', 'test@example.invalid')
        self.git('config', 'commit.gpgsign', 'false')
        self.commit('base', 'Initial')
        self.git('branch', 'dev')
        self.git('remote', 'add', 'origin', str(self.origin))
        self.merge_pr(1, 'Add export')
        self.git('push', '-q', 'origin', 'main', 'dev')
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        gh = self.bin / 'gh'
        gh.write_text(FAKE_GH)
        gh.chmod(0o755)
        self.state = self.root / 'gh.json'
        self.state.write_text(json.dumps({'origin': str(self.origin), 'prs': []}))
        self.env = dict(os.environ, PATH=str(self.bin)+os.pathsep+os.environ['PATH'], FAKE_GH_STATE=str(self.state), GH_HOST='github.invalid', GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1')

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.repo, stderr=subprocess.DEVNULL, text=True).strip()

    def commit(self, filename, message):
        (self.repo / filename).write_text(message)
        self.git('add', '--', filename)
        self.git('commit', '-qm', message)

    def merge_pr(self, number, title):
        branch = 'feature-'+str(number)
        self.git('checkout', '-qb', branch)
        self.commit(branch, 'Implement '+title)
        self.git('checkout', '-q', 'main')
        self.git('merge', '-q', '--no-ff', branch, '-m', f'Merge pull request #{number} from test/{branch}', '-m', title)

    def run_script(self, *args, ok=True, cwd=None):
        result = subprocess.run(['bash', str(SCRIPT), *args], cwd=cwd or self.repo, env=self.env, text=True, capture_output=True)
        if ok:
            self.assertEqual(result.returncode, 0, result.stderr+result.stdout)
            return json.loads(result.stdout)
        return result

    def db(self):
        return json.loads(self.state.read_text())

    def set_pr(self, body, title='Dev Release 2026/01/01'):
        self.git('fetch', '-q', 'origin')
        db = self.db()
        db['prs'] = [dict(number=1, url='https://github.invalid/test/repo/pull/1', body=body, title=title, state='OPEN', isDraft=False, isCrossRepository=False, baseRefName='dev', headRefName='main', baseRefOid=self.git('rev-parse', 'origin/dev'), headRefOid=self.git('rev-parse', 'origin/main'))]
        self.state.write_text(json.dumps(db))

    def writes(self):
        return [x for x in self.db().get('calls', []) if x[:2] in [['pr','create'], ['pr','edit']]]

    def test_regular_title_containing_release_name_is_not_excluded(self):
        self.merge_pr(2, 'Update Main Release checklist docs')
        self.git('push', '-q', 'origin', 'main')
        self.run_script('dev', 'main')
        self.assertIn('#2', self.db()['prs'][0]['body'])

    def test_missing_branch_never_writes_a_pr(self):
        result = self.run_script('missing', 'main', ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.writes(), [])

    def test_refresh_preserves_handwritten_notes(self):
        self.set_pr('## Merge commits (dev..main)\n\nMerge pull request #1 from test/feature-1  (Author: Test Author)\n\n## Deploy notes\n\nKeep this exact note.\n')
        self.run_script('dev', 'main')
        self.assertIn('## Deploy notes\n\nKeep this exact note.\n', self.db()['prs'][0]['body'])

    def test_git_log_failure_does_not_replace_existing_body(self):
        import shutil
        self.set_pr('## Merge commits (dev..main)\n\nKeep this note.\n')
        real_git = shutil.which('git')
        proxy = self.bin / 'git'
        proxy.write_text('#!/usr/bin/env python3\nimport os,sys\n'
                         + 'if sys.argv[1] == "log": raise SystemExit(71)\n'
                         + 'os.execv(' + repr(real_git) + ', ["git", *sys.argv[1:]])\n')
        proxy.chmod(0o755)
        result = self.run_script('dev', 'main', ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.writes(), [])
        self.assertIn('Keep this note.', self.db()['prs'][0]['body'])

    def test_missing_review_provenance_is_rejected(self):
        record, report = self.prepare_review()
        data = json.loads(record.read_text()); data.pop('source')
        record.write_text(json.dumps(data))
        count = len(self.writes())
        result = self.run_script('dev', 'main', '--review-record', str(record), '--review-summary', str(report), ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(count, len(self.writes()))

    def test_reserved_marker_in_review_is_rejected(self):
        record, report = self.prepare_review()
        report.write_text('<!-- release-snapshot {} -->')
        count = len(self.writes())
        result = self.run_script('dev', 'main', '--review-record', str(record), '--review-summary', str(report), ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(count, len(self.writes()))

    def test_crlf_inside_managed_blocks_can_be_refreshed(self):
        self.run_script('dev', 'main')
        db = self.db()
        db['prs'][0]['body'] = db['prs'][0]['body'].replace('\n', '\r\n')+'\r\n手書きの注記\r\n'
        self.state.write_text(json.dumps(db))
        self.run_script('dev', 'main')
        self.assertTrue(self.db()['prs'][0]['body'].endswith('\r\n手書きの注記\r\n'))

    def test_stale_pr_base_oid_uses_fetched_base(self):
        self.set_pr('')
        db = self.db(); db['freeze_base'] = True
        old_base = db['prs'][0]['baseRefOid']
        self.state.write_text(json.dumps(db))
        self.git('checkout', '-q', 'dev')
        self.commit('base-update', 'Base branch update')
        self.git('push', '-q', 'origin', 'dev')
        result = self.run_script('dev', 'main')
        self.assertNotEqual(result['base_sha'], old_base)
        self.assertEqual(result['base_sha'], self.git('rev-parse', 'origin/dev'))
        self.assertTrue(result['snapshot_current'])

    def test_body_claim_is_not_a_verified_review_result(self):
        self.run_script('dev', 'main')
        db = self.db()
        db['prs'][0]['body'] = db['prs'][0]['body'].replace('"outcome": "pending"', '"outcome": "pass"')
        self.state.write_text(json.dumps(db))
        result = self.run_script('dev', 'main')
        self.assertNotIn('review', result)
        self.assertEqual(result['body_review_claim'], 'pass')

    def test_dry_run_backs_up_body_without_github_writes(self):
        old = '## Merge commits (dev..main)\n\nKeep this note.\n'
        self.set_pr(old)
        result = self.run_script('dev', 'main', '--dry-run')
        self.assertEqual(Path(result['backup']).read_bytes().decode(), old)
        self.assertEqual(self.writes(), [])

    def test_dry_run_preserves_unpublished_review_evidence(self):
        record, report = self.prepare_review()
        count = len(self.writes())
        result = self.run_script('dev', 'main', '--dry-run', '--review-record', str(record), '--review-summary', str(report))
        saved = json.loads(Path(result['prepared_record']).read_text())
        self.assertEqual(saved['evidence']['source'], json.loads(record.read_text())['source'])
        self.assertNotIn('report', saved['evidence'])
        self.assertTrue(saved['dry_run'])
        self.assertNotIn('body_confirmed', saved)
        self.assertEqual(count, len(self.writes()))

    def test_state_survives_owned_worktree_cleanup(self):
        record, report = self.prepare_review()
        worktree = self.root / 'review-worktree'
        self.git('worktree', 'add', '--detach', str(worktree), 'main')
        db = self.db(); db['views'] = 0
        db['view_changes'] = {'3': {'body': 'Concurrent edit after publication.'}}
        self.state.write_text(json.dumps(db))
        response = self.run_script('dev', 'main', '--review-record', str(record), '--review-summary', str(report), cwd=worktree, ok=False)
        self.assertNotEqual(response.returncode, 0)
        path = Path(json.loads(response.stdout)['prepared_record'])
        self.assertTrue(path.resolve().is_relative_to((self.repo / '.agents/state').resolve()))
        self.git('worktree', 'remove', str(worktree))
        self.assertTrue(path.exists())

    def test_legacy_row_with_manual_annotation_is_not_removed(self):
        self.set_pr('## Merge commits (dev..main)\n\nMerge pull request #1 from test/feature-1  (Author: A) (QA verified)\n')
        self.run_script('dev', 'main')
        self.assertIn('(QA verified)', self.db()['prs'][0]['body'])

    def test_fork_pr_does_not_hide_same_repository_release(self):
        self.set_pr('Fork notes')
        db = self.db(); db['prs'][0].update(number=99, url='https://github.invalid/other/repo/pull/99', isCrossRepository=True)
        self.state.write_text(json.dumps(db))
        result = self.run_script('dev', 'main')
        self.assertEqual(result['action'], 'created')
        self.assertEqual(self.db()['prs'][0]['body'], 'Fork notes')
        self.assertFalse(self.db()['prs'][1]['isCrossRepository'])

    def test_non_object_review_record_stops_cleanly(self):
        record, report = self.prepare_review()
        record.write_text('[]')
        count = len(self.writes())
        result = self.run_script('dev', 'main', '--review-record', str(record), '--review-summary', str(report), ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('Traceback', result.stderr)
        self.assertEqual(count, len(self.writes()))

    def test_main_prod_and_production_releases_are_all_excluded(self):
        for number, title in enumerate(['Main Release 2026/11/01', 'Prod Release 2026/11/01', 'Production Release 2026/11/01'], start=2):
            self.merge_pr(number, title)
        self.git('push', '-q', 'origin', 'main')
        self.run_script('dev', 'main')
        body = self.db()['prs'][0]['body']
        self.assertIn('#1', body)
        for number in (2, 3, 4):
            self.assertNotIn('#'+str(number), body)

    def test_review_body_is_brief_and_links_to_github_details(self):
        record, report = self.prepare_review()
        result = self.run_script('dev', 'main', '--review-record', str(record), '--review-summary', str(report))
        body = self.db()['prs'][0]['body']
        self.assertIn('[Detailed review]('+json.loads(record.read_text())['source']+')', body)
        self.assertNotIn('Detailed integration evidence only on GitHub.', body)
        self.assertEqual(result['cleanup'], 'complete')
        self.assertEqual(list((self.repo / '.agents/state/github-release-pr').rglob('prepared-*')), [])

    def test_confirming_host_publication_cleans_prepared_data(self):
        self.set_pr('## Merge commits (dev..main)\n\nImportant hand note.\n')
        prepared = self.run_script('dev', 'main', '--dry-run')
        db = self.db(); db['prs'][0].update(body=prepared['body'], title=prepared['title'])
        self.state.write_text(json.dumps(db))
        result = self.run_script('dev', 'main', '--confirm-prepared', prepared['prepared_record'])
        self.assertEqual(result['cleanup'], 'complete')
        self.assertFalse(Path(prepared['prepared_record']).exists())
        self.assertFalse(Path(prepared['backup']).exists())
        self.assertEqual(self.writes(), [])

    def test_confirming_new_host_pr_requires_and_accepts_actual_url(self):
        prepared = self.run_script('dev', 'main', '--dry-run')
        self.set_pr(prepared['body'], title=prepared['title'])
        result = self.run_script('dev', 'main', '--confirm-prepared', prepared['prepared_record'], '--pr-url', self.db()['prs'][0]['url'])
        self.assertEqual(result['action'], 'confirmed')
        self.assertFalse(Path(prepared['prepared_record']).exists())

    def test_unconfirmed_host_update_keeps_recovery_files(self):
        self.set_pr('## Merge commits (dev..main)\n\nKeep original notes.\n')
        prepared = self.run_script('dev', 'main', '--dry-run')
        result = self.run_script('dev', 'main', '--confirm-prepared', prepared['prepared_record'], ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(Path(prepared['prepared_record']).exists())
        self.assertTrue(Path(prepared['backup']).exists())
        self.assertEqual(self.writes(), [])

    def test_cleanup_does_not_touch_unowned_files(self):
        other = self.root / 'other.json'; other.write_text('{}')
        result = self.run_script('dev', 'main', '--confirm-prepared', str(other), ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(other.exists())

    def test_unpublished_github_review_is_rejected(self):
        record, report = self.prepare_review()
        db = self.db(); db['reviews']['7']['state'] = 'PENDING'
        self.state.write_text(json.dumps(db))
        count = len(self.writes())
        result = self.run_script('dev', 'main', '--review-record', str(record), '--review-summary', str(report), ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(count, len(self.writes()))

    def test_github_review_comparison_mismatch_is_rejected(self):
        record, report = self.prepare_review()
        db = self.db(); db['reviews']['7']['body'] = db['reviews']['7']['body'].replace(json.loads(record.read_text())['base_sha'], '0'*40)
        self.state.write_text(json.dumps(db))
        count = len(self.writes())
        result = self.run_script('dev', 'main', '--review-record', str(record), '--review-summary', str(report), ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(count, len(self.writes()))

    def test_long_report_must_be_summarized_before_body_publication(self):
        record, report = self.prepare_review()
        report.write_text('a'*1201)
        count = len(self.writes())
        result = self.run_script('dev', 'main', '--review-record', str(record), '--review-summary', str(report), ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(count, len(self.writes()))

    def test_review_source_is_rechecked_before_cleanup(self):
        record, report = self.prepare_review()
        db = self.db(); db['review_changes'] = {'2': {'state': 'DISMISSED'}}
        self.state.write_text(json.dumps(db))
        result = self.run_script('dev', 'main', '--review-record', str(record), '--review-summary', str(report), ok=False)
        self.assertNotEqual(result.returncode, 0)
        payload = json.loads(result.stdout)
        self.assertFalse(payload['source_confirmed'])
        self.assertEqual(payload['cleanup'], 'retained')
        self.assertTrue(Path(payload['prepared_record']).exists())

    def prepare_review(self):
        result = self.run_script('dev', 'main')
        record = dict(result, reviewer='independent-test', source=result['url']+'#pullrequestreview-7',
                      scope='release-integration', independent=True, outcome='pass')
        db = self.db()
        db['reviews'] = {'7': dict(html_url=record['source'], commit_id=result['head_sha'], state='COMMENTED', body='<!-- release-review-source '+json.dumps(record)+' -->\nDetailed integration evidence only on GitHub.')}
        self.state.write_text(json.dumps(db))
        path = self.root / 'review.json'
        path.write_text(json.dumps(record))
        report = self.root / 'review.md'
        report.write_text('Reviewed integration: no blocking findings.')
        return path, report

    def test_new_pr_contains_titles_and_only_merge_prs(self):
        self.commit('direct', 'Direct change')
        self.merge_pr(2, 'Main Release 2026/11/01')
        self.git('push', '-q', 'origin', 'main')
        result = self.run_script('dev', 'main')
        body = self.db()['prs'][0]['body']
        self.assertEqual(result['action'], 'created')
        self.assertIn('Add export', body)
        self.assertNotIn('Direct change', body)
        self.assertNotIn('#2', body)
        self.assertIn('Independent review pending', body)

    def test_repeating_refresh_does_not_edit(self):
        self.run_script('dev', 'main')
        count = len(self.writes())
        result = self.run_script('dev', 'main')
        self.assertEqual(result['action'], 'unchanged')
        self.assertEqual(len(self.writes()), count)

    def test_custom_title_and_text_outside_markers_survive(self):
        self.run_script('dev', 'main')
        db = self.db()
        old = db['prs'][0]['body']
        db['prs'][0].update(title='Manual release name', body='手書き\r\n\r\n'+old+'\r\nKeep tail exactly.\r\n')
        self.state.write_text(json.dumps(db))
        self.commit('new', 'Another direct change')
        self.git('push', '-q', 'origin', 'main')
        self.run_script('dev', 'main')
        pr = self.db()['prs'][0]
        self.assertEqual(pr['title'], 'Manual release name')
        self.assertTrue(pr['body'].startswith('手書き\r\n\r\n'))
        self.assertTrue(pr['body'].endswith('\r\nKeep tail exactly.\r\n'))

    def test_legacy_notes_survive_and_successful_update_cleans_backup(self):
        old = '## Merge commits (dev..main)\n\nMerge pull request #1 from test/feature-1  (Author: Test Author)\n\n## Agent Review\nOld result\n\nHuman addition after review.\n'
        self.set_pr(old)
        result = self.run_script('dev', 'main')
        body = self.db()['prs'][0]['body']
        self.assertIn('Previous Agent Review (unverified)', body)
        self.assertIn('Old result\n\nHuman addition after review.\n', body)
        self.assertEqual(result['cleanup'], 'complete')
        self.assertEqual(list((self.repo / '.agents/state/github-release-pr').rglob('*.md')), [])

    def test_unknown_body_requires_approval(self):
        self.set_pr('My hand-written release notes.\n')
        result = self.run_script('dev', 'main', ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.writes(), [])
        self.assertEqual(self.db()['prs'][0]['body'], 'My hand-written release notes.\n')

    def test_approved_append_preserves_unknown_body(self):
        self.set_pr('My release notes.\n')
        self.run_script('dev', 'main', '--append-managed')
        self.assertTrue(self.db()['prs'][0]['body'].startswith('My release notes.\n'))

    def test_no_ahead_commits_means_no_pr(self):
        self.git('branch', 'same', 'dev')
        self.git('push', '-q', 'origin', 'same')
        result = self.run_script('dev', 'same')
        self.assertEqual(result['action'], 'no-changes')
        self.assertEqual(self.writes(), [])

    def test_direct_commits_only_have_explicit_empty_merge_list(self):
        self.git('checkout', '-qb', 'direct', 'dev')
        self.commit('change', 'Direct commit')
        self.git('push', '-q', 'origin', 'direct')
        self.run_script('dev', 'direct')
        self.assertIn('(no matching merge commits)', self.db()['prs'][0]['body'])

    def test_dry_run_never_publishes(self):
        result = self.run_script('dev', 'main', '--dry-run')
        self.assertTrue(result['dry_run'])
        self.assertIn('Add export', result['body'])
        self.assertEqual(self.writes(), [])

    def test_multiple_open_prs_stop(self):
        self.set_pr('')
        db = self.db()
        db['prs'].append(dict(db['prs'][0], number=2))
        self.state.write_text(json.dumps(db))
        result = self.run_script('dev', 'main', ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.writes(), [])

    def test_draft_pr_is_not_modified(self):
        self.set_pr('')
        db = self.db(); db['prs'][0]['isDraft'] = True
        self.state.write_text(json.dumps(db))
        result = self.run_script('dev', 'main', ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.writes(), [])

    def test_review_published_once_and_preserved_on_refresh(self):
        record, report = self.prepare_review()
        result = self.run_script('dev', 'main', '--review-record', str(record), '--review-summary', str(report))
        self.assertEqual(result['body_review_claim'], 'pass')
        body = self.db()['prs'][0]['body']
        count = len(self.writes())
        refreshed = self.run_script('dev', 'main')
        self.assertEqual(refreshed['body_review_claim'], 'pass')
        self.assertEqual(body, self.db()['prs'][0]['body'])
        self.assertEqual(count, len(self.writes()))
        self.assertEqual(body.count('## Agent Review'), 1)

    def test_review_of_another_head_is_rejected(self):
        record, report = self.prepare_review()
        data = json.loads(record.read_text()); data['head_sha'] = '0'*40
        record.write_text(json.dumps(data))
        count = len(self.writes())
        result = self.run_script('dev', 'main', '--review-record', str(record), '--review-summary', str(report), ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(count, len(self.writes()))

    def test_new_head_invalidates_review(self):
        record, report = self.prepare_review()
        self.run_script('dev', 'main', '--review-record', str(record), '--review-summary', str(report))
        self.commit('later', 'Later change')
        self.git('push', '-q', 'origin', 'main')
        result = self.run_script('dev', 'main')
        self.assertEqual(result['body_review_claim'], 'pending')
        self.assertNotIn(report.read_text(), self.db()['prs'][0]['body'])
        self.assertIn('Detailed integration evidence', self.db()['reviews']['7']['body'])
        self.assertEqual(list((self.repo / '.agents/state/github-release-pr').rglob('prepared-*.json')), [])

    def test_base_advance_requires_integration_assessment(self):
        record, report = self.prepare_review()
        self.run_script('dev', 'main', '--review-record', str(record), '--review-summary', str(report))
        self.git('checkout', '-q', 'dev')
        self.commit('base-change', 'Base progressed')
        self.git('push', '-q', 'origin', 'dev')
        result = self.run_script('dev', 'main')
        self.assertEqual(result['body_review_claim'], 'base-advanced')
        self.assertIn(report.read_text(), self.db()['prs'][0]['body'])

    def test_body_edit_during_refresh_is_preserved(self):
        self.run_script('dev', 'main')
        db = self.db(); old = db['prs'][0]['body']; db['calls'] = []; db['views'] = 0
        db['view_changes'] = {'2': {'body': old+'\nConcurrent note.\n'}}
        self.state.write_text(json.dumps(db))
        self.run_script('dev', 'main')
        self.assertTrue(self.db()['prs'][0]['body'].endswith('\nConcurrent note.\n'))

    def test_repeated_concurrent_edits_stop_without_writing(self):
        self.run_script('dev', 'main')
        db = self.db(); old = db['prs'][0]['body']; db['calls'] = []; db['views'] = 0
        db['view_changes'] = {'2': {'body': old+'\nFirst edit.'}, '4': {'body': old+'\nSecond edit.'}}
        self.state.write_text(json.dumps(db))
        result = self.run_script('dev', 'main', ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.writes(), [])
        self.assertTrue(self.db()['prs'][0]['body'].endswith('Second edit.'))

    def test_remote_head_mismatch_stops_without_writing(self):
        self.set_pr('')
        db = self.db(); db['prs'][0]['headRefOid'] = '0'*40; db['freeze_oids'] = True
        self.state.write_text(json.dumps(db))
        result = self.run_script('dev', 'main', ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.writes(), [])

    def test_body_change_after_publication_is_reported(self):
        self.run_script('dev', 'main')
        db = self.db(); db['calls'] = []; db['views'] = 0
        db['prs'][0]['title'] = 'Dev Release 2000/01/01'
        db['view_changes'] = {'3': {'body': 'A newer user edit.'}}
        self.state.write_text(json.dumps(db))
        result = self.run_script('dev', 'main', ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(json.loads(result.stdout)['body_confirmed'])
        self.assertEqual(self.db()['prs'][0]['body'], 'A newer user edit.')


class BodyTests(unittest.TestCase):
    def setUp(self):
        self.snap = dict(base='dev', head='release/1.0', base_sha='b', head_sha='h', merge_base='m')

    def test_release_filter_recognizes_any_single_token_release_name(self):
        from release_body import render_list
        body = render_list('dev', 'release/1.0', self.snap, [
            ('Merge pull request #1 from x/a', 'A', 'Update Release/1x0 Release checklist'),
            ('Merge pull request #2 from x/b', 'A', 'Release/1.0 Release 2026/01/01'),
            ('Merge branch main', 'A', 'Normal merge'),
        ])
        self.assertIn('#1', body)
        self.assertNotIn('#2', body)
        self.assertNotIn('Normal merge', body)

    def test_multiline_commit_body_does_not_add_phantom_entries(self):
        from release_body import render_list
        body = render_list('dev', 'main', self.snap, [('Merge pull request #3 from x/a', 'A', 'Real title\n\nMerge pull request #999 in prose')])
        self.assertIn('Real title', body)
        self.assertNotIn('#999', body)

    def test_broken_or_nested_markers_are_rejected(self):
        from release_body import BodyConflict, marker, splice
        for body in (marker('list','begin'), marker('list','end'), marker('list','begin')+marker('review','begin')+marker('review','end')+marker('list','end')):
            with self.subTest(body=body), self.assertRaises(BodyConflict):
                splice(body, '', self.snap)

    def test_duplicate_markers_are_rejected(self):
        from release_body import BodyConflict, block, splice
        body = block('list', self.snap, 'list')
        with self.assertRaises(BodyConflict):
            splice(body+body, body, self.snap)


if __name__ == '__main__':
    unittest.main()
