# 塩釜菜那 blog — iPhone app

A personal iOS reader for the public Traditional Chinese archive at [shiogama-nana-blog.vercel.app](https://shiogama-nana-blog.vercel.app). It is meant to be sideloaded with a free Apple ID. It is not set up for the App Store.

The app reads only the site's public JSON:

- `GET https://shiogama-nana-blog.vercel.app/api/posts` — the list, newest `post_date` first
- `GET https://shiogama-nana-blog.vercel.app/api/posts?id=<id>` — one post

Each post has `id`, `title_zh`, `title_jp`, `post_date`, `original_url`, and `body`. A body block is either `{ "type": "text", "text": "..." }` or `{ "type": "photo", "src": "/photos/…", "alt": "…", "width": …, "height": … }`. Photo `src` values are joined onto `https://shiogama-nana-blog.vercel.app`. The app also accepts a block whose type is `image`, in case that name is used later.

The app uses that public JSON only. It does not include an API key or a database client.

## What you can do

- Browse posts newest first, with the Chinese title, Japanese title, and date.
- Open a post. Line breaks in the text are kept, and photos sit between the paragraphs. Tap a photo for a full-screen view (pinch to zoom, swipe down to close).
- Open the official Japanese post in Safari.
- Search Chinese or Japanese titles.
- Pull down to refresh the list. Opening a post also refreshes that post.
- Read offline. The last successful list, each saved post, and photos that have already been downloaded stay on the phone. Pull to refresh again when you are back online.
- Light and dark appearance follow the iPhone setting (Settings > Display & Brightness).

Requires iOS 17 or later. No CocoaPods and no Swift package dependencies.

## Install on your iPhone

You need a Mac with Xcode 15 or later, a free Apple ID, and an iPhone on iOS 17 or later. The project is committed with an empty development team and the placeholder bundle id `com.example.shiogamananablog`, so the public repo does not contain an Apple ID or a team id.

1. Open `ios/ShiogamaNanaBlog.xcodeproj` in Xcode.
2. Select the **ShiogamaNanaBlog** target, then **Signing & Capabilities**. If your Apple ID is not in Xcode yet, add it under Xcode > Settings > Accounts. Choose your **Personal Team**. Change the bundle id to something unique (for example `com.yourname.shiogamananablog`). Leave the same bundle id in place afterwards so the on-phone cache is kept.
3. On the iPhone, enable **Developer Mode** (Settings > Privacy & Security > Developer Mode) and restart when asked.
4. Connect the iPhone, choose it as the run destination, and press **Run**.
5. If the phone says the developer is not trusted, open **Settings > General > VPN & Device Management**, trust the developer certificate, and open the app again.
6. A free Apple ID signature lasts about 7 days. When the app will no longer open, connect the phone and press **Run** again. You do not need to delete the app.

The iOS Simulator can run the same scheme without a paid account. A device build needs the Personal Team selected in step 2.
