# MediAlert

MediAlert is a Flutter app for managing daily medicines with reminder notifications and a medication history log.

## Live Demo

- Web app: https://medialert-16f7d.web.app
- GitHub: https://github.com/Kumii512/medialert

## Main Features

- Add and manage medicine schedules
- Get reminder notifications for medicine times
- Mark medicines as taken with optional notes
- Track medication history by date
- Save and sync data using Firebase backend services

## Tech Stack

- Flutter (Dart)
- Firebase Auth
- Cloud Firestore
- Firebase Storage
- Firebase Cloud Messaging
- Firebase Hosting
- Cloud Functions (for scheduled notification flows)

## Run Locally

1. Install Flutter SDK
2. In the project folder, run:

```bash
flutter pub get
flutter run
```

## Build for Web

```bash
flutter build web --no-wasm-dry-run
```

## Deploy to Firebase Hosting

```bash
firebase deploy --only hosting
```

## Notification Setup

See [NOTIFICATION_SETUP.md](NOTIFICATION_SETUP.md) for Firebase Cloud Messaging setup, Cloud Functions deployment, and testing steps.
