# 塩釜菜那 blog — iPhone app

A personal iOS reader for the public Traditional Chinese archive at [shiogama-nana-blog.vercel.app](https://shiogama-nana-blog.vercel.app). It is meant to be sideloaded with a free Apple ID. It is not set up for the App Store.

The app reads only the site's public JSON:

- `GET https://shiogama-nana-blog.vercel.app/api/posts` — the list, newest `post_date` first
- `GET https://shiogama-nana-blog.vercel.app/api/posts?id=<id>` — one post
- `GET https://shiogama-nana-blog.vercel.app/api/instagram` — Instagram posts, newest `taken_at` first
- `GET https://shiogama-nana-blog.vercel.app/api/instagram?code=<code>` — one Instagram post

Each post has `id`, `title_zh`, `title_jp`, `post_date`, `original_url`, and `body`. A body block is either `{ "type": "text", "text": "..." }` or `{ "type": "photo", "src": "/photos/…", "alt": "…", "width": …, "height": … }`. Photo `src` values are joined onto `https://shiogama-nana-blog.vercel.app`. The app also accepts a block whose type is `image`, in case that name is used later. The live list includes photo blocks. If a list response does not, the gallery requests `GET /api/posts?id=<id>` for each post (up to four at a time) and stores the result on the phone.

An Instagram post has `code`, `taken_at`, `caption`, `permalink`, `slides`, `photo_count`, and `added_at`. A slide is a photo (`src` such as `/photos/ig/…/*.jpg`), a video, or a photo that was not archived (`src` null). Unknown slide types are kept so the page number still matches Instagram. Relative `src` paths are joined onto `https://shiogama-nana-blog.vercel.app`. The grid uses the smaller `-sm.webp` next to each `.jpg`, and the `.jpg` when that file is missing. Dates are shown in Japan time.

The app uses that public JSON only. It does not include an API key or a database client.

## What you can do

- Open 動態. Blog posts and Instagram posts share one timeline, newest day first (Instagram uses Japan time). On the same day the blog post comes first. Filter with 全部, Blog, or IG, and pick a date on the right. Cards use the same layout: a photo, the date as 2026.11.25, and a Blog or IG badge. An Instagram card shows the first caption lines, skipping spacer and hashtag-only lines, and a slide count when there is more than one. Tap a card to open the article or the Instagram post. Back returns to the same filters.
- Open a post from 動態. Line breaks in the text are kept, and photos sit between the paragraphs. Tap a photo for a full-screen view (pinch to zoom, swipe down to close). From that view you can save the photo to the iPhone photo library. iOS asks the first time. A full-size photo shows its small thumbnail, blurred, until the large image fades in.
- Open 相簿. Blog photos and archived Instagram photos are shown together as square thumbnails, newest day first. On the same day, blog photos come first. In 全部, Instagram tiles are marked IG. Tap a photo for the full-screen viewer. A blog photo can open its article. An Instagram photo can open its post in 動態, or open that slide on Instagram. You can also save the photo to the photo library.
- Open the official Japanese post in Safari.
- Search the feed for a Chinese or Japanese title, or for words in an Instagram caption.
- Pull down to refresh the list, the gallery, or Instagram. Opening a blog post or an Instagram post also refreshes that post.
- Read offline. The last successful list, each saved post, and photos that have already been downloaded stay on the phone. If the list response has no photo blocks, the app loads each post a few at a time, saves those posts, and the gallery still opens offline after that first successful load. The Instagram tab keeps the last successful post list the same way. Pull to refresh again when you are back online.
- Light and dark appearance follow the iPhone setting (Settings > Display & Brightness).

Requires iOS 17 or later. No CocoaPods and no Swift package dependencies.

## Install on your iPhone

You need a Mac with Xcode 15 or later, a free Apple ID, and an iPhone on iOS 17 or later. The project is committed with an empty development team and the placeholder bundle id `com.example.shiogamananablog`, so the public repo does not contain an Apple ID or a team id.

1. Open `ShiogamaNanaBlog.xcodeproj` in Xcode.
2. Select the **ShiogamaNanaBlog** target, then **Signing & Capabilities**. If your Apple ID is not in Xcode yet, add it under Xcode > Settings > Accounts. Choose your **Personal Team**. Change the bundle id to something unique (for example `com.yourname.shiogamananablog`). Leave the same bundle id in place afterwards so the on-phone cache is kept.
3. On the iPhone, enable **Developer Mode** (Settings > Privacy & Security > Developer Mode) and restart when asked.
4. Connect the iPhone, choose it as the run destination, and press **Run**.
5. If the phone says the developer is not trusted, open **Settings > General > VPN & Device Management**, trust the developer certificate, and open the app again.
6. A free Apple ID signature lasts about 7 days. When the app will no longer open, connect the phone and press **Run** again. You do not need to delete the app.

The iOS Simulator can run the same scheme without a paid account. A device build needs the Personal Team selected in step 2.
