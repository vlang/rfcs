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

fn (app &App) render_index() string {
	mut cards := strings.new_builder(8192)
	for r in app.rfcs {
		num := if r.id == '' { '—' } else { r.id }
		cards.write_string('<article class="rfc-card" data-search="${escape_html(r.title + ' ' + r.slug + ' ' + r.summary + ' ' + r.topic)}">\n')
		cards.write_string('<div class="rfc-meta"><span class="rfc-num">#${escape_html(num)}</span>')
		if r.start_date != '' {
			cards.write_string('<span class="rfc-date">${escape_html(r.start_date)}</span>')
		}
		cards.write_string('</div>\n')
		cards.write_string('<h2><a href="${app.base_path}/rfc/${r.slug}/">${escape_html(r.title)}</a></h2>\n')
		if r.summary != '' {
			cards.write_string('<p class="rfc-summary">${escape_html(r.summary)}</p>\n')
		}
		cards.write_string('<div class="rfc-links"><a href="${app.base_path}/rfc/${r.slug}/">Read RFC →</a>')
		if r.pr != '' {
			cards.write_string(' <a class="rfc-pr" href="${escape_html(r.pr)}">PR ↗</a>')
		}
		cards.write_string('</div></article>\n')
	}
	body := '<section class="intro">\n' + '<h1>V RFCs</h1>\n' +
		'<p>Request for Comments for changes to the V language and standard library. ' +
		'Read the <a href="https://github.com/vlang/rfcs#rfc-proposal-process">RFC process</a> ' +
		'or <a href="https://github.com/vlang/rfcs">contribute on GitHub</a>.</p>\n' +
		'<input id="rfc-search" type="search" placeholder="Filter RFCs…" aria-label="Filter RFCs" />\n' +
		'<p class="rfc-count" id="rfc-count">${app.rfcs.len} RFCs</p>\n' + '</section>\n' +
		'<section class="rfc-list" id="rfc-list">\n' + cards.str() + '</section>\n'
	return app.layout('V RFCs', body)
}

fn (app &App) render_rfc(r Rfc) string {
	num := if r.id == '' { 'Draft' } else { 'RFC ${r.id}' }
	mut meta := '<p class="rfc-detail-meta"><a href="${app.base_path}/">← All RFCs</a> · ${escape_html(num)}'
	if r.start_date != '' {
		meta += ' · ${escape_html(r.start_date)}'
	}
	if r.topic != '' {
		meta += ' · <code>${escape_html(r.topic)}</code>'
	}
	meta += '</p>'
	mut links := '<p class="rfc-source">'
	if r.pr != '' {
		links += '<a href="${escape_html(r.pr)}">Discussion PR ↗</a> · '
	}
	links += '<a href="https://github.com/vlang/rfcs/blob/master/${escape_html(r.source)}">Source on GitHub ↗</a></p>'
	body := meta + '<article class="rfc-body">\n<h1>${escape_html(r.title)}</h1>\n' + r.body_html +
		'\n</article>\n' + links
	return app.layout(r.title + ' — V RFCs', body)
}

fn (app &App) layout(title string, inner string) string {
	base := app.base_path
	return '<!DOCTYPE html>\n<html lang="en">\n<head>\n<meta charset="utf-8" />\n' +
		'<meta name="viewport" content="width=device-width, initial-scale=1" />\n' +
		'<title>${escape_html(title)}</title>\n' +
		'<link rel="stylesheet" href="${base}/static/style.css" />\n' + '</head>\n<body>\n' +
		'<header class="site-header"><div class="wrap">\n' +
		'<a class="brand" href="${base}/"><span class="brand-mark">V</span><span>RFCs</span></a>\n' +
		'<nav><a href="${base}/">Index</a>' +
		'<a href="https://vlang.io">vlang.io</a>' +
		'<a href="https://docs.vlang.io">Docs</a>' +
		'<a href="https://github.com/vlang/rfcs">GitHub</a></nav>\n' + '</div></header>\n' +
		'<main class="wrap">\n' + inner + '\n</main>\n' +
		'<footer class="site-footer"><div class="wrap">\n' +
		'<p>V RFCs · <a href="https://github.com/vlang/rfcs">vlang/rfcs</a> · ' +
		'Theme inspired by <a href="https://vlang.io">vlang.io</a></p>\n' + '</div></footer>\n' +
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
				'<h1>Page not found</h1><p><a href="${app.base_path}/">Back to RFC index</a></p>')
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
		if name.ends_with('.css') || name.ends_with('.js') {
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
				title = candidate
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
			summary = t
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

// md_to_html is a small self-contained Markdown renderer, enough for RFC prose:
// headings, fenced code, lists, links, bold, inline code and paragraphs.
fn md_to_html(md string) string {
	mut out := strings.new_builder(md.len + 1024)
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
				if code_lang != '' {
					out.write_string('<pre><code class="lang-' + escape_html(code_lang) +
						'">')
				} else {
					out.write_string('<pre><code>')
				}
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
			out.write_string('<h4>' + inline_md(t[5..].trim_space()) + '</h4>\n')
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
			out.write_string('<h3>' + inline_md(t[4..].trim_space()) + '</h3>\n')
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
			out.write_string('<h2>' + inline_md(t[3..].trim_space()) + '</h2>\n')
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
			out.write_string('<h2>' + inline_md(t[2..].trim_space()) + '</h2>\n')
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
