# tumblr-to-jekyll

Move a Tumblr blog (posts, reblogs, asks) to a self-hosted Jekyll site, with images on Cloudinary.
First target: [fromdaysoff.tumblr.com](https://fromdaysoff.tumblr.com/) to glosse.me.

## What's here

| Path | What it is |
|---|---|
| `scripts/tumblr_to_jekyll.py` | Importer. Pages through the Tumblr API, writes one Jekyll post per Tumblr post, uploads every image to Cloudinary as `tumblr/fromdaysoff/<post-id>_<n>`. Resumable, writes a `results-log-*.txt` on every run. |
| `glosse-me/` | The Jekyll site: layouts, styles, and the 305 imported posts in `_posts/`. |
| `glosse-me/raw/` | Each post's full Tumblr API response, so posts can be re-rendered without calling the API again. |
| `glosse-me/state.json` | Importer progress, used to resume. |

Post URLs follow Tumblr's pattern: `/post/<tumblr id>/`.

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

## Build the site

```bash
cd glosse-me && bundle install && bundle exec jekyll build
```

## Status

- Import: 305 posts and 900 images, 0 errors.
- Theme: builds; a plain first pass that still needs design direction.
- Not yet imported: 338 posts that appear in the Tumblr export but are no longer on the live blog (plan: import as hidden posts).
- Not yet built: the admin editor (admin.glosse.me), redirects from the old Tumblr blog, and the final cutover.
