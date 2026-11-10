#!/usr/bin/env ruby
# Turns a blog post into an HTML page whose content can be pasted into the
# Substack editor, which keeps pasted formatting but does not import Markdown.
#
#   ruby _scripts/substack.rb _posts/2026-11-10-java-ai.md [--no-open]
#
# The page is written to ~/substack/<slug>.html (outside /tmp, so a snap
# Firefox can read it) and opened in the browser. It starts with a line linking
# to the post on the site, since Substack has no canonical URL setting.
#
# Changes made for Substack:
#   - tables become aligned monospace blocks (Substack has no tables);
#   - code blocks lose syntax highlighting (Substack has none);
#   - site-relative links and images become absolute URLs.

require 'cgi'
require 'date'
require 'fileutils'
require 'kramdown'
require 'net/http'
require 'yaml'

ROOT = File.expand_path('..', __dir__)

post = ARGV.find { |a| !a.start_with?('--') }
abort "usage: ruby _scripts/substack.rb _posts/<post>.md [--no-open]" unless post && File.file?(post)
open_page = !ARGV.include?('--no-open')

text = File.read(post)
_, front, body = text.split(/^---\s*$/, 3)
abort "#{post}: no front matter found" unless body
meta = YAML.safe_load(front, permitted_classes: [Date, Time]) || {}

# Canonical URL, built the way Jekyll builds it from _config.yml. The file is
# not strict YAML (an alias is used before its anchor), so read only the top-level
# keys needed here; like Jekyll, the last occurrence of a key wins.
def setting(config, key)
  value = config.scan(/^#{key}\s*:\s*(?:&\S+\s+)?("[^"]*"|\S+)/).flatten.last
  value&.delete('"').to_s
end
config = File.read(File.join(ROOT, '_config.yml'))
site = "#{setting(config, 'url')}#{setting(config, 'baseurl')}".chomp('/')
slug = meta['slug'] || File.basename(post, '.*').sub(/\A\d{4}-\d{1,2}-\d{1,2}-/, '')
path = meta['permalink'] || setting(config, 'permalink').gsub(':collection', 'posts').gsub(':title', slug)
canonical = site + path

# Substack has no tables: turn each Markdown table into an aligned monospace block.
body = body.gsub(/((?:^[ \t]*\|.*\|[ \t]*\n)+)/) do
  rows = Regexp.last_match(1).lines.map do |line|
    line.strip.delete_prefix('|').delete_suffix('|').split('|').map { |cell| cell.strip.delete('`') }
  end
  rows.reject! { |row| row.all? { |cell| cell.match?(/\A:?-+:?\z/) } }
  widths = rows.map(&:size).max.times.map { |i| rows.map { |row| row[i].to_s.length }.max }
  lines = rows.map do |row|
    widths.each_index.map { |i| i.zero? ? row[i].to_s.ljust(widths[i]) : row[i].to_s.rjust(widths[i]) }.join('   ').rstrip
  end
  "```\n#{lines.join("\n")}\n```\n"
end
body = body.gsub(/\{%-?\s*(raw|endraw)\s*-?%\}/, '')

html = Kramdown::Document.new(body, input: 'GFM', syntax_highlighter: nil, hard_wrap: false).to_html
html = html.gsub(/(src|href)="\/(?!\/)/) { "#{Regexp.last_match(1)}=\"#{site}/" }

title = meta['title'].to_s
subtitle = (meta['description'] || meta['excerpt']).to_s
shown = canonical.sub(%r{\Ahttps?://}, '').chomp('/')

page = <<~HTML
  <!doctype html>
  <html lang="en">
  <head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>#{CGI.escapeHTML(title)}</title>
  <style>
    body { max-width: 720px; margin: 2em auto; padding: 0 16px; font-family: Georgia, serif; line-height: 1.6; background: #fff; color: #222; }
    pre { background: #f4f4f4; padding: 12px; overflow-x: auto; }
    code { font-family: monospace; }
    .meta { font-family: sans-serif; background: #fff6d6; border: 1px solid #e6c84f; padding: 12px; margin-bottom: 2em; }
  </style>
  </head>
  <body>
  <div class="meta">
    <strong>Title:</strong> #{CGI.escapeHTML(title)}<br>
    <strong>Subtitle:</strong> #{CGI.escapeHTML(subtitle)}<br>
    Copy these two into Substack's title and subtitle fields, then select from the line below to the end and paste it into the post body.
  </div>
  <p><em>This article was originally published on <a href="#{CGI.escapeHTML(canonical)}">#{CGI.escapeHTML(shown)}</a>.</em></p>
  <hr>
  #{html}
  </body>
  </html>
HTML

out_dir = File.join(Dir.home, 'substack')
FileUtils.mkdir_p(out_dir)
out = File.join(out_dir, "#{slug}.html")
File.write(out, page)

puts "Canonical URL: #{canonical}"
begin
  status = Net::HTTP.get_response(URI(canonical)).code
  warn "Warning: #{canonical} answered HTTP #{status}; publish the post on the site first." unless status == '200'
rescue StandardError => e
  warn "Warning: could not check #{canonical} (#{e.class})."
end
puts "Substack page:  #{out}"

system('xdg-open', out, out: File::NULL, err: File::NULL) if open_page
