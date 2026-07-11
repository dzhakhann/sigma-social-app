import 'package:flutter/material.dart';
import '../theme/brutal_theme.dart';

// ════════════════════════════════════════════════════════════════════════════
//  LOCALIZATION  ·  RU / EN
//  Usage:  context.t('home')   →  "Главная" or "Home"
// ════════════════════════════════════════════════════════════════════════════
class S {
  static const Map<String, Map<String, String>> _v = {
    'en': {
      'appName': 'Sigmacta',
      'tagline': 'your space',
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
      'boost': 'Resonance',
      'amplify': 'Amplify',
      'repost': 'Repost',
      'share': 'Share',
      'reposted': 'Reposted to your feed',
      'linkCopied': 'Copied to clipboard',
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
      'navigation': 'Navigation side',
      'navRight': 'Right',
      'navLeft': 'Left',
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
      'navHome': 'Home', 'navPodcasts': 'Podcasts', 'navChat': 'Chat',
      'navProfile': 'Profile',
      'morning': 'Good morning', 'afternoon': 'Good afternoon',
      'evening': 'Good evening', 'night': 'Good night',
      'aiTip': 'AI tip for today', 'aiThinking': 'AI is thinking…',
      'aiEmpty': 'Set a yearly goal and I will suggest where to start today.',
      'myGoals': 'My goals', 'seeAll': 'All', 'active': 'active',
      'setGoal': 'Set a goal', 'noGoals': 'No goals yet',
      'noGoalsHint': 'Set your first yearly goal with the + button',
      'yearProgress': 'Your year progress', 'goalsDoneLbl': 'Goals completed',
      'avgProgress': 'Average progress', 'horoWeek': 'Weekly horoscope',
      'horoFill': 'Add your birthday in the profile to see your horoscope and weekly forecast.',
      'loadingForecast': 'Loading forecast…',
      'podcasts': 'Podcasts', 'pBrowse': 'Browse', 'pHistory': 'History',
      'pPlaylist': 'Playlist', 'pLiked': 'Liked',
      'pSearch': 'Search podcasts worldwide…',
      'pCreatePlaylist': 'Create playlist', 'pNothing': 'Nothing found',
      'pEpisodesNone': 'No episodes found',
      'pFirstPlaylist': 'Create your first playlist',
      'aura': 'Aura', 'followers': 'Followers', 'postsLbl': 'Posts',
      'following': 'Following', 'aboutMe': 'About', 'info': 'Information',
      'goalsYear': 'Yearly goals', 'completed': 'completed',
      'goalsHidden': 'goals are private',
      'addFriend': 'Add', 'friends': 'Friends', 'messageBtn': 'Message',
      'tabPosts': 'Posts', 'tabReposts': 'Reposts', 'tabStories': 'Stories',
      'menu': 'Menu', 'mYearReport': 'Year report', 'mSaved': 'Saved',
      'mHelp': 'Help', 'comingSoon': 'Coming soon',
      'messageHint': 'Message…', 'online': 'online',
      'obTitleNew': 'Tell us about you', 'obTitleEdit': 'Edit profile',
      'later': 'Later',
      'obIntro': 'Fill in your profile so people can get to know you better. The eye icon shows or hides a field on your profile.',
      'secName': 'Name', 'fFirst': 'First name', 'fLast': 'Last name',
      'fMiddle': 'Middle name', 'secBasic': 'Basics',
      'fBirthday': 'Date of birth (e.g. 05.07.2000)', 'fGender': 'Gender',
      'fBirthplace': 'Place of birth', 'secEdu': 'Education & work',
      'fEducation': 'Education (school, university)', 'fWork': 'Workplace',
      'secMore': 'More', 'fWebsite': 'Links (website, socials)',
      'fRelationship': 'Relationship status',
      'fSkills': 'Skills & hobbies: languages, subjects, sports…',
      'fAbout': 'About', 'saveContinue': 'Save and continue',
      'hiddenTip': 'Hidden — tap to show', 'visibleTip': 'Visible to everyone',
      // chat
      'chatTitle': 'Messages', 'noChats': 'No chats yet.\nOpen someone\'s profile and tap Message.',
      'camera': 'Camera', 'gallery': 'Gallery',
      'sendingPhoto': 'Sending photo…', 'sendingVideo': 'Sending video circle…',
      'sendingVoice': 'Sending voice…', 'noMessages': 'No messages yet',
      'editMsg': 'Edit message', 'deleteMsg': 'Delete', 'editMsgLabel': 'Edit',
      'slideCancel': 'Slide to cancel', 'editedMark': 'edited',
      // notifications
      'activityTitle': 'Activity', 'readAll': 'Read all',
      'tabAll': 'All', 'tabSubs': 'Subscriptions', 'tabReplies': 'Replies',
      'noNotifications': 'No notifications yet',
      // channels
      'channelsTitle': 'Channels',
      'channelsDesc': 'Subscribe to channels for a feed full of news, sport, movies, science and more — updated daily.',
      'subscribe': 'Subscribe', 'subscribed': 'Subscribed',
      // comments
      'editComment': 'Edit', 'deleteComment': 'Delete',
      'repliesLabel': 'Replies', 'noReplies': 'No replies yet. Be first!',
      'editingComment': 'Editing comment',
      // compose / main
      'newPost': 'New post', 'newPostSub': 'A post on your profile — visible to followers',
      'newGoal': 'New goal', 'newGoalSub': 'Set a goal for the year',
      // goals extra
      'addGoalBtn': 'Add goal', 'saveBtn': 'Save', 'goalDoneBtn': 'Done ✓',
      'postponeBtn': 'Postpone', 'deleteBtn': 'Delete',
      'goalCompletedMsg': 'Goal completed! 🎉',
      'noGoalsYear': 'No goals for {year} yet',
      'noGoalsYearHint': 'Set your first goal — we\'ll compile a nice report at year\'s end',
      'progressLbl': 'Progress: {n}%', 'postponedLbl': 'postponed',
      // admin
      'adminTitle': 'Admin panel', 'areYouSure': 'Are you sure?',
      'cancelBtn': 'Cancel', 'yesBtn': 'Yes',
      'noUsers': 'No users', 'noPosts': 'No posts',
      // matrix / general
      'newChatTitle': 'New chat', 'noUsersFound': 'No users found',
      'couldNotOpen': 'Could not open chat',
      // podcast extra
      'episodesCount': '{n} episodes', 'newPlaylistTitle': 'New playlist',
      'deletePlaylistQ': 'Delete "{name}"?', 'playlistEmpty': 'Playlist empty',
      'addToPlaylist': 'Add to playlist', 'createNewPlaylist': 'Create new playlist',
      'addedToPlaylist': 'Added to "{name}"',
      // general
      'ok': 'OK', 'close': 'Close', 'back': 'Back',
      // ai
      'aiAssistant': 'AI Assistant', 'nothingPlaying': 'Nothing is playing',
      // reels
      'reelsTitle': 'Reels', 'noReels': 'No reels yet',
      'uploadFirstReel': 'Upload first reel', 'addCaption': 'Add caption',
      'upload': 'Upload', 'uploadingReel': 'Uploading reel…',
      'reelUploaded': 'Reel uploaded!',
      // goals screen
      'newGoalYear': 'New goal for {year}', 'goalHint': 'E.g.: learn English',
      'myGoalsTitle': 'My goals · {year}', 'myYearHeader': 'Your {year}',
      'doneOfGoals': '{done} of {total} goals done',
      'motivStart': 'Start with one goal ✨',
      'motivHigh': 'Almost there — keep going! 🔥',
      'motivMid': 'Great pace, keep it up! 💪',
      'motivLow': 'Good start, don\'t slow down 🚀',
      'motivStep': 'Take one step today 👟',
      'goalFabBtn': 'Goal', 'postponedLabel': 'postponed',
      // search
      'searchPeople': 'Search by name or @username…',
      // podcasts
      'nothingPlayingHint': 'Open a show and tap Play',
      'pHistoryEmpty': 'Your recent listens will appear here',
      'playlistNameHint': 'Name', 'episodesSuffix': '{n} ep.',
      'playlistCreated': 'Playlist "{name}" created',
      // matrix
      'matrixChat': 'Matrix chat',
      // compose
      'newBranch': 'New thread',
      // profile share
      'profileShareTitle': 'Profile exchange',
      'qrScanHint': 'Point at someone\'s QR code',
      // gif picker
      'gifPickerTitle': 'Pick GIF',
      // pro
      'proTitle': 'Sigmacta Pro', 'proBuyBtn': 'Get Pro',
      // misc
      'helpTitle': 'Help', 'deleteStoryQ': 'Delete story?',
      'selectUser': 'Select User',
      // search extra
      'nothingFound': 'Nothing found', 'profileExchange': 'Profile exchange',
      'profileExchangeHint': 'Hold phones together — swap accounts',
      'suggestedPeople': 'People worth adding', 'noSuggestions': 'No suggestions yet',
      // podcasts
      'playlistEmptyHint': 'Playlist is empty',
      // story
      'replySent': 'Reply sent',
      // year review
      'myYearOf': 'My {year}', 'couldNotRender': 'Could not render image',
      'goalsSet': 'of {total} set · {rate}% done',
      'whatYouAchieved': 'WHAT YOU ACHIEVED',
      // video podcast
      'videoLoadError': 'Could not load video',
      // pro screen
      'proSubtitle': 'Unlock your max: verified badge, clean UI and more AI.',
      'proSettingsSub': 'Badge · no ads · more AI',
      // ai reco card
      'aiRecoTitle': 'AI recommendations', 'aiAsk': 'Ask →',
      'aiRecoLoading': 'Gathering tips from your goals…',
      'aiRecoGoals': 'My goals and year report →',
      // login screen
      'createAccount': 'Create account', 'signIn': 'Sign in',
      'signInSubtitle': 'Sign in with your username',
      'registerSubtitle': 'No email. No phone. Just a username.',
      'confirmPassword': 'Confirm password',
      'privacyNote': 'We don\'t collect your personal data. No email, no phone — your identity is just your username.',
      'passMismatch': 'Passwords do not match',
      'alreadyHave': 'Already have an account? ',
      'registrationFailed': 'Registration failed',
      'loginFailed': 'Login failed',
      // hints
      'aiAskHint': 'Ask about your goal…', 'whatsNew': "What's new?",
      'gifSearch': 'Search GIF…', 'replyHint': 'Reply…',
      'editCommentHint': 'Edit comment…', 'writeReplyHint': 'Write a reply…',
      'matrixUsername': 'Matrix username', 'matrixNoAt': 'without @',
      'matrixPassword': 'Matrix password',
      // goal categories
      'cat_study': 'Study', 'cat_career': 'Career', 'cat_health': 'Health',
      'cat_finance': 'Finance', 'cat_relationships': 'Relationships',
      'cat_hobby': 'Hobby', 'cat_personal': 'Personal', 'cat_other': 'Other',
      // podcast categories
      'pc_top': 'Top', 'pc_news': 'News', 'pc_business': 'Business',
      'pc_tech': 'Technology', 'pc_sport': 'Sport', 'pc_health': 'Health',
      'pc_comedy': 'Comedy', 'pc_education': 'Education', 'pc_motivation': 'Motivation',
      'pc_default_term': 'podcast',
      'mainDirection': 'Main focus',
      'goalReached': 'goal achieved', 'goalsReached': 'goals achieved',
      'episode': 'Episode',
      // pro benefits
      'proB1t': 'Verified badge', 'proB1d': 'Blue checkmark next to your name — trust and status.',
      'proB2t': 'No ads', 'proB2d': 'Clean feed and profile without promos.',
      'proB3t': 'More AI', 'proB3d': 'Extended limits for AI coach and recommendations.',
      'proB4t': 'Advanced goal analytics', 'proB4d': 'Deep progress stats and charts.',
      'proB5t': 'Exclusive themes and frames', 'proB5d': 'Profile styling available only to Pro.',
      // ai chat
      'aiGreeting': 'Hi! I\'m your Sigmacta AI coach. Tell me about your goal — I\'ll help break it into steps and suggest where to start.',
      'typing': 'typing…',
      // chats / chat detail
      'noMsgsShort': 'No messages',
      'lastSeenMin': 'last seen {n} min ago', 'lastSeenAt': 'last seen at {t}',
      'lastSeenDate': 'last seen {d}',
      // compose
      'photoBtn': 'Photo', 'cameraBtn': 'Camera',
      'publicPost': 'Public post', 'publishBtn': 'Publish',
      // gif
      'gifUnavailable': 'GIFs unavailable.\nAdd a Giphy key on the server (GIPHY_API_KEY).',
      // goals
      'myYearTooltip': 'My year',
      // help
      'helpBody': 'Sigmacta is a social network for personal growth.\n\nSet yearly goals, track progress, publish posts on your profile, listen to podcasts and chat.\n\nQuestions: dzhakhann@gmail.com',
      // onboarding
      'gMale': 'Male', 'gFemale': 'Female', 'gOther': 'Other',
      'rSingle': 'Single', 'rRelationship': 'In a relationship',
      'rMarried': 'Married', 'rComplicated': 'It\'s complicated',
      // profile
      'chatFallback': 'Chat', 'noReposts': 'No reposts yet', 'noPostsYet': 'No posts yet',
      'repostFrom': 'Repost', 'storiesArchiveHint': 'Your past stories will be stored here',
      'noStories': 'No stories',
      // story
      'storyReplyPrefix': 'Reply to story: ', 'storyLiked': '❤️ liked your story',
      'sentMark': '❤️ Sent',
      // qr share
      'myQr': 'My QR', 'scanQr': 'Scan',
      'profileFallback': 'Profile',
      'qrShowHint': 'Show this code — let them scan it to open your profile and follow you.',
      // pro payment
      'proComingSoon': 'Payments arrive with the Google Play release. Soon!',
      'proFootnote': 'The subscription activates via Google Play after the app is published. Payment and management — in your Google Play account.',
      // search
      'exchangeSoon': 'Coming soon: profile exchange nearby — hold phones together (Bluetooth).',
      // misc words
      'ofWord': 'of', 'subscribersWord': 'subscribers', 'sendingMsg': 'Sending…',
      'podcastFallback': 'Podcast',
      // video circle recorder
      'releaseToSend': 'Release to send', 'holdToRecord': 'Hold the button to record',
      // video
      'videoFallback': 'Video',
      // year review
      'publishedToStory': 'Published to your story ✓',
      'publishFailed': 'Could not publish',
      'publishing': 'Publishing…', 'publishToStory': 'Publish to story',
      'yearTip': 'Tip: save the image and post it to your Instagram story — the final full-year report arrives in December.',
      'yearEmpty': 'Set goals for {year} —\nand your beautiful\nyear report will appear here ✨',
      // ai
      'aiUnavailable': 'AI is unavailable.',
      // notifications (client-side localization by type)
      'nLike': '{u} liked your post',
      'nComment': '{u} commented on your post',
      'nFollow': '{u} started following you',
      'nRepost': '{u} reposted',
      'nChannelPost': 'New post in {u}',
      'viewMyStories': 'View my stories',
      'cropHint': 'Drag and pinch to choose the visible area',
      // story extras
      'reportBtn': 'Report', 'reportSent': 'Report sent. We\'ll review this story.',
      'shareBtn': 'Share', 'copyLink': 'Copy link',
      'shareStoryText': 'Check out this story on Sigmacta',
      // settings extras
      'secAppearance': 'Appearance', 'secAccount': 'Account', 'secAbout': 'About',
      'editProfileBtn': 'Edit profile',
      'privacyPolicy': 'Privacy Policy', 'termsOfUse': 'Terms of Use',
      'appVersion': 'Version',
      'deleteAccount': 'Delete account',
      'deleteAccountWarn': 'This will permanently delete your account, posts, messages and goals. This cannot be undone.',
      'deleteAccountConfirm': 'Delete forever',
      'accountDeleted': 'Account deleted',
      // goals extras
      'fAll': 'All', 'fActive': 'Active', 'fDone': 'Done', 'fPaused': 'Postponed',
      'plus10': '+10%',
    },
    'ru': {
      'appName': 'Sigmacta',
      'tagline': 'твоё пространство',
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
      'boost': 'Резонанс',
      'amplify': 'Усилить',
      'repost': 'Репост',
      'share': 'Поделиться',
      'reposted': 'Репост добавлен в твою ленту',
      'linkCopied': 'Скопировано',
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
      'navigation': 'Сторона навигации',
      'navRight': 'Справа',
      'navLeft': 'Слева',
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
      'navHome': 'Главная', 'navPodcasts': 'Подкасты', 'navChat': 'Чат',
      'navProfile': 'Профиль',
      'morning': 'Доброе утро', 'afternoon': 'Добрый день',
      'evening': 'Добрый вечер', 'night': 'Доброй ночи',
      'aiTip': 'Совет ИИ на сегодня', 'aiThinking': 'ИИ думает…',
      'aiEmpty': 'Поставь цель на год — и я подскажу, с чего начать сегодня.',
      'myGoals': 'Мои цели', 'seeAll': 'Все', 'active': 'активных',
      'setGoal': 'Поставить цель', 'noGoals': 'Пока нет целей',
      'noGoalsHint': 'Поставь первую цель на год через кнопку +',
      'yearProgress': 'Твой прогресс за год', 'goalsDoneLbl': 'Целей выполнено',
      'avgProgress': 'Средний прогресс', 'horoWeek': 'Гороскоп на неделю',
      'horoFill': 'Заполни дату рождения в профиле — покажу твой гороскоп и прогноз на неделю.',
      'loadingForecast': 'Загружаю прогноз…',
      'podcasts': 'Подкасты', 'pBrowse': 'Обзор', 'pHistory': 'История',
      'pPlaylist': 'Плейлист', 'pLiked': 'Нравится',
      'pSearch': 'Искать подкасты со всего мира…',
      'pCreatePlaylist': 'Создать плейлист', 'pNothing': 'Ничего не найдено',
      'pEpisodesNone': 'Эпизоды не найдены',
      'pFirstPlaylist': 'Создай свой первый плейлист',
      'aura': 'Aura', 'followers': 'Подписчики', 'postsLbl': 'Посты',
      'following': 'Подписки', 'aboutMe': 'О себе', 'info': 'Информация',
      'goalsYear': 'Цели года', 'completed': 'выполнено',
      'goalsHidden': 'сами цели скрыты',
      'addFriend': 'Добавить', 'friends': 'В друзьях', 'messageBtn': 'Написать',
      'tabPosts': 'Посты', 'tabReposts': 'Репосты', 'tabStories': 'История',
      'menu': 'Меню', 'mYearReport': 'Годовой отчёт', 'mSaved': 'Сохранённое',
      'mHelp': 'Помощь', 'comingSoon': 'Скоро будет доступно',
      'messageHint': 'Сообщение…', 'online': 'в сети',
      'obTitleNew': 'Расскажи о себе', 'obTitleEdit': 'Редактировать профиль',
      'later': 'Позже',
      'obIntro': 'Заполни профиль, чтобы тебя было интереснее узнать. Значок «глаз» у поля — показать в профиле или скрыть.',
      'secName': 'Имя', 'fFirst': 'Имя', 'fLast': 'Фамилия',
      'fMiddle': 'Отчество', 'secBasic': 'Основное',
      'fBirthday': 'Дата рождения (напр. 05.07.2000)', 'fGender': 'Пол',
      'fBirthplace': 'Место рождения', 'secEdu': 'Образование и работа',
      'fEducation': 'Учёба (школа, университет)', 'fWork': 'Место работы',
      'secMore': 'Дополнительно', 'fWebsite': 'Ссылки (сайт, соцсети)',
      'fRelationship': 'Семейное положение',
      'fSkills': 'Способности и хобби: языки, предметы, спорт…',
      'fAbout': 'О себе', 'saveContinue': 'Сохранить и продолжить',
      'hiddenTip': 'Скрыто — нажми чтобы показать', 'visibleTip': 'Видно всем',
      // chat
      'chatTitle': 'Сообщения', 'noChats': 'Пока нет чатов.\nОткрой профиль человека и нажми «Написать».',
      'camera': 'Камера', 'gallery': 'Галерея',
      'sendingPhoto': 'Отправляем фото…', 'sendingVideo': 'Отправляем видеокружок…',
      'sendingVoice': 'Отправляем голосовое…', 'noMessages': 'Пока нет сообщений',
      'editMsg': 'Редактировать', 'deleteMsg': 'Удалить', 'editMsgLabel': 'Редактировать',
      'slideCancel': 'Проведи для отмены', 'editedMark': 'изм.',
      // notifications
      'activityTitle': 'Активность', 'readAll': 'Прочитать всё',
      'tabAll': 'Все', 'tabSubs': 'Подписки', 'tabReplies': 'Ответы',
      'noNotifications': 'Уведомлений пока нет',
      // channels
      'channelsTitle': 'Каналы',
      'channelsDesc': 'Подпишись на каналы — новости, спорт, кино, наука и всё что интересно, обновляется каждый день.',
      'subscribe': 'Подписаться', 'subscribed': 'Подписан',
      // comments
      'editComment': 'Редактировать', 'deleteComment': 'Удалить',
      'repliesLabel': 'Ответы', 'noReplies': 'Пока нет ответов. Будь первым!',
      'editingComment': 'Редактирование комментария',
      // compose / main
      'newPost': 'Публикация', 'newPostSub': 'Пост в вашем профиле — увидят подписчики',
      'newGoal': 'Новая цель', 'newGoalSub': 'Поставить цель на год',
      // goals extra
      'addGoalBtn': 'Добавить цель', 'saveBtn': 'Сохранить', 'goalDoneBtn': 'Выполнено ✓',
      'postponeBtn': 'Отложить', 'deleteBtn': 'Удалить',
      'goalCompletedMsg': 'Цель выполнена! 🎉',
      'noGoalsYear': 'Пока нет целей на {year}',
      'noGoalsYearHint': 'Поставь первую цель — в конце года соберём красивый отчёт',
      'progressLbl': 'Прогресс: {n}%', 'postponedLbl': 'отложена',
      // admin
      'adminTitle': 'Панель администратора', 'areYouSure': 'Вы уверены?',
      'cancelBtn': 'Отмена', 'yesBtn': 'Да',
      'noUsers': 'Нет пользователей', 'noPosts': 'Нет постов',
      // matrix / general
      'newChatTitle': 'Новый чат', 'noUsersFound': 'Пользователи не найдены',
      'couldNotOpen': 'Не удалось открыть чат',
      // podcast extra
      'episodesCount': '{n} эпизодов', 'newPlaylistTitle': 'Новый плейлист',
      'deletePlaylistQ': 'Удалить «{name}»?', 'playlistEmpty': 'Плейлист пуст',
      'addToPlaylist': 'Добавить в плейлист', 'createNewPlaylist': 'Создать новый плейлист',
      'addedToPlaylist': 'Добавлено в «{name}»',
      // general
      'ok': 'ОК', 'close': 'Закрыть', 'back': 'Назад',
      // ai
      'aiAssistant': 'ИИ-ассистент', 'nothingPlaying': 'Ничего не воспроизводится',
      // reels
      'reelsTitle': 'Рилсы', 'noReels': 'Рилсов пока нет',
      'uploadFirstReel': 'Загрузить первый рилс', 'addCaption': 'Подпись',
      'upload': 'Загрузить', 'uploadingReel': 'Загружаем рилс…',
      'reelUploaded': 'Рилс загружен!',
      // goals screen
      'newGoalYear': 'Новая цель на {year}', 'goalHint': 'Например: выучить английский',
      'myGoalsTitle': 'Мои цели · {year}', 'myYearHeader': 'Твой {year}',
      'doneOfGoals': '{done} из {total} целей выполнено',
      'motivStart': 'Начни с одной цели ✨',
      'motivHigh': 'Ты почти у цели — держись! 🔥',
      'motivMid': 'Отличный темп, продолжай! 💪',
      'motivLow': 'Хорошее начало, не сбавляй 🚀',
      'motivStep': 'Сделай сегодня один шаг 👟',
      'goalFabBtn': 'Цель', 'postponedLabel': 'отложена',
      // search
      'searchPeople': 'Найти по имени или @нику…',
      // podcasts
      'nothingPlayingHint': 'Открой подкаст и нажми «Играть»',
      'pHistoryEmpty': 'Здесь будет то, что ты недавно слушал',
      'playlistNameHint': 'Название', 'episodesSuffix': '{n} эп.',
      'playlistCreated': 'Создан плейлист «{name}»',
      // matrix
      'matrixChat': 'Matrix чат',
      // compose
      'newBranch': 'Новая ветка',
      // profile share
      'profileShareTitle': 'Обмен профилем',
      'qrScanHint': 'Наведи на QR другого человека',
      // gif picker
      'gifPickerTitle': 'Выбрать GIF',
      // pro
      'proTitle': 'Sigmacta Pro', 'proBuyBtn': 'Оформить Pro',
      // misc
      'helpTitle': 'Помощь', 'deleteStoryQ': 'Удалить историю?',
      'selectUser': 'Выбрать пользователя',
      // search extra
      'nothingFound': 'Ничего не найдено', 'profileExchange': 'Обмен профилями',
      'profileExchangeHint': 'Поднеси телефоны — обменяйтесь аккаунтами',
      'suggestedPeople': 'Люди, которых стоит добавить', 'noSuggestions': 'Пока некого предложить',
      // podcasts
      'playlistEmptyHint': 'Плейлист пуст',
      // story
      'replySent': 'Ответ отправлен',
      // year review
      'myYearOf': 'Мой {year}', 'couldNotRender': 'Не удалось собрать картинку',
      'goalsSet': 'из {total} поставленных · {rate}% выполнено',
      'whatYouAchieved': 'ЧЕГО ТЫ ДОБИЛСЯ',
      // video podcast
      'videoLoadError': 'Не удалось загрузить видео',
      // pro screen
      'proSubtitle': 'Раскрой максимум: статус, чистый интерфейс и больше ИИ.',
      'proSettingsSub': 'Галочка · без рекламы · больше ИИ',
      // ai reco card
      'aiRecoTitle': 'Рекомендации ИИ', 'aiAsk': 'Спросить →',
      'aiRecoLoading': 'Собираю советы по твоим целям…',
      'aiRecoGoals': 'Мои цели и годовой отчёт →',
      // login screen
      'createAccount': 'Создать аккаунт', 'signIn': 'Войти',
      'signInSubtitle': 'Войдите по никнейму',
      'registerSubtitle': 'Без почты. Без телефона. Только никнейм.',
      'confirmPassword': 'Повторите пароль',
      'privacyNote': 'Мы не собираем ваши личные данные. Никакой почты и телефона — ваша личность это только никнейм.',
      'passMismatch': 'Пароли не совпадают',
      'alreadyHave': 'Уже есть аккаунт? ',
      'registrationFailed': 'Не удалось зарегистрироваться',
      'loginFailed': 'Не удалось войти',
      // hints
      'aiAskHint': 'Спроси о своей цели…', 'whatsNew': 'Что нового?',
      'gifSearch': 'Поиск GIF…', 'replyHint': 'Ответить…',
      'editCommentHint': 'Изменить комментарий…', 'writeReplyHint': 'Написать ответ…',
      'matrixUsername': 'Никнейм Matrix', 'matrixNoAt': 'без @',
      'matrixPassword': 'Пароль Matrix',
      // goal categories
      'cat_study': 'Учёба', 'cat_career': 'Карьера', 'cat_health': 'Здоровье',
      'cat_finance': 'Финансы', 'cat_relationships': 'Отношения',
      'cat_hobby': 'Хобби', 'cat_personal': 'Личное', 'cat_other': 'Другое',
      // podcast categories
      'pc_top': 'Топ', 'pc_news': 'Новости', 'pc_business': 'Бизнес',
      'pc_tech': 'Технологии', 'pc_sport': 'Спорт', 'pc_health': 'Здоровье',
      'pc_comedy': 'Комедия', 'pc_education': 'Образование', 'pc_motivation': 'Мотивация',
      'pc_default_term': 'подкаст',
      'mainDirection': 'Главное направление',
      'goalReached': 'цель достигнута', 'goalsReached': 'целей достигнуто',
      'episode': 'Эпизод',
      // pro benefits
      'proB1t': 'Галочка верификации', 'proB1d': 'Синяя галочка рядом с именем — доверие и статус.',
      'proB2t': 'Без рекламы', 'proB2d': 'Чистая лента и профиль без промо-блоков.',
      'proB3t': 'Больше ИИ', 'proB3d': 'Расширенные лимиты ИИ-коуча и рекомендаций.',
      'proB4t': 'Продвинутая аналитика целей', 'proB4d': 'Глубокая статистика прогресса и графики.',
      'proB5t': 'Эксклюзивные темы и рамки', 'proB5d': 'Оформление профиля, доступное только Pro.',
      // ai chat
      'aiGreeting': 'Привет! Я твой ИИ-коуч Sigmacta. Расскажи о своей цели — помогу разбить её на шаги и подскажу, с чего начать.',
      'typing': 'печатает…',
      // chats / chat detail
      'noMsgsShort': 'Нет сообщений',
      'lastSeenMin': 'был(а) {n} мин назад', 'lastSeenAt': 'был(а) в {t}',
      'lastSeenDate': 'был(а) {d}',
      // compose
      'photoBtn': 'Фото', 'cameraBtn': 'Камера',
      'publicPost': 'Публикация для всех', 'publishBtn': 'Опубликовать',
      // gif
      'gifUnavailable': 'GIF пока недоступны.\nДобавьте ключ Giphy на сервере (GIPHY_API_KEY).',
      // goals
      'myYearTooltip': 'Мой год',
      // help
      'helpBody': 'Sigmacta — соцсеть для личностного роста.\n\nСтавь цели на год, следи за прогрессом, публикуй посты в профиле, слушай подкасты и общайся в чате.\n\nВопросы: dzhakhann@gmail.com',
      // onboarding
      'gMale': 'Мужской', 'gFemale': 'Женский', 'gOther': 'Другое',
      'rSingle': 'Холост/Не замужем', 'rRelationship': 'В отношениях',
      'rMarried': 'Женат/Замужем', 'rComplicated': 'Всё сложно',
      // profile
      'chatFallback': 'Чат', 'noReposts': 'Пока нет репостов', 'noPostsYet': 'Пока нет публикаций',
      'repostFrom': 'Репост', 'storiesArchiveHint': 'Твои прошлые истории будут храниться здесь',
      'noStories': 'Нет историй',
      // story
      'storyReplyPrefix': 'Ответ на историю: ', 'storyLiked': '❤️ понравилась твоя история',
      'sentMark': '❤️ Отправлено',
      // qr share
      'myQr': 'Мой QR', 'scanQr': 'Сканировать',
      'profileFallback': 'Профиль',
      'qrShowHint': 'Покажи этот код — пусть отсканируют, чтобы открыть твой профиль и подписаться.',
      // pro payment
      'proComingSoon': 'Оплата подключится при публикации в Google Play. Скоро!',
      'proFootnote': 'Подписка активируется через Google Play после публикации приложения. Оплата и управление — в аккаунте Google Play.',
      // search
      'exchangeSoon': 'Скоро: обмен профилями рядом — поднеси телефоны друг к другу (Bluetooth).',
      // misc words
      'ofWord': 'из', 'subscribersWord': 'подписчиков', 'sendingMsg': 'Отправка…',
      'podcastFallback': 'Подкаст',
      // video circle recorder
      'releaseToSend': 'Отпустите, чтобы отправить', 'holdToRecord': 'Зажмите кнопку для записи',
      // video
      'videoFallback': 'Видео',
      // year review
      'publishedToStory': 'Опубликовано в твою сторис ✓',
      'publishFailed': 'Не удалось опубликовать',
      'publishing': 'Публикуем…', 'publishToStory': 'Опубликовать в сторис',
      'yearTip': 'Совет: сохрани картинку и выложи в сторис Instagram — финальный отчёт за весь год соберётся в декабре.',
      'yearEmpty': 'Поставь цели на {year} —\nи здесь появится твой\nкрасивый годовой отчёт ✨',
      // ai
      'aiUnavailable': 'ИИ недоступен.',
      // notifications (client-side localization by type)
      'nLike': '{u} понравился ваш пост',
      'nComment': '{u} прокомментировал(а) ваш пост',
      'nFollow': '{u} подписался(ась) на вас',
      'nRepost': '{u} сделал(а) репост',
      'nChannelPost': 'Новый пост в {u}',
      'viewMyStories': 'Мои истории',
      'cropHint': 'Перемещайте и масштабируйте, чтобы выбрать видимую область',
      // story extras
      'reportBtn': 'Пожаловаться', 'reportSent': 'Жалоба отправлена. Мы проверим эту историю.',
      'shareBtn': 'Поделиться', 'copyLink': 'Скопировать ссылку',
      'shareStoryText': 'Посмотри эту историю в Sigmacta',
      // settings extras
      'secAppearance': 'Оформление', 'secAccount': 'Аккаунт', 'secAbout': 'О приложении',
      'editProfileBtn': 'Редактировать профиль',
      'privacyPolicy': 'Политика конфиденциальности', 'termsOfUse': 'Условия использования',
      'appVersion': 'Версия',
      'deleteAccount': 'Удалить аккаунт',
      'deleteAccountWarn': 'Аккаунт, посты, сообщения и цели будут удалены навсегда. Это действие нельзя отменить.',
      'deleteAccountConfirm': 'Удалить навсегда',
      'accountDeleted': 'Аккаунт удалён',
      // goals extras
      'fAll': 'Все', 'fActive': 'Активные', 'fDone': 'Выполненные', 'fPaused': 'Отложенные',
      'plus10': '+10%',
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
