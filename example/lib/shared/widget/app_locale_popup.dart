import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:example/i18n/strings.g.dart';
import 'package:example/shared/pods/translation_pod.dart';

///This widget can be used to change the local in a popup
class AppLocalePopUp extends ConsumerWidget {
  const AppLocalePopUp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsPod);
    final curentlocale = t.$meta.locale;
    final localeName = t["locale_${curentlocale.languageCode}"].toString();

    return PopupMenuButton<AppLocale>(
        initialValue: AppLocaleUtils.parse(curentlocale.languageCode),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(localeName),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
        //  icon: const Icon(Icons.translate),
        // Callback that sets the selected popup menu item.
        onSelected: (locale) async {
          final update = switch (locale) {
            AppLocale.en => await AppLocale.en.build(),
            AppLocale.es => await AppLocale.es.build(),
          };
          ref.read(translationsPod.notifier).update(
                (state) => update,
              );
        },
        itemBuilder: (BuildContext context) => AppLocale.values.map(
              (e) {
                return PopupMenuItem<AppLocale>(
                  value: e,
                  child: e.languageCode == curentlocale.languageCode
                      ? SelectedLocaleItem(
                          locale: e.flutterLocale,
                          key: ValueKey('selected ${e.languageCode}'),
                        )
                      : UnselectedLocaleItem(
                          locale: e.flutterLocale,
                          key: ValueKey('unselected ${e.languageCode}'),
                        ),
                );
              },
            ).toList());
  }
}

class SelectedLocaleItem extends ConsumerWidget {
  const SelectedLocaleItem({
    super.key,
    required this.locale,
  });
  final Locale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsPod);
    final localeName = t["locale_${locale.languageCode}"].toString();
    return Row(
      children: [
        const Icon(
          Icons.check,
          color: Colors.green,
        ),
        Text(localeName),
      ],
    );
  }
}

class UnselectedLocaleItem extends ConsumerWidget {
  const UnselectedLocaleItem({
    super.key,
    required this.locale,
  });
  final Locale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsPod);
    final localeName = t["locale_${locale.languageCode}"].toString();
    return Localizations.override(
      context: context,
      locale: locale,
      child: Text(
        localeName,
        style: const TextStyle(
          color: Colors.grey,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
