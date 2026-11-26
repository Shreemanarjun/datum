import 'dart:io';

import 'package:test/test.dart';

/// Layers of `lib/source`, innermost first. A file may import its own layer
/// and any layer above it in this list (lower rank), never one below.
///
/// 0 utils      — logger, connectivity contract, formatting
/// 1 domain     — entities, operations, queries, schema, errors, events,
///                resolver contracts, middleware contracts
/// 2 adapter    — local/remote adapter contracts and capabilities
/// 3 services   — migrations, sync strategies, persistence
/// 4 config     — DatumConfig
/// 5 engine     — the sync engine (push/pull cycle, queue, conflict detection)
/// 6 manager    — DatumManager: the per-entity application API
/// 7 facade     — Datum: the multi-entity singleton
const _rank = {
  'utils': 0,
  'core/models': 1,
  'core/errors': 1,
  'core/query': 1,
  'core/schema': 1,
  'core/resolver': 1,
  'core/health': 1,
  'core/events': 1,
  'core/middleware': 1,
  'core/utils': 1,
  'core': 1,
  'adapter': 2,
  'core/migration': 3,
  'core/sync': 3,
  'core/persistence': 3,
  'config': 4,
  'core/engine': 5,
  'core/manager': 6,
  'core/facade': 7,
};

/// Known violations of the dependency rule. This list may only shrink.
///
/// Relation objects (`user.posts.fetch()`) live on the entity and return
/// through a manager, so the relational entity model reaches up to the
/// manager layer. Removing it means moving relation loading off the entity.
const _baseline = {
  'core/models/relational_datum_entity.dart -> core/manager/datum_manager.dart',
  'core/models/relational_datum_entity.dart -> core/manager/manager_locator.dart',
};

String _layer(String relative) {
  final parts = relative.split('/');
  if (parts.first != 'core') return parts.first;
  return parts.length > 2 ? 'core/${parts[1]}' : 'core';
}

void main() {
  test('lib/source follows the dependency rule (inner layers never import outer ones)', () {
    final root = Directory('lib/source').absolute.uri;
    final import = RegExp(r"^import '([^']+)';", multiLine: true);
    final violations = <String>{};

    for (final file in Directory('lib/source').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final from = file.absolute.uri.path.substring(root.path.length);
      for (final match in import.allMatches(file.readAsStringSync())) {
        final uri = match.group(1)!;
        // The package barrel re-exports every layer, hiding real dependencies.
        if (uri == 'package:datum/datum.dart') {
          violations.add('$from -> package:datum/datum.dart');
          continue;
        }
        final String to;
        if (uri.startsWith('package:datum/source/')) {
          to = uri.substring('package:datum/source/'.length);
        } else if (uri.startsWith('.')) {
          to = file.absolute.uri.resolve(uri).path.substring(root.path.length);
        } else {
          continue;
        }
        final fromRank = _rank[_layer(from)], toRank = _rank[_layer(to)];
        expect(fromRank, isNotNull, reason: 'unranked layer for $from — add it to _rank');
        expect(toRank, isNotNull, reason: 'unranked layer for $to — add it to _rank');
        if (toRank! > fromRank!) violations.add('$from -> $to');
      }
    }

    expect(violations.difference(_baseline), isEmpty, reason: 'new upward imports');
    expect(_baseline.difference(violations), isEmpty, reason: 'fixed: remove these from _baseline');
  });
}
