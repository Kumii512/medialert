# Notification Setup

This project uses two delivery paths:

- In-app local/web checks from Flutter.
- Server push dispatch from Firebase Cloud Functions (`sendMedicationReminders`) for background/closed-tab delivery.

## 1) Prerequisites

- Firebase project: `medialert-16f7d`
- Billing enabled (required for Cloud Scheduler-backed scheduled functions)
- Firebase CLI logged in (`firebase login`)
- Node.js 20+

## 2) Web VAPID key

Create/get your Web Push certificate key pair in Firebase Console:

- Firebase Console -> Project Settings -> Cloud Messaging -> Web configuration
- Copy **Web Push certificate key pair** public key

Run Flutter web with:

- `flutter run -d chrome --dart-define=FCM_WEB_VAPID_KEY=YOUR_PUBLIC_VAPID_KEY`

Build Flutter web with:

- `flutter build web --dart-define=FCM_WEB_VAPID_KEY=YOUR_PUBLIC_VAPID_KEY`

## 3) Deploy Functions

From repository root:

- `cd functions`
- `npm install`
- `cd ..`
- `firebase deploy --only functions`

The deployed function runs every minute:

- Function name: `sendMedicationReminders`
- Trigger: scheduler (`every 1 minutes`)

## 4) Deploy Hosting (if needed)

- `flutter build web --dart-define=FCM_WEB_VAPID_KEY=YOUR_PUBLIC_VAPID_KEY`
- `firebase deploy --only hosting`

## 5) Runtime behavior

- App stores FCM token in `users/{uid}/notificationTokens/{token}`.
- Token metadata includes platform and timezone offset.
- Scheduler reads:
  - `users/{uid}/medications`
  - `users/{uid}/settings/preferences`
  - `users/{uid}/notificationTokens`
- If a medication is due for a user timezone minute, FCM push is sent.
- Dispatch lock docs in `reminderDispatches/{dispatchKey}` prevent duplicates.

## 6) Quick verification

1. Sign in and allow notifications.
2. Add a medication scheduled 2-3 minutes ahead.
3. Keep browser tab in background or close it.
4. Wait for scheduled minute; verify push appears.
5. Check function logs:
   - `firebase functions:log --only sendMedicationReminders`

## 7) Notes

- Current scheduler logic uses medication `time` plus optional reminder interval from settings.
- If a token has no timezone metadata yet, scheduler falls back to UTC offset `0` for that token.
