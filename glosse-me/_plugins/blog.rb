# frozen_string_literal: true

# blog.rb - taxonomy pages and image tuning for the Tumblr archive.
#
# 1. Taxonomy: builds /tags/<slug>/, /themes/<slug>/ and /categories/<slug>/
#    from the `tags`, `themes` and `categories` front matter of every post, and
#    exposes sorted term lists to templates as site.taxonomies.tags (etc.), each
#    entry {name, slug, count, page}. Terms are lower-cased so "Art" and "art"
#    are one term. Tags used fewer than `tag_page_min` times (_config.yml) get no
#    page of their own (2000+ one-post pages would only bloat the site); they stay
#    searchable and are listed on /tags/.
#    Add `themes: [a, b]` or `categories: [x]` to any post's front matter (by
#    hand or in a CMS) and the pages appear on the next build.
#
# 2. Images: Cloudinary images inside a post are served resized (max 1400px,
#    automatic format and quality) and lazy-loaded, with the full-size URL kept in
#    data-full for the lightbox. The first image on a page loads eagerly.

require "set"

module Blog
  KINDS = %w[tags themes categories].freeze

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
          Array(doc.data[kind]).each do |raw|
            name = raw.to_s.strip.downcase
            next if name.empty?
            (groups[name] ||= []) << doc
          end
        end

        used = Set.new
        terms = groups.map do |name, posts|
          slug = Jekyll::Utils.slugify(name)
          slug = name.unpack1("H*")[0, 16] if slug.nil? || slug.empty?
          slug = "#{slug}-2" while used.include?(slug)
          used << slug
          posts = posts.uniq
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

      # Per-post links for templates: doc.term_links.tags = [{name, url|nil}, ...]
      # (url is nil when a term has no page of its own).
      lookup = {}
      KINDS.each do |kind|
        lookup[kind] = {}
        result[kind].each { |t| lookup[kind][t["name"]] = t }
      end
      docs.each do |doc|
        links = {}
        KINDS.each do |kind|
          links[kind] = Array(doc.data[kind]).map { |raw| raw.to_s.strip.downcase }.reject(&:empty?).uniq.map do |name|
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
