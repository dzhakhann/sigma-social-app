import 'package:flutter/material.dart';
import '../theme/brutal_theme.dart';

// ════════════════════════════════════════════════════════════════════════════
//  LOCALIZATION  ·  RU / EN
//  Usage:  context.t('home')   →  "Главная" or "Home"
// ════════════════════════════════════════════════════════════════════════════
class S {
  static const Map<String, Map<String, String>> _v = {
    'en': {
      'appName': 'PULSE',
      'tagline': 'feel the pulse',
      // auth
      'email': 'Email',
      'password': 'Password',
      'login': 'Log in',
      'register': 'Create account',
      'enter': 'ENTER',
      'newHere': 'New here?',
      'welcome': 'Welcome back',
      'joinPulse': 'Join the pulse',
      // nav
      'home': 'Home',
      'discover': 'Discover',
      'chats': 'Chats',
      'alerts': 'Alerts',
      'me': 'Me',
      'settings': 'Settings',
      // home / feed
      'energy': 'ENERGY',
      'streak': 'streak',
      'days': 'days',
      'whatsUp': "What's pulsing?",
      'drop': 'DROP',
      'react': 'React',
      'comment': 'Comment',
      'boost': 'Boost',
      'nothingYet': 'Nothing pulsing yet',
      'beFirst': 'Drop the first pulse and light it up',
      'youReacted': 'Nice. +energy',
      'today': 'today',
      // settings
      'appearance': 'APPEARANCE',
      'theme': 'Theme',
      'language': 'Language',
      'russian': 'Русский',
      'english': 'English',
      'pickTheme': 'Pick your vibe',
      'pickLang': 'Choose language',
      'account': 'ACCOUNT',
      'logout': 'Log out',
      'preview': 'PREVIEW',
      'sampleCard': 'This is how your pulse looks.',
      'done': 'Done',
      // auth · recovery
      'username': 'Username',
      'newPassword': 'New password',
      'recoverLink': 'Forgot password?',
      'recoverTitle': 'Recover account',
      'recoverSubtitle':
          'Enter your username and your 12-word recovery phrase to set a new password.',
      'recoveryPhrase': 'Recovery phrase',
      'phraseHint': 'twelve words separated by spaces',
      'resetPassword': 'Reset password',
      'recoverFailed': 'Recovery failed',
      'fillAll': 'Fill in all fields',
      'passTooShort': 'Password must be at least 6 characters',
      'connError': 'Connection error',
      'recoveryTitle': 'Your recovery phrase',
      'recoverySubtitle':
          'These 12 words are the only way to recover your account. There is no email or phone to fall back on.',
      'recoveryWarning':
          'Write them down and keep them private. Anyone with this phrase can take over your account, and we can never show it again.',
      'copyPhrase': 'Copy phrase',
      'copied': 'Copied',
      'savedConfirm': "I've saved my recovery phrase in a safe place.",
      'enterApp': 'Enter Sigma',
      'continueBtn': 'Continue',
      // verify
      'verifyTitle': 'Confirm your phrase',
      'verifySubtitle':
          'Select the correct word for each position to confirm you saved your phrase.',
      'verifyConfirm': 'Confirm',
      'verifyWrong': 'Some words are wrong — try again.',
      'verifyReset': 'Reset',
      'verifyHint': 'Tap the words below in order',
      'wordLabel': 'Word',
    },
    'ru': {
      'appName': 'PULSE',
      'tagline': 'почувствуй ритм',
      // auth
      'email': 'Почта',
      'password': 'Пароль',
      'login': 'Войти',
      'register': 'Создать аккаунт',
      'enter': 'ВОЙТИ',
      'newHere': 'Впервые тут?',
      'welcome': 'С возвращением',
      'joinPulse': 'Присоединяйся',
      // nav
      'home': 'Главная',
      'discover': 'Обзор',
      'chats': 'Чаты',
      'alerts': 'События',
      'me': 'Я',
      'settings': 'Настройки',
      // home / feed
      'energy': 'ЭНЕРГИЯ',
      'streak': 'серия',
      'days': 'дн.',
      'whatsUp': 'Что пульсирует?',
      'drop': 'ОПУБЛИКОВАТЬ',
      'react': 'Реакция',
      'comment': 'Коммент',
      'boost': 'Буст',
      'nothingYet': 'Пока тишина',
      'beFirst': 'Опубликуй первый пульс и зажги ленту',
      'youReacted': 'Класс. +энергия',
      'today': 'сегодня',
      // settings
      'appearance': 'ОФОРМЛЕНИЕ',
      'theme': 'Тема',
      'language': 'Язык',
      'russian': 'Русский',
      'english': 'English',
      'pickTheme': 'Выбери свой вайб',
      'pickLang': 'Выбери язык',
      'account': 'АККАУНТ',
      'logout': 'Выйти',
      'preview': 'ПРЕВЬЮ',
      'sampleCard': 'Так выглядит твой пульс.',
      'done': 'Готово',
      // auth · recovery
      'username': 'Никнейм',
      'newPassword': 'Новый пароль',
      'recoverLink': 'Забыли пароль?',
      'recoverTitle': 'Восстановить аккаунт',
      'recoverSubtitle':
          'Введите никнейм и вашу фразу из 12 слов, чтобы задать новый пароль.',
      'recoveryPhrase': 'Фраза восстановления',
      'phraseHint': 'двенадцать слов через пробел',
      'resetPassword': 'Сбросить пароль',
      'recoverFailed': 'Не удалось восстановить',
      'fillAll': 'Заполните все поля',
      'passTooShort': 'Пароль минимум 6 символов',
      'connError': 'Ошибка соединения',
      'recoveryTitle': 'Ваша фраза восстановления',
      'recoverySubtitle':
          'Эти 12 слов — единственный способ вернуть аккаунт. Почты или телефона для восстановления нет.',
      'recoveryWarning':
          'Запишите их и храните в тайне. Любой, у кого есть эта фраза, получит доступ к аккаунту, а показать её снова мы не сможем.',
      'copyPhrase': 'Скопировать фразу',
      'copied': 'Скопировано',
      'savedConfirm': 'Я сохранил фразу восстановления в надёжном месте.',
      'enterApp': 'Войти в Sigma',
      'continueBtn': 'Далее',
      // verify
      'verifyTitle': 'Подтвердите фразу',
      'verifySubtitle':
          'Выберите правильное слово для каждой позиции, чтобы подтвердить, что вы сохранили фразу.',
      'verifyConfirm': 'Подтвердить',
      'verifyWrong': 'Некоторые слова неверны — попробуйте снова.',
      'verifyReset': 'Сбросить',
      'verifyHint': 'Нажимайте слова ниже по порядку',
      'wordLabel': 'Слово',
    },
  };

  static String t(BuildContext context, String key) {
    final lang = AppScope.of(context).lang;
    return _v[lang]?[key] ?? _v['en']?[key] ?? key;
  }
}

extension TrContext on BuildContext {
  String t(String key) => S.t(this, key);
}
