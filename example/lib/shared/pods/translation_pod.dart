import 'package:example/i18n/strings.g.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final translationsPod = StateProvider<Translations>(
  (ref) => throw UnimplementedError("translations not overriden yet"),
  name: 'translationsProvider',
);
