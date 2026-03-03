Future<bool> requestBrowserNotificationPermission() async => false;

Future<bool> canShowBrowserNotifications() async => false;

Future<bool> showBrowserNotification({
  required String title,
  required String body,
}) async => false;

String? getBrowserStorageItem(String key) => null;

void setBrowserStorageItem(String key, String value) {}
