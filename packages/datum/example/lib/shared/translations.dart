import 'package:example/i18n/strings.g.dart';
import 'package:signals_flutter/signals_flutter.dart';

/// Active translations; replaced with the device locale during init.
final translations = signal<Translations>(AppLocale.en.buildSync());
