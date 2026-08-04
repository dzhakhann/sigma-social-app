// Firebase Cloud Messaging service worker — what actually lets a push
// notification show up while the Sigmacta tab (or the whole browser) is
// closed. Without this file, FCM works ONLY while the tab is open and
// foregrounded (which the app already covers via the live socket connection
// and the in-app island banner — see NotificationService/MainScreen).
//
// REQUIRES the same Firebase web config as lib/main.dart's kIsWeb branch —
// see the REPLACE_ME markers there. Both have to point at the same Firebase
// project or messages silently won't arrive.
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'REPLACE_ME',
  authDomain: 'sigmacta-67de6.firebaseapp.com',
  projectId: 'sigmacta-67de6',
  messagingSenderId: 'REPLACE_ME',
  appId: 'REPLACE_ME',
});

const messaging = firebase.messaging();

// Renders the notification when the message arrives with the app fully
// closed. Foreground messages are handled entirely in Dart (PushService /
// NotificationService) — this only fires for the background case.
messaging.onBackgroundMessage((payload) => {
  const data = payload.data || {};
  const title = data.from_username || 'Sigmacta';
  const body = data.message || '';
  self.registration.showNotification(title, {
    body,
    icon: '/icons/Icon-192.png',
    data,
  });
});

// Tapping the OS notification focuses (or opens) the app tab.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((all) => {
      for (const c of all) {
        if ('focus' in c) return c.focus();
      }
      if (clients.openWindow) return clients.openWindow('/');
    })
  );
});
