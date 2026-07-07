import 'package:flutter/foundation.dart';

/// Bump this to tell the Home feed to reload (e.g. after publishing a post).
final ValueNotifier<int> feedRefresh = ValueNotifier<int>(0);
