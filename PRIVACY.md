# Privacy

FlickPic does not operate a server and does not collect, sell, or share
analytics, identifiers, usage history, or photo-library contents.

The app stores reviewed photo identifiers, pending-deletion identifiers,
preferences, and a derived image-category cache locally on the device. The
category cache contains an asset identifier, receipt/document/screenshot/other
category, confidence, versioning dates, classifier version, and processing
status. It does not store thumbnails, OCR text, embeddings, or Apple Vision's
complete classification results.

FlickPic uses Apple PhotoKit to read only media the user authorized and to
request deletion only after the user reviews and confirms the pending queue.
PhotoKit may download a small authorized representation from the user's own
iCloud Photos library when the user starts an explicit category scan or when
iOS runs eligible background work.

Apple Vision image classification and text recognition run on-device. FlickPic
does not send images to a developer-controlled service. A photo, video, or
recognized text leaves the app only when the user explicitly chooses a
destination in the system share sheet.

This document should be reviewed and published at the final support URL before
App Store submission.
