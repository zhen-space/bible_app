import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Student normal-page route: iOS/macOS use CupertinoPageRoute so the platform
/// owns the interactive leading-edge back gesture; Android/Web keep Material
/// routing and browser-back behavior. Reader routes intentionally do not use
/// this helper because horizontal gestures inside Reader turn chapters.
Route<T> studentPageRoute<T>({required WidgetBuilder builder}) {
  final cupertino = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);
  if (cupertino) return CupertinoPageRoute<T>(builder: builder);
  return MaterialPageRoute<T>(builder: builder);
}
