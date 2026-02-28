import 'dart:html' as html;

Future<bool> requestBrowserNotificationPermission() async {
  if (!html.Notification.supported) {
    return false;
  }

  if (html.Notification.permission == 'granted') {
    return true;
  }

  final permission = await html.Notification.requestPermission();
  return permission == 'granted';
}

Future<bool> canShowBrowserNotifications() async {
  return html.Notification.supported &&
      html.Notification.permission == 'granted';
}

Future<bool> showBrowserNotification({
  required String title,
  required String body,
}) async {
  if (!await canShowBrowserNotifications()) {
    return false;
  }

  html.Notification(title, body: body);
  return true;
}

String? getBrowserStorageItem(String key) {
  return html.window.localStorage[key];
}

void setBrowserStorageItem(String key, String value) {
  html.window.localStorage[key] = value;
}
