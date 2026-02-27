importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyD3hQuZRkJCM0nKB7cDoYoPIU_B7GtPnDg',
  appId: '1:280439406383:web:8cd34d727ca7fdb8822bda',
  messagingSenderId: '280439406383',
  projectId: 'medialert-16f7d',
  authDomain: 'medialert-16f7d.firebaseapp.com',
  storageBucket: 'medialert-16f7d.firebasestorage.app',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title ?? 'Medication Reminder';
  const options = {
    body: payload.notification?.body ?? 'You have a medication reminder.',
    icon: '/icons/Icon-192.png',
    data: payload.data ?? {},
  };

  self.registration.showNotification(title, options);
});
