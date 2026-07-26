# FlickPic

FlickPic is the development codename for a minimal, local-first iPhone photo
library cleaner. It lets you review one photo or video at a time, keep it,
queue it for deletion, or rescue useful information before deleting it.

Nothing is deleted on swipe. Pending items remain in an on-device queue until
the user reviews that queue and confirms the PhotoKit deletion request.

## Principles

- No account, backend, analytics, advertising, or subscription.
- No goals, streaks, achievements, reminders, or engagement mechanics.
- Review history, the deletion queue, and the derived category index stay
  on-device with SwiftData.
- Media types and facets such as GIFs, Live Photos, screenshots, panoramas,
  and screen recordings use PhotoKit metadata. Optional dynamic categories use
  Apple Vision image classification on small image representations.
- OCR uses Apple Vision on-device.
- Animated GIFs play in the review deck and zoomable inspector.
- Sharing occurs only through an explicit system share sheet.
- Hidden media is excluded and Favorites are protected by default.

## On-device categories

The home dashboard derives overlapping metadata buckets immediately and applies
the current review setup to their counts. After the user chooses Start
Categorizing, Apple Vision discovers arbitrary high-confidence tags. An image
can appear in several Vision categories, and category cards update as results
are saved.

The private Vision index runs incrementally while the app is active. It uses
local image data first, reduces concurrency while a review deck is open, pauses
for Low Power Mode or serious thermal pressure, and may retry iCloud-backed
images with an iOS background processing task. A category deck can be opened
before the scan finishes and adds new matching images without replacing the
current card.

The cache stores only asset identifiers, Vision tag identifiers and confidence,
asset modification dates, classifier version, status, and last-attempt date. It
does not store thumbnails, OCR text, or embeddings.

## Requirements

- Xcode 26 or newer
- iOS 18 or newer
- A physical iPhone is recommended for PhotoKit deletion and iCloud testing

Background classification uses the current development bundle identifier.
Update `BGTaskSchedulerPermittedIdentifiers` and
`ClassificationBackgroundScheduler.identifier` together when choosing the
public bundle identifier.

## Development

Open `FlickPic.xcodeproj` and run the `FlickPic` scheme. The first launch
explains the privacy model before requesting read/write Photos access.

Build from the command line:

```sh
xcodebuild \
  -project FlickPic.xcodeproj \
  -scheme FlickPic \
  -destination 'generic/platform=iOS Simulator' \
  build
```

The public product name, final bundle identifier, icon, and repository URL must
be selected before an App Store release. “FlickPic” is not the intended public
name.

## License

MIT
