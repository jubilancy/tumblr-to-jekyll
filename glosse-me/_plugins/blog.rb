# frozen_string_literal: true

# blog.rb - taxonomy pages, CMS-friendly front matter and image tuning for the Tumblr archive.
#
# 1. Taxonomy: builds /tags/<slug>/, /themes/<slug>/ and /categories/<slug>/
#    from the `tags`, `themes` and `categories` front matter of every post, and
#    exposes sorted term lists to templates as site.taxonomies.tags (etc.), each
#    entry {name, slug, count, page}. Terms are lower-cased so "Art" and "art"
#    are one term. Tags used fewer than `tag_page_min` times (_config.yml) get no
#    page of their own (2000+ one-post pages would only bloat the site); they stay
#    searchable and are listed on /tags/.
#
#    Each of the three can be a YAML list OR one comma-separated string:
#        themes: [medieval, maps]        themes: "medieval, maps"
#    The string form is what the CMS bulk-edit table uses (Sveltia can't bulk-edit
#    lists). Jekyll itself splits `tags` and `categories` strings on spaces, so
#    the raw front matter is read here to keep multi-word terms intact.
#
# 2. Cover images for posts made in the CMS: a post without an `images` list gets
#    one built from the Cloudinary images in its body, with each image's size looked
#    up from Cloudinary at build time (the fl_getinfo flag; cached in .jekyll-cache).
#    The tile grid needs the size to reserve space for the picture.
#
# 3. Images in posts are served resized (max 1400px, automatic format and quality)
#    and lazy-loaded, with the full-size URL kept in data-full for the lightbox.
#    The first image on a page loads eagerly.

require "set"
require "json"
require "net/http"
require "uri"
require "yaml"
require "date"

module Blog
  KINDS = %w[tags themes categories].freeze

  # Raw front matter, read straight from the file.
  module Raw
    @cache = {}

    def self.front_matter(doc)
      @cache[doc.path] ||= begin
        text = File.read(doc.path, encoding: "UTF-8")
        m = text.match(/\A---\s*\n(.*?)\n---\s*(\n|\z)/m)
        data = m ? YAML.safe_load(m[1], permitted_classes: [Date, Time, Symbol], aliases: true) : nil
        data.is_a?(Hash) ? data : {}
      rescue StandardError
        {}
      end
    end

    # Normalised terms for one taxonomy: lower-cased, trimmed, unique.
    def self.terms(doc, kind)
      raw = front_matter(doc)[kind]
      raw = doc.data[kind] if raw.nil?
      list = raw.is_a?(String) ? raw.split(",") : Array(raw)
      list.flatten.map { |t| t.to_s.strip.downcase }.reject(&:empty?).uniq
    end
  end

  # Cover images (with sizes) for posts that have none in front matter.
  class Images < Jekyll::Generator
    safe true
    priority :highest

    IMG_MD = %r{!\[([^\]]*)\]\((https://res\.cloudinary\.com/[^/\s)]+/image/upload/(?:[^/\s)]+/)*v\d+/[^\s)]+)\)}.freeze

    def generate(site)
      @cache_path = File.join(site.source, site.config["cache_dir"] || ".jekyll-cache", "blog-image-sizes.json")
      @sizes = File.exist?(@cache_path) ? (JSON.parse(File.read(@cache_path)) rescue {}) : {}
      changed = false

      site.posts.docs.each do |doc|
        next unless Array(doc.data["images"]).empty?
        found = doc.content.scan(IMG_MD)
        next if found.empty?
        doc.data["images"] = found.map do |alt, url|
          clean = url.sub(%r{(/image/upload/)(?:[^/]+/)*(v\d+/)}, '\1\2')
          unless @sizes.key?(clean)
            @sizes[clean] = lookup(clean)
            changed = true
          end
          w, h = @sizes[clean]
          { "url" => clean, "width" => w, "height" => h, "alt" => alt }
        end
      end

      return unless changed
      FileUtils.mkdir_p(File.dirname(@cache_path))
      File.write(@cache_path, JSON.generate(@sizes))
    end

    private

    # Cloudinary's fl_getinfo flag returns the original's size as JSON.
    def lookup(url)
      info = URI(url.sub("/image/upload/", "/image/upload/fl_getinfo/"))
      res = Net::HTTP.start(info.host, info.port, use_ssl: true, open_timeout: 8, read_timeout: 10) { |h| h.get(info.request_uri) }
      input = JSON.parse(res.body)["input"]
      [input["width"], input["height"]]
    rescue StandardError => e
      Jekyll.logger.warn "blog:", "could not read image size for #{url} (#{e.class}); tile falls back to a square"
      [nil, nil]
    end
  end

  class TermPage < Jekyll::PageWithoutAFile
    def initialize(site, kind, term, posts)
      super(site, site.source, File.join(kind, term["slug"]), "index.html")
      self.data = {
        "layout" => "taxonomy",
        "title" => term["name"],
        "taxonomy" => kind,
        "term" => term["name"],
        "posts" => posts,
        "sitemap" => false,
      }
      self.content = ""
    end
  end

  class Taxonomy < Jekyll::Generator
    safe true
    priority :low

    def generate(site)
      min = (site.config["tag_page_min"] || 2).to_i
      docs = site.posts.docs.sort_by(&:date).reverse
      result = {}

      KINDS.each do |kind|
        groups = {}
        docs.each do |doc|
          Blog::Raw.terms(doc, kind).each { |name| (groups[name] ||= []) << doc }
        end

        used = Set.new
        terms = groups.map do |name, posts|
          slug = Jekyll::Utils.slugify(name)
          slug = name.unpack1("H*")[0, 16] if slug.nil? || slug.empty?
          slug = "#{slug}-2" while used.include?(slug)
          used << slug
          { "name" => name, "slug" => slug, "count" => posts.size,
            "page" => (kind != "tags" || posts.size >= min), "posts" => posts }
        end
        terms.sort_by! { |t| [-t["count"], t["name"]] }

        terms.each do |t|
          site.pages << TermPage.new(site, kind, t, t["posts"]) if t["page"]
        end
        result[kind] = terms.map { |t| t.reject { |k, _| k == "posts" } }
      end

      site.config["taxonomies"] = result

      # Per-post links for templates: doc.term_links.tags = [{name, slug|nil}, ...]
      # (slug is nil when a term has no page of its own). Themes and categories
      # are also written back as clean lists for the feed and templates.
      lookup = {}
      KINDS.each do |kind|
        lookup[kind] = {}
        result[kind].each { |t| lookup[kind][t["name"]] = t }
      end
      docs.each do |doc|
        links = {}
        KINDS.each do |kind|
          names = Blog::Raw.terms(doc, kind)
          doc.data[kind] = names unless kind == "tags"
          links[kind] = names.map do |name|
            t = lookup[kind][name]
            { "name" => name, "slug" => (t && t["page"] ? t["slug"] : nil) }
          end
        end
        doc.data["term_links"] = links
      end
    end
  end
end

CLOUDINARY_IMG = %r{<img src="(https://res\.cloudinary\.com/[^"/]+/image/upload/)(v\d+/[^"]+)"([^>]*)>}.freeze

Jekyll::Hooks.register :posts, :post_render do |post|
  first = true
  post.output = post.output.gsub(CLOUDINARY_IMG) do
    base = Regexp.last_match(1)
    rest = Regexp.last_match(2)
    attrs = Regexp.last_match(3)
    lazy = first ? "" : ' loading="lazy"'
    first = false
    %(<img src="#{base}c_limit,w_1400,f_auto,q_auto/#{rest}" data-full="#{base}#{rest}"#{lazy} decoding="async"#{attrs}>)
  end
end
