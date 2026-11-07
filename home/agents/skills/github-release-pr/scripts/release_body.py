"""Render and splice owned release sections without rewriting surrounding prose."""
import html
import json
import re


class BodyConflict(ValueError):
    pass


def marker(kind, edge):
    return f'<!-- github-release-pr:{kind}:{edge} -->'


def block(kind, snapshot, content):
    metadata = json.dumps(snapshot, sort_keys=True).replace('<', r'\u003c').replace('>', r'\u003e')
    return f'{marker(kind, "begin")}\n<!-- release-snapshot {metadata} -->\n{content}\n{marker(kind, "end")}'


def sections(body):
    tokens = list(re.finditer(r'<!-- github-release-pr:(list|review):(begin|end) -->', body))
    if body.count('<!-- github-release-pr:') != len(tokens):
        raise BodyConflict('Unrecognized or malformed release marker')
    spans = {}
    opened = None
    for token in tokens:
        kind, edge = token.groups()
        if edge == 'begin':
            if opened or kind in spans:
                raise BodyConflict('Duplicate or nested release marker')
            opened = (kind, token.start())
        else:
            if not opened or opened[0] != kind:
                raise BodyConflict('Unmatched release marker')
            start = opened[1]
            spans[kind] = (start, token.end())
            opened = None
    if opened:
        raise BodyConflict('Unclosed release marker')
    if spans and 'list' not in spans:
        raise BodyConflict('Review marker has no release list')
    return spans


def metadata(body, span):
    content = body[slice(*span)]
    matches = re.findall(r'^<!-- release-snapshot (.+) -->\r?$', content, re.MULTILINE)
    if len(matches) != 1:
        raise BodyConflict('Missing or duplicate snapshot metadata')
    try:
        data = json.loads(matches[0])
    except json.JSONDecodeError as error:
        raise BodyConflict('Invalid snapshot metadata') from error
    if not isinstance(data, dict):
        raise BodyConflict('Snapshot must be an object')
    return data


def render_list(base, head, snapshot, records):
    lines = [f'## Merge commits ({base}..{head})', '']
    release_title = re.compile(r'\S+ Release \d{4}/\d{2}/\d{2}')
    for subject, author, description in records:
        if not re.fullmatch(r'Merge pull request #[0-9]+ from .+', subject):
            continue
        title = next((line.strip() for line in description.splitlines() if line.strip()), '')
        if release_title.fullmatch(title):
            continue
        entry = f'{html.escape(subject)}  (Author: {html.escape(author)})'
        if title:
            entry += ' — ' + html.escape(title)
        lines.append(entry)
    if len(lines) == 2:
        lines.append('(no matching merge commits)')
    return block('list', snapshot, '\n'.join(lines))


def review_status(data, snapshot):
    if data.get('head_sha') != snapshot['head_sha'] or data.get('merge_base') != snapshot['merge_base']:
        return 'stale'
    if data.get('outcome') not in ('pass', 'notes', 'blocking'):
        return 'pending'
    if data.get('base_sha') != snapshot['base_sha']:
        return 'base-advanced'
    return data['outcome']


def splice(body, new_list, snapshot, *, review=None, report=None, append_managed=False):
    spans = sections(body)
    migrated = False
    if not spans:
        # Only the recognisable output of the previous generator can be migrated.
        header = re.search(r'^## Merge commits \(' + re.escape(snapshot['base'] + '..' + snapshot['head']) + r'\)\r?\n', body, re.MULTILINE)
        if header:
            end = header.end()
            for line in body[end:].splitlines(keepends=True):
                if not line.strip() or re.fullmatch(r'Merge pull request #[0-9]+ from .*  \(Author: [^()]*\)\r?\n?', line):
                    end += len(line)
                else:
                    break
            body = body[:header.start()] + new_list + '\n\n' + body[end:]
            # Do not delete unknown text after a legacy review heading.
            headings = list(re.finditer(r'^## Agent Review\r?$', body, re.MULTILINE))
            if headings:
                last = headings[-1]
                body = body[:last.start()] + '## Previous Agent Review (unverified)' + body[last.end():]
            migrated = True
        elif body.strip() and not append_managed:
            raise BodyConflict('Unmanaged body: confirm appending managed sections first')
        else:
            body += ('\n\n' if body else '') + new_list
        spans = sections(body)
    else:
        old = metadata(body, spans['list'])
        if (old.get('base'), old.get('head')) != (snapshot['base'], snapshot['head']):
            raise BodyConflict('Managed sections belong to a different branch pair')
        start, end = spans['list']
        body = body[:start] + new_list + body[end:]
        spans = sections(body)

    if review is not None:
        for key in ('head_sha', 'base_sha', 'merge_base'):
            if review.get(key) != snapshot[key]:
                raise BodyConflict('Review does not cover the current ' + key)
        if review.get('outcome') not in ('pass', 'notes', 'blocking') or not review.get('reviewer') or not review.get('source'):
            raise BodyConflict('Review needs reviewer, source, and a supported outcome')
        if review.get('independent') is not True or review.get('scope') != 'release-integration':
            raise BodyConflict('Review must independently cover release integration')
        if not isinstance(report, str) or not report.strip():
            raise BodyConflict('Review report is empty')
        if len(report) > 1200 or len(report.splitlines()) > 12:
            raise BodyConflict('Use a brief summary (1200 characters / 12 lines); publish details in the GitHub review')
        if '<!-- github-release-pr:' in report or '<!-- release-snapshot ' in report:
            raise BodyConflict('Review report contains reserved section markers')
        replacement = block('review', dict(snapshot, **{k: review[k] for k in ('outcome', 'reviewer', 'source', 'scope', 'independent')}), '## Agent Review\n\n' + report + '\n\n[Detailed review](' + review['source'] + ')')
        status = review['outcome']
    elif 'review' in spans:
        data = metadata(body, spans['review'])
        status = review_status(data, snapshot)
        if status != 'stale':
            return body, status, migrated
        replacement = block('review', dict(snapshot, outcome='pending'), '## Agent Review\n\nPrevious review is stale; independent review pending for ' + snapshot['head_sha'] + '.')
        status = 'pending'
    else:
        replacement = block('review', dict(snapshot, outcome='pending'), '## Agent Review\n\nIndependent review pending for ' + snapshot['head_sha'] + '.')
        status = 'pending'
    if 'review' in spans:
        start, end = spans['review']
        body = body[:start] + replacement + body[end:]
    else:
        body += '\n\n' + replacement
    return body, status, migrated
