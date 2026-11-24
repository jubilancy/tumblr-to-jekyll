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

## Admin (Sveltia CMS)

The editor lives at `/admin/` (for now `https://jubilancy.github.io/tumblr-to-jekyll/admin/`). Config: `glosse-me/admin/config.yml`.

**Sign in:** click **Sign In Using Access Token** and paste a GitHub personal access token. Create a fine-grained token for this repo only with **Contents: read and write** (GitHub: Settings → Developer settings → Personal access tokens → Fine-grained tokens). The **Sign In with GitHub** button needs an OAuth client, which isn't set up yet.

**What you can do**
- Write or edit posts (markdown editor); images are picked from, and uploaded to, Cloudinary.
- **Bulk edit:** open Posts, click **Edit** in the toolbar for a spreadsheet-style table of Published, Title, Themes and Categories. Changes save in one commit. Filter first to edit only some posts.
- **Themes and categories are comma-separated text** (`medieval art, maps`) because Sveltia can only bulk-edit single-value fields, not lists. Tags stay a list (edited per post). The theme reads either form.
- Hide a post by turning **Published** off; it stays in the repo but not on the site.
- Posts made in the CMS get their URL from the filename (`/post/<slug>/`) and their cover image and size from the first Cloudinary image in the body (the size is looked up from Cloudinary at build time).

Fields the CMS doesn't know about (`images`, `reblog_trail`, `id`, `permalink` on imported posts) are written back unchanged, per Sveltia's docs. Check the first commit it makes to a post to confirm nothing was dropped.

The Cloudinary **API key** in the config is public by design; never put the API secret there.

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
- Admin: Sveltia CMS configured and loads; not yet tried with a real sign-in and save.
- Not yet built: Cloudflare Access in front of the admin (needs the custom domain), and the final cutover.
