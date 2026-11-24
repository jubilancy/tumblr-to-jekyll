# tumblr-to-jekyll

Move a Tumblr blog (posts, reblogs, asks) to a self-hosted Jekyll site, with images on Cloudinary.
First target: [fromdaysoff.tumblr.com](https://fromdaysoff.tumblr.com/) to glosse.me.

## What's here

| Path | What it is |
|---|---|
| `scripts/tumblr_to_jekyll.py` | Importer. Pages through the Tumblr API, writes one Jekyll post per Tumblr post, uploads every image to Cloudinary as `tumblr/fromdaysoff/<post-id>_<n>`. Resumable, writes a `results-log-*.txt` on every run. |
| `glosse-me/` | The Jekyll site: theme, plugin and the 305 imported posts in `_posts/`. |
| `glosse-me/raw/` | Each post's full Tumblr API response, so posts can be re-rendered without calling the API again. |
| `glosse-me/state.json` | Importer progress, used to resume. |
| `.github/workflows/pages.yml` | Builds the site and deploys it to GitHub Pages. |

Post URLs follow Tumblr's pattern: `/post/<tumblr id>/`.

## The theme

Top bar, then a masonry of tiles (one tile per post, `⧉ 9` marks posts with several images). The `▤ / ▦` buttons switch between masonry and a neat grid; the choice and the light/dark choice are remembered in the browser. Look and font (Luxi Mono) come from glosse.me.

- **Light on the wire:** the first 24 tiles are in the page; the rest load from `posts.json` as you scroll. Tiles use Cloudinary thumbnails (480px wide, automatic format; GIFs show their first frame). Full-size images load only on the post page, and the lightbox opens the original.
- **Pages:** `/` (tiles), `/post/<id>/`, `/archive/` (text list by year and month), `/tags/` (cloud), `/themes/`, `/categories/`, `/navigate/` (search over posts, tags, themes and categories), `/feed.xml` (one Atom feed).
- **Tag, theme and category pages** come from front matter. Tags come from Tumblr. Add `themes: [name]` or `categories: [name]` to any post (by hand or in a CMS) and the pages appear on the next build. Tags used only once get no page of their own (about 1,800 of them), but they stay searchable and listed under "all tags" on `/tags/`.
- Code: `_plugins/blog.rb` (taxonomy pages, image sizing), `assets/js/blog.js` (tiles, masonry, load-more), `lightbox.js`, `navigate.js`.

## Run the importer

Set two environment variables (never commit them):

- `TUMBLR_API_KEY`: a Tumblr OAuth consumer key (read-only is enough).
- `CLOUDINARY_URL`: `cloudinary://<api_key>:<api_secret>@<cloud_name>` (not needed with `--dry-run`).

```bash
uv run scripts/tumblr_to_jekyll.py --dry-run --max-posts 50
```

```bash
uv run scripts/tumblr_to_jekyll.py --out glosse-me
```

## Build and preview

```bash
cd glosse-me && bundle install && bundle exec jekyll serve
```

## Deploy

Repo **Settings → Pages → Build and deployment → Source: GitHub Actions**. Pushes to `main` build and deploy; pull requests only build. The site is at `https://jubilancy.github.io/tumblr-to-jekyll/` for now. To move it to `blog.glosse.me`, set `url: https://blog.glosse.me` and `baseurl: ""` in `glosse-me/_config.yml`, add a `CNAME` file, and point a `blog` DNS record at GitHub Pages.

## Status

- Import: 305 posts and 900 images, 0 errors.
- Theme: built and tested in a browser (home, grid, post, lightbox, tags, search, mobile).
- Not yet imported: 338 posts that appear in the Tumblr export but are no longer on the live blog (plan: import as hidden posts).
- Not yet built: the admin editor, and the final cutover.
