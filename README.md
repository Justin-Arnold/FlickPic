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
- Screenshots use exact PhotoKit metadata. Receipts and documents use Apple
  Vision image classification on small image representations.
- OCR uses Apple Vision on-device.
- Sharing occurs only through an explicit system share sheet.
- Hidden media is excluded and Favorites are protected by default.

## On-device categories

Session setup can combine its date/review scope with a separate category:
Any, Screenshots, Receipts, Documents, or Other Photos. The categories are
exclusive in that order of priority.

FlickPic builds its private category index while the app is open and idle. It
uses local image data first, pauses during review sessions, Low Power Mode, and
serious thermal pressure, and may resume eligible work with an iOS background
processing task. Selecting an AI category explicitly retries small iCloud
representations with visible, cancellable progress.

The cache stores only the asset identifier, derived category, confidence,
asset modification date, classifier version, status, and last-attempt date. It
does not store thumbnails, OCR text, embeddings, or Vision's full taxonomy.

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
