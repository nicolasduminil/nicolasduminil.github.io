#!/usr/bin/env ruby
# Turns a blog post into an HTML page whose content can be pasted into the
# Substack or Medium editor, which keep pasted formatting but do not import Markdown.
#
#   ruby _scripts/substack.rb _posts/2026-11-10-java-ai.md [--medium] [--no-open]
#
# The page is written to ~/substack/<slug>.html, or ~/medium/<slug>.html with
# --medium (outside /tmp, so a snap Firefox can read it), and opened in the
# browser. A box at the top gives the title, subtitle and the steps to follow.
#
# Substack has no canonical URL setting, so its page starts with a line linking
# to the post on the site. Medium has one (Advanced Settings), so its page
# leaves that line out and the box gives the URL to enter there instead.
#
# Changes made for both:
#   - tables become aligned monospace blocks (neither editor has tables);
#   - code blocks lose syntax highlighting (neither editor has it);
#   - site-relative links and images become absolute URLs;
#   - images wrapped in a link are listed at the top, because both editors drop
#     those links on paste and they have to be added back with Ctrl+K.

require 'cgi'
require 'date'
require 'fileutils'
require 'kramdown'
require 'net/http'
require 'yaml'

ROOT = File.expand_path('..', __dir__)

post = ARGV.find { |a| !a.start_with?('--') }
abort "usage: ruby _scripts/substack.rb _posts/<post>.md [--medium] [--no-open]" unless post && File.file?(post)
open_page = !ARGV.include?('--no-open')
medium = ARGV.include?('--medium')
platform = medium ? 'Medium' : 'Substack'

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

# Both editors drop the link around pasted images, so list them for relinking by hand.
# Kramdown has already HTML-escaped these attribute values.
linked_images = html.scan(/<a href="([^"]*)">\s*<img\b([^>]*)>\s*<\/a>/).map do |href, attrs|
  [attrs[/\balt="([^"]*)"/, 1].to_s.then { |alt| alt.empty? ? 'image' : alt }, href]
end
relink_how = if medium
  'click the image until it has a green border, press Ctrl+K, paste the URL, then press Enter.'
else
  'in edit mode, click the image once, press Ctrl+K, paste the URL, then Update.'
end
relink = if linked_images.empty?
  ''
else
  items = linked_images.map { |alt, href| %(<li>#{alt}: <code>#{href}</code></li>) }.join("\n")
  <<~BOX.chomp
    <p><strong>Relink these images after pasting</strong> (#{platform} drops their links): #{relink_how}</p>
    <ul>
    #{items}
    </ul>
  BOX
end

safe_canonical = CGI.escapeHTML(canonical)
steps = if medium
  <<~BOX.chomp
    <p>Type the title as the first line of a new story and the subtitle as the second line, then select everything below this box and paste it after them.</p>
    <p><strong>Canonical link:</strong> before publishing, open the story's settings, go to Advanced Settings, tick "This story was originally published elsewhere" and enter <code>#{safe_canonical}</code>.</p>
  BOX
else
  "<p>Copy these two into Substack's title and subtitle fields, then select everything below this box and paste it into the post body.</p>"
end
notice = if medium
  ''
else
  %(<p><em>This article was originally published on <a href="#{safe_canonical}">#{CGI.escapeHTML(shown)}</a>.</em></p>\n<hr>)
end

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
    .meta p { margin: 0.5em 0; }
  </style>
  </head>
  <body>
  <div class="meta">
  <p><strong>For #{platform}</strong></p>
  <p><strong>Title:</strong> #{CGI.escapeHTML(title)}<br>
  <strong>Subtitle:</strong> #{CGI.escapeHTML(subtitle)}</p>
  #{steps}
  #{relink}
  </div>
  #{notice}
  #{html}
  </body>
  </html>
HTML

out_dir = File.join(Dir.home, platform.downcase)
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
puts "#{"#{platform} page:".ljust(15)} #{out}"
linked_images.each { |alt, href| puts "Relink image:   #{CGI.unescapeHTML(alt)} -> #{CGI.unescapeHTML(href)}" }

system('xdg-open', out, out: File::NULL, err: File::NULL) if open_page
