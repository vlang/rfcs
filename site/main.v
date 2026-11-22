module main

import veb
import net.http
import os
import strings

const site_root = os.dir(@FILE)
const out_dir = os.join_path(site_root, 'dist')
const rfcs_dir = os.abs_path(os.join_path(site_root, '..', 'rfcs'))
const repo_root = os.abs_path(os.join_path(site_root, '..'))

const port = 8085

struct App {
	veb.StaticHandler
pub mut:
	rfcs      []Rfc
	base_path string
}

struct Context {
	veb.Context
}

struct Heading {
	level int
	title string
	id    string
}

struct Rfc {
	id         string
	slug       string
	title      string
	topic      string
	start_date string
	pr         string
	summary    string
	body_html  string
	source     string
	headings   []Heading
}

struct SearchEntry {
	id      string
	slug    string
	title   string
	summary string
	url     string
}

// index renders the RFC catalogue.
@['/']
fn (app &App) index(mut ctx Context) veb.Result {
	return ctx.html(app.render_index())
}

// rfc_detail renders a single RFC.
@['/rfc/:slug']
fn (app &App) rfc_detail(mut ctx Context, slug string) veb.Result {
	rfc := app.find_rfc(slug) or { return ctx.not_found() }
	return ctx.html(app.render_rfc(rfc))
}

// search_json exposes the client-side search index.
@['/search.json']
fn (app &App) search_json(mut ctx Context) veb.Result {
	ctx.res.header.set(.content_type, 'application/json')
	return ctx.text(app.search_json_text())
}

// not_found_page is reachable as /404 so the static export can write 404.html.
@['/404']
fn (mut ctx Context) not_found() veb.Result {
	ctx.res.set_status(.not_found)
	return ctx.html('<h1>Page not found</h1><p><a href="/">Back to RFC index</a></p>')
}

fn (app &App) find_rfc(slug string) ?Rfc {
	for r in app.rfcs {
		if r.slug == slug {
			return r
		}
	}
	return none
}

fn (app &App) search_json_text() string {
	entries := app.search_entries()
	mut b := strings.new_builder(2048)
	b.write_u8(`[`)
	for i, e in entries {
		if i > 0 {
			b.write_u8(`,`)
		}
		b.write_string('{"id":"' + json_escape(e.id) + '","slug":"' +
			json_escape(e.slug) + '","title":"' + json_escape(e.title) + '","summary":"' +
			json_escape(e.summary) + '","url":"' + json_escape(e.url) + '"}')
	}
	b.write_u8(`]`)
	return b.str()
}

// json_escape renders a string as a JSON string body (without quotes).
// Summaries are single-line prose, so only quotes, backslashes and common
// whitespace need escaping; other bytes pass through as UTF-8.
fn json_escape(s string) string {
	mut b := strings.new_builder(s.len + 2)
	for ch in s {
		match ch {
			`"` { b.write_string('\\"') }
			`\\` { b.write_string('\\\\') }
			`\n` { b.write_string('\\n') }
			`\r` { b.write_string('\\r') }
			`\t` { b.write_string('\\t') }
			else { b.write_u8(ch) }
		}
	}
	return b.str()
}

fn (app &App) search_entries() []SearchEntry {
	mut out := []SearchEntry{}
	for r in app.rfcs {
		out << SearchEntry{
			id:      r.id
			slug:    r.slug
			title:   r.title
			summary: r.summary
			url:     '${app.base_path}/rfc/${r.slug}/'
		}
	}
	return out
}

const external_icon = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M7 17 17 7M8 7h9v9"/></svg>'

// pr_number pulls the pull request id out of a GitHub PR URL. RFC templates use
// 00000 as a placeholder, which is returned as '' so the client skips it.
fn pr_number(url string) string {
	marker := '/pull/'
	i := url.index(marker) or { return '' }
	tail := url[i + marker.len..]
	mut n := ''
	for ch in tail {
		if ch < `0` || ch > `9` {
			break
		}
		n += ch.ascii_str()
	}
	if n == '' || n == '0' || n == '0000' || n == '00000' {
		return ''
	}
	return n.trim_left('0')
}

fn (app &App) render_index() string {
	mut cards := strings.new_builder(8192)
	for r in app.rfcs {
		num := if r.id == '' { 'Draft' } else { 'RFC ${r.id}' }
		topic := if r.topic == '' { 'proposal' } else { r.topic }
		pr_num := pr_number(r.pr)
		cards.write_string('<article class="rfc-card" data-search="${escape_html(r.title + ' ' + r.slug + ' ' + r.summary + ' ' + r.topic)}"')
		cards.write_string(' data-id="${escape_html(r.id)}" data-date="${escape_html(r.start_date)}"')
		cards.write_string(' data-title="${escape_html(r.title.to_lower())}" data-pr="${pr_num}">\n')
		cards.write_string('<div class="card-top"><span class="rfc-num">${escape_html(num)}</span>')
		cards.write_string('<span class="rfc-topic">${escape_html(topic)}</span></div>\n')
		cards.write_string('<h3><a href="${app.base_path}/rfc/${r.slug}/">${escape_html(r.title)}&nbsp;<span class="card-arrow" aria-hidden="true">→</span></a></h3>\n')
		if r.summary != '' {
			cards.write_string('<p class="rfc-summary">${escape_html(r.summary)}</p>\n')
		}
		cards.write_string('<div class="card-foot">')
		if r.start_date != '' {
			cards.write_string('<time>${escape_html(r.start_date)}</time>')
		} else {
			cards.write_string('<span>Open proposal</span>')
		}
		cards.write_string('<span class="card-foot-right">')
		if pr_num != '' {
			cards.write_string('<span class="creator" data-pr="${pr_num}"><span class="creator-avatar"></span><span class="creator-name">Loading author…</span></span>')
		}
		if r.pr != '' {
			cards.write_string('<a class="pr-link" href="${escape_html(r.pr)}">Discussion ${external_icon}</a>')
		}
		cards.write_string('</span></div></article>\n')
	}
	hero := '<section class="hero">\n' +
		'<p class="eyebrow">V language · design proposals</p>\n' +
		'<h1>V <span class="accent">RFCs</span></h1>\n' +
		'<p class="lead">Requests for Comments are how the V community proposes, debates and ' +
		'refines changes to the language and its standard library. ' +
		'<a href="https://github.com/vlang/rfcs#rfc-proposal-process">Read the process</a> or ' +
		'<a href="https://github.com/vlang/rfcs">contribute on GitHub</a>.</p>\n' +
		'<div class="search-wrap">\n' +
		'<svg class="search-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>\n' +
		'<input id="rfc-search" type="search" placeholder="Search proposals, topics, titles…" aria-label="Search RFCs" autocomplete="off" spellcheck="false" />\n' +
		'<kbd class="search-kbd" aria-hidden="true">/</kbd>\n' +
		'</div>\n' +
		'<div class="hero-stats"><span><strong>${app.rfcs.len}</strong> documents</span>' +
		'<span class="sep">·</span><span>open to discussion</span>' +
		'<span class="sep">·</span><span>maintained by the V community</span></div>\n' +
		'</section>\n'
	catalog := '<section class="catalog" aria-labelledby="catalog-title">\n' +
		'<div class="section-head"><div class="section-heading">' +
		'<h2 id="catalog-title">The catalogue</h2>' +
		'<p class="rfc-count" id="rfc-count" aria-live="polite">${app.rfcs.len} proposals</p></div>' +
		'<div class="sort-control" role="group" aria-label="Sort proposals">' +
		'<span class="sort-label">Sort by</span>' +
		'<button type="button" class="sort-btn is-active" data-sort="number" aria-pressed="true">RFC #</button>' +
		'<button type="button" class="sort-btn" data-sort="newest" aria-pressed="false">Newest</button>' +
		'<button type="button" class="sort-btn" data-sort="title" aria-pressed="false">A–Z</button>' +
		'</div></div>\n' +
		'<div class="rfc-list" id="rfc-list">\n' + cards.str() + '</div>\n' +
		'<div class="empty-state" id="rfc-empty" hidden><p>No proposals match that search.</p>' +
		'<button type="button" id="rfc-reset">Clear search</button></div>\n' +
		'</section>\n'
	return app.layout('V RFCs', hero + catalog, 'Requests for Comments for changes to the V language and standard library.')
}

fn (app &App) render_rfc(r Rfc) string {
	num := if r.id == '' { 'Draft' } else { 'RFC ${r.id}' }
	crumbs := '<nav class="breadcrumb" aria-label="Breadcrumb"><a href="${app.base_path}/">All RFCs</a>' +
		'<span class="sep">/</span><span>${escape_html(num)}</span></nav>\n'

	mut meta := '<div class="detail-meta"><span class="rfc-num">${escape_html(num)}</span>'
	if r.topic != '' {
		meta += '<span class="rfc-topic">${escape_html(r.topic)}</span>'
	}
	if r.start_date != '' {
		meta += '<time>${escape_html(r.start_date)}</time>'
	}
	meta += '</div>'
	head := '<header class="detail-head">' + meta + '<h1>${escape_html(r.title)}</h1></header>\n'

	mut toc_links := strings.new_builder(512)
	for h in r.headings {
		toc_links.write_string('<a class="toc-lvl-${h.level}" href="#${h.id}">${escape_html(h.title)}</a>\n')
	}
	mut aside := '<aside class="toc" aria-label="On this page">'
	if r.headings.len > 0 {
		aside += '<p class="toc-title">On this page</p><nav class="toc-nav">\n' + toc_links.str() + '</nav>'
	}
	pr_num := pr_number(r.pr)
	if pr_num != '' {
		aside += '<div class="toc-creator"><p class="toc-title">Proposed by</p>' +
			'<span class="creator" data-pr="${pr_num}"><span class="creator-avatar"></span>' +
			'<span class="creator-name">Loading author…</span></span></div>'
	}
	aside += '<div class="toc-links">'
	if r.pr != '' {
		aside += '<a href="${escape_html(r.pr)}">Discussion PR ${external_icon}</a>'
	}
	aside += '<a href="https://github.com/vlang/rfcs/blob/master/${escape_html(r.source)}">Source on GitHub ${external_icon}</a>'
	aside += '</div></aside>\n'

	inner := '<div class="detail">' + crumbs + head + '<div class="detail-grid">' +
		'<article class="rfc-body">\n' + r.body_html + '\n</article>\n' + aside + '</div></div>\n'
	return app.layout(r.title + ' — V RFCs', inner, r.summary)
}

fn (app &App) layout(title string, inner string, description string) string {
	base := app.base_path
	desc := if description == '' { 'Requests for Comments for changes to the V language and standard library.' } else { description }
	return '<!DOCTYPE html>\n<html lang="en">\n<head>\n<meta charset="utf-8" />\n' +
		'<meta name="viewport" content="width=device-width, initial-scale=1" />\n' +
		'<meta name="theme-color" content="#0a0e16" />\n' +
		'<meta name="description" content="${escape_html(desc)}" />\n' +
		'<title>${escape_html(title)}</title>\n' +
		'<link rel="icon" type="image/png" href="${base}/static/v-logo.png" />\n' +
		'<link rel="stylesheet" href="${base}/static/style.css" />\n' + '</head>\n<body>\n' +
		'<a class="skip-link" href="#main">Skip to content</a>\n' +
		'<header class="site-header"><div class="container header-inner">\n' +
		'<a class="brand" href="${base}/"><span class="brand-mark"><img src="${base}/static/v-logo.png" alt="V" width="30" height="30" /></span><span>RFCs</span></a>\n' +
		'<nav class="site-nav" aria-label="Primary">' +
		'<a class="nav-link is-current" href="${base}/">Index</a>' +
		'<a class="nav-link nav-secondary" href="https://vlang.io">vlang.io</a>' +
		'<a class="nav-link nav-secondary" href="https://docs.vlang.io">Docs</a>' +
		'<a class="nav-link nav-github" href="https://github.com/vlang/rfcs">GitHub ${external_icon}</a>' +
		'</nav>\n</div></header>\n' +
		'<main id="main" class="container">\n' + inner + '\n</main>\n' +
		'<footer class="site-footer"><div class="container footer-inner">\n' +
		'<p class="footer-brand"><img src="${base}/static/v-logo.png" alt="" width="20" height="20" /> V RFCs · <a href="https://github.com/vlang/rfcs">vlang/rfcs</a></p>\n' +
		'<p>Built with V and veb · inspired by <a href="https://vlang.io">vlang.io</a></p>\n' +
		'</div></footer>\n' +
		'<script src="${base}/static/app.js" defer></script>\n' + '</body>\n</html>\n'
}

fn main() {
	mut app := &App{}
	app.rfcs = load_rfcs() or {
		eprintln('failed to load RFCs: ${err}')
		exit(1)
	}
	if os.args.len > 1 && os.args[1] == '--export' {
		app.base_path = '/rfcs'
		export_site(mut app) or { panic('export: ${err}') }
		return
	}
	app.base_path = ''
	// Mount by explicit path: handle_static derives the URL mount from the
	// directory string, which breaks for absolute Windows paths.
	app.mount_static_folder_at(os.join_path(site_root, 'static'), '/static')!
	veb.run[App, Context](mut app, port)
}

fn export_site(mut app &App) ! {
	mut routes := ['/', '/404', '/search.json']
	for r in app.rfcs {
		routes << '/rfc/${r.slug}'
	}
	mut written := 0
	for route in routes {
		// /404 gets the full layout (with the right base path) instead of the
		// bare dev fragment, so GitHub Pages serves a styled error page.
		body := if route == '/404' {
			app.layout('Page not found — V RFCs',
				'<div class="detail"><h1>Page not found</h1><p><a href="${app.base_path}/">Back to RFC index</a></p></div>', '')
		} else {
			render_route(app, route)
		}
		if body == '' {
			panic('export: route "${route}" produced an empty body')
		}
		out := output_path(route)
		os.mkdir_all(os.dir(out))!
		os.write_file(out, body)!
		println('  wrote ${out} (${body.len} bytes)')
		written++
	}
	copy_static()!
	if written != routes.len {
		panic('export: expected ${routes.len} routes, wrote ${written}')
	}
	println('exported ${written} route(s) to ${out_dir}')
}

fn render_route(app &App, path string) string {
	// render_request's app parameter is the by-value generic A; dereference
	// explicitly so handlers see the loaded RFCs instead of a bad copy.
	mut owned := *app
	ctx := veb.render_request[App, Context](mut owned, http.Request{
		method: .get
		url:    path
	}) or { panic(err) }
	return ctx.res.body
}

fn output_path(route string) string {
	if route == '/' {
		return os.join_path(out_dir, 'index.html')
	}
	if route == '/404' {
		return os.join_path(out_dir, '404.html')
	}
	if route.ends_with('.json') {
		return os.join_path(out_dir, route.trim_left('/'))
	}
	return os.join_path(out_dir, route.trim_left('/'), 'index.html')
}

fn copy_static() ! {
	src := os.join_path(site_root, 'static')
	dst := os.join_path(out_dir, 'static')
	os.mkdir_all(dst)!
	for name in os.ls(src)! {
		if name.ends_with('.css') || name.ends_with('.js') || name.ends_with('.png') {
			data := os.read_file(os.join_path(src, name))!
			os.write_file(os.join_path(dst, name), data)!
		}
	}
}

// load_rfcs collects rfcs/*.md plus notable root docs as browsable pages.
fn load_rfcs() ![]Rfc {
	mut out := []Rfc{}
	for name in os.ls(rfcs_dir)! {
		if !name.ends_with('.md') {
			continue
		}
		path := os.join_path(rfcs_dir, name)
		out << parse_rfc_file(path, 'rfcs/${name}')!
	}
	for name in ['comptime.md', 'error_handling.md', 'optional-option-result.md'] {
		path := os.join_path(repo_root, name)
		if os.exists(path) {
			out << parse_rfc_file(path, name)!
		}
	}
	out.sort(a.slug < b.slug)
	out.sort(a.id < b.id)
	return out
}

fn parse_rfc_file(path string, source string) !Rfc {
	raw := os.read_file(path)!
	fname := os.base(path).replace('.md', '')
	mut id := ''
	mut slug := fname
	if fname.len > 4 && fname[3] == `-` {
		id = fname[..3]
		slug = fname[4..]
		if id == '000' {
			id = ''
		}
	}
	lines := raw.split_into_lines()
	mut topic := ''
	mut start_date := ''
	mut pr := ''
	mut title := ''
	mut summary := ''
	for line in lines {
		t := line.trim_space()
		if t.starts_with('- Topic Name:') {
			topic = t.replace('- Topic Name:', '').trim_space()
		} else if t.starts_with('- Start Date:') {
			start_date = t.replace('- Start Date:', '').trim_space()
		} else if t.starts_with('- RFC PR:') {
			start := t.index('(') or { -1 }
			end := t.last_index(')') or { -1 }
			if start != -1 && end != -1 && end > start {
				pr = t[start + 1..end]
			}
		} else if t.starts_with('# ') && title == '' {
			candidate := t[2..].trim_space()
			if !is_template_section(candidate) {
				title = plain_text(candidate)
			}
		}
		if title != '' && topic != '' && start_date != '' {
			// keep scanning for the PR line, it usually follows
			if pr != '' || !t.starts_with('- ') {
				// do not break too early when PR line is still ahead
			}
		}
	}
	if title == '' {
		title = humanize_slug(slug)
	}
	// Template placeholder PRs (00000 / 0000) are not real discussions. Drop
	// them so neither the card nor the detail page renders a broken link.
	if pr != '' && pr_number(pr) == '' {
		pr = ''
	}
	// summary is the first non-heading paragraph after the first heading
	mut seen_heading := false
	for i, line in lines {
		t := line.trim_space()
		if t.starts_with('# ') {
			seen_heading = true
			continue
		}
		if seen_heading && t != '' && !t.starts_with('#') && !t.starts_with('- ')
			&& !t.starts_with('![') && i < lines.len - 1 {
			summary = plain_text(t)
			if summary.len > 220 {
				summary = summary[..220] + '…'
			}
			break
		}
	}
	// drop the heading reused as the page title so it is not rendered twice
	mut body_lines := lines.clone()
	for i, line in body_lines {
		t := line.trim_space()
		if t.starts_with('# ') {
			if t == '# ' + title {
				body_lines.delete(i)
			}
			break
		}
	}
	// Collect the same headings the renderer emits, with matching anchors, so
	// the table of contents can never drift from the article.
	mut used_slugs := []string{}
	mut headings := []Heading{}
	for line in body_lines {
		t := line.trim_space()
		mut level := 0
		mut heading_text := ''
		if t.starts_with('#### ') {
			level = 4
			heading_text = t[5..].trim_space()
		} else if t.starts_with('### ') {
			level = 3
			heading_text = t[4..].trim_space()
		} else if t.starts_with('## ') {
			level = 2
			heading_text = t[3..].trim_space()
		} else if t.starts_with('# ') {
			level = 2
			heading_text = t[2..].trim_space()
		}
		if level > 0 {
			headings << Heading{
				level: level
				title: heading_text
				id:    unique_slug(heading_text, mut used_slugs)
			}
		}
	}
	body_html := md_to_html(body_lines.join('\n'))
	return Rfc{
		id:         id
		slug:       slug
		title:      title
		topic:      topic
		start_date: start_date
		pr:         pr
		summary:    summary
		body_html:  body_html
		source:     source
		headings:   headings
	}
}

fn is_template_section(s string) bool {
	lower := s.to_lower()
	return lower in ['summary', 'motivation', 'guide-level explanation', 'reference-level explanation',
		'drawbacks', 'rationale and alternatives', 'prior art', 'unresolved questions',
		'future possibilities']
}

fn humanize_slug(slug string) string {
	parts := slug.replace('_', '-').split('-')
	mut out := []string{}
	for p in parts {
		if p.len == 0 {
			continue
		}
		up := p.to_upper()
		if up == 'RFC' || up == 'VPM' || up == 'API' || up == 'VLIB' {
			out << up
		} else {
			out << p[0..1].to_upper() + p[1..]
		}
	}
	return out.join(' ')
}

fn escape_html(s string) string {
	mut b := strings.new_builder(s.len + 16)
	for ch in s {
		match ch {
			`&` { b.write_string('&amp;') }
			`<` { b.write_string('&lt;') }
			`>` { b.write_string('&gt;') }
			`"` { b.write_string('&quot;') }
			`'` { b.write_string('&#39;') }
			else { b.write_u8(ch) }
		}
	}
	return b.str()
}

// plain_text keeps inline Markdown decorations out of titles and summaries.
fn plain_text(s string) string {
	return s.replace('`', '').replace('**', '').replace('__', '')
}

// slugify turns a heading into a stable, URL-safe anchor.
fn slugify(s string) string {
	mut b := strings.new_builder(s.len)
	mut prev_dash := false
	for ch in s.to_lower() {
		if (ch >= `a` && ch <= `z`) || (ch >= `0` && ch <= `9`) {
			b.write_u8(ch)
			prev_dash = false
		} else if !prev_dash {
			b.write_u8(`-`)
			prev_dash = true
		}
	}
	return b.str().trim_left('-').trim_right('-')
}

// unique_slug keeps anchors unique when a document repeats a heading.
fn unique_slug(title string, mut used []string) string {
	mut base := slugify(title)
	if base == '' {
		base = 'section'
	}
	mut id := base
	mut n := 2
	for used.contains(id) {
		id = '${base}-${n}'
		n++
	}
	used << id
	return id
}

// md_to_html is a small self-contained Markdown renderer, enough for RFC prose:
// headings, fenced code, lists, links, bold, inline code and paragraphs.
fn md_to_html(md string) string {
	mut out := strings.new_builder(md.len + 1024)
	mut used_slugs := []string{}
	mut in_code := false
	mut code_lang := ''
	mut in_list := false
	mut para := strings.new_builder(512)

	lines := md.split_into_lines()
	for line in lines {
		t := line.trim_space()
		if t.starts_with('```') {
			if in_code {
				out.write_string('</code></pre>\n')
				in_code = false
			} else {
				pt := para.str().trim_space()
				if pt != '' {
					out.write_string('<p>' + inline_md(pt) + '</p>\n')
				}
				para = strings.new_builder(512)
				if in_list {
					out.write_string('</ul>\n')
					in_list = false
				}
				code_lang = t.trim_left('`').trim_space()
				out.write_string('<pre class="code-block" data-lang="' + escape_html(code_lang) + '"><code>')
				in_code = true
			}
			continue
		}
		if in_code {
			out.write_string(escape_html(line) + '\n')
			continue
		}
		if t == '' {
			pt := para.str().trim_space()
			if pt != '' {
				out.write_string('<p>' + inline_md(pt) + '</p>\n')
			}
			para = strings.new_builder(512)
			continue
		}
		if t.starts_with('- Topic Name:') || t.starts_with('- Start Date:')
			|| t.starts_with('- RFC PR:') || t.starts_with('- V Issue:') {
			continue
		}
		if t.starts_with('#### ') {
			pt := para.str().trim_space()
			if pt != '' {
				out.write_string('<p>' + inline_md(pt) + '</p>\n')
			}
			para = strings.new_builder(512)
			if in_list {
				out.write_string('</ul>\n')
				in_list = false
			}
			htext := t[5..].trim_space()
			hid := unique_slug(htext, mut used_slugs)
			out.write_string('<h4 id="' + hid + '">' + inline_md(htext) + '</h4>\n')
		} else if t.starts_with('### ') {
			pt := para.str().trim_space()
			if pt != '' {
				out.write_string('<p>' + inline_md(pt) + '</p>\n')
			}
			para = strings.new_builder(512)
			if in_list {
				out.write_string('</ul>\n')
				in_list = false
			}
			htext := t[4..].trim_space()
			hid := unique_slug(htext, mut used_slugs)
			out.write_string('<h3 id="' + hid + '">' + inline_md(htext) + '</h3>\n')
		} else if t.starts_with('## ') {
			pt := para.str().trim_space()
			if pt != '' {
				out.write_string('<p>' + inline_md(pt) + '</p>\n')
			}
			para = strings.new_builder(512)
			if in_list {
				out.write_string('</ul>\n')
				in_list = false
			}
			htext := t[3..].trim_space()
			hid := unique_slug(htext, mut used_slugs)
			out.write_string('<h2 id="' + hid + '">' + inline_md(htext) + '</h2>\n')
		} else if t.starts_with('# ') {
			pt := para.str().trim_space()
			if pt != '' {
				out.write_string('<p>' + inline_md(pt) + '</p>\n')
			}
			para = strings.new_builder(512)
			if in_list {
				out.write_string('</ul>\n')
				in_list = false
			}
			htext := t[2..].trim_space()
			hid := unique_slug(htext, mut used_slugs)
			out.write_string('<h2 id="' + hid + '">' + inline_md(htext) + '</h2>\n')
		} else if t.starts_with('- ') || t.starts_with('* ') {
			pt := para.str().trim_space()
			if pt != '' {
				out.write_string('<p>' + inline_md(pt) + '</p>\n')
			}
			para = strings.new_builder(512)
			if !in_list {
				out.write_string('<ul>\n')
				in_list = true
			}
			out.write_string('<li>' + inline_md(t[2..].trim_space()) + '</li>\n')
		} else if t.len > 2 && t[0] >= `0` && t[0] <= `9` && t[1] == `.` {
			pt := para.str().trim_space()
			if pt != '' {
				out.write_string('<p>' + inline_md(pt) + '</p>\n')
			}
			para = strings.new_builder(512)
			if !in_list {
				out.write_string('<ul>\n')
				in_list = true
			}
			out.write_string('<li>' + inline_md(t[2..].trim_space()) + '</li>\n')
		} else {
			if in_list {
				out.write_string('</ul>\n')
				in_list = false
			}
			if para.len > 0 {
				para.write_string(' ')
			}
			para.write_string(t)
		}
	}
	pt_end := para.str().trim_space()
	if pt_end != '' {
		out.write_string('<p>' + inline_md(pt_end) + '</p>\n')
	}
	if in_list {
		out.write_string('</ul>\n')
	}
	if in_code {
		out.write_string('</code></pre>\n')
	}
	return out.str()
}

fn inline_md(s string) string {
	// escape first, then restore markdown-generated tags
	mut r := escape_html(s)
	// inline code `x`
	for {
		a := r.index('&#39;') or { break }
		_ = a
		break
	}
	mut out := strings.new_builder(r.len + 32)
	mut i := 0
	mut in_code := false
	for i < r.len {
		if r[i] == 96 {
			out.write_string(if in_code { '</code>' } else { '<code>' })
			in_code = !in_code
			i++
		} else {
			out.write_u8(r[i])
			i++
		}
	}
	r = out.str()
	if in_code {
		r += '</code>'
	}
	// bold **x**
	for {
		a := r.index('**') or { break }
		b := r[a + 2..].index('**') or { break }
		inner := r[a + 2..a + 2 + b]
		r = r[..a] + '<strong>' + inner + '</strong>' + r[a + 2 + b + 2..]
	}
	// links [t](u)
	for {
		a := r.index('[') or { break }
		m := r[a..].index('](') or { break }
		b := r[a + m + 2..].index(')') or { break }
		text := r[a + 1..a + m]
		url := r[a + m + 2..a + m + 2 + b]
		r = r[..a] + '<a href="' + url + '">' + text + '</a>' +
			r[a + m + 2 + b + 1..]
	}
	return r
}
