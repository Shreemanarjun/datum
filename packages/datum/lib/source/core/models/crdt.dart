import 'package:equatable/equatable.dart';

/// Base interface for Conflict-free Replicated Data Types (CRDTs).
abstract interface class CRDT<T> {
  /// Merges this CRDT with another of the same type.
  CRDT<T> merge(covariant CRDT<T> other);

  /// Returns the current value of the CRDT.
  T get value;

  /// Converts the CRDT state to a map for serialization.
  Map<String, dynamic> toMap();
}

/// A Positive-Negative Counter CRDT.
///
/// It allows increments and decrements across multiple replicas independently
/// and can be merged without conflicts.
class PNCounter extends Equatable implements CRDT<int> {
  final Map<String, int> _p; // Positive increments
  final Map<String, int> _n; // Negative decrements

  const PNCounter({
    Map<String, int>? p,
    Map<String, int>? n,
  })  : _p = p ?? const {},
        _n = n ?? const {};

  factory PNCounter.fromMap(Map<String, dynamic> map) {
    // Lenient numeric decode: JSON backends may deliver ints as doubles.
    final pMap = (map['p'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, (v as num).toInt())) ?? {};
    final nMap = (map['n'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, (v as num).toInt())) ?? {};
    return PNCounter(p: pMap, n: nMap);
  }

  @override
  Map<String, dynamic> toMap() => {
        'p': _p,
        'n': _n,
      };

  @override
  int get value {
    final pTotal = _p.values.fold(0, (sum, val) => sum + val);
    final nTotal = _n.values.fold(0, (sum, val) => sum + val);
    return pTotal - nTotal;
  }

  PNCounter increment(String replicaId, [int amount = 1]) {
    final newP = Map<String, int>.from(_p);
    newP[replicaId] = (newP[replicaId] ?? 0) + amount;
    return PNCounter(p: newP, n: _n);
  }

  PNCounter decrement(String replicaId, [int amount = 1]) {
    final newN = Map<String, int>.from(_n);
    newN[replicaId] = (newN[replicaId] ?? 0) + amount;
    return PNCounter(p: _p, n: newN);
  }

  @override
  PNCounter merge(covariant PNCounter other) {
    final mergedP = Map<String, int>.from(_p);
    other._p.forEach((k, v) {
      mergedP[k] = mergedP.containsKey(k) ? (mergedP[k]! > v ? mergedP[k]! : v) : v;
    });

    final mergedN = Map<String, int>.from(_n);
    other._n.forEach((k, v) {
      mergedN[k] = mergedN.containsKey(k) ? (mergedN[k]! > v ? mergedN[k]! : v) : v;
    });

    return PNCounter(p: mergedP, n: mergedN);
  }

  @override
  List<Object?> get props => [_p, _n];

  @override
  String toString() => 'PNCounter(value: $value)';
}

/// An Observed-Remove Set CRDT.
///
/// Elements can be added and removed across multiple replicas.
/// It uses a "win" strategy for concurrent add/remove of the same element.
class ORSet<T> extends Equatable implements CRDT<Set<T>> {
  final Map<T, Set<String>> _addSet;
  final Map<T, Set<String>> _removeSet;

  const ORSet({
    Map<T, Set<String>>? addSet,
    Map<T, Set<String>>? removeSet,
  })  : _addSet = addSet ?? const {},
        _removeSet = removeSet ?? const {};

  factory ORSet.fromMap(Map<String, dynamic> map, T Function(dynamic) decoder) {
    // Format 2 stores entries as {'e': encodedElement, 't': [tags]} so the
    // element round-trips through [decoder] faithfully. The legacy format
    // stringified elements into JSON map KEYS — `toString()` has no inverse,
    // so any non-String element type either crashed the decoder or collided
    // distinct elements into one key (merging their tag sets).
    if (map['format'] == 2) {
      Map<T, Set<String>> parse(String key) => {
            for (final raw in (map[key] as List? ?? const [])) decoder((raw as Map)['e']): ((raw['t'] as List?) ?? const []).cast<String>().toSet(),
          };
      return ORSet(addSet: parse('add'), removeSet: parse('remove'));
    }

    final addMap = <T, Set<String>>{};
    (map['add'] as Map<String, dynamic>?)?.forEach((k, v) {
      addMap[decoder(k)] = (v as List).cast<String>().toSet();
    });

    final removeMap = <T, Set<String>>{};
    (map['remove'] as Map<String, dynamic>?)?.forEach((k, v) {
      removeMap[decoder(k)] = (v as List).cast<String>().toSet();
    });

    return ORSet(addSet: addMap, removeSet: removeMap);
  }

  /// Serializes in the format-2 entry shape. [encoder] converts an element
  /// to a JSON-encodable value; by default the element itself is stored
  /// (correct for JSON primitives — matching what [fromMap]'s decoder
  /// expects back).
  @override
  Map<String, dynamic> toMap({Object? Function(T element)? encoder}) {
    Object? encode(T element) => encoder != null ? encoder(element) : element;
    List<Map<String, dynamic>> entries(Map<T, Set<String>> source) => [
          for (final MapEntry(:key, :value) in source.entries) {'e': encode(key), 't': value.toList()},
        ];
    return {
      'format': 2,
      'add': entries(_addSet),
      'remove': entries(_removeSet),
    };
  }

  @override
  Set<T> get value {
    final result = <T>{};
    for (final element in _addSet.keys) {
      final adds = _addSet[element] ?? {};
      final removes = _removeSet[element] ?? {};
      if (adds.difference(removes).isNotEmpty) {
        result.add(element);
      }
    }
    return result;
  }

  ORSet<T> add(T element, String tag) {
    final newAdd = Map<T, Set<String>>.from(_addSet.map((k, v) => MapEntry(k, Set<String>.from(v))));
    newAdd[element] = (newAdd[element] ?? {})..add(tag);
    return ORSet(addSet: newAdd, removeSet: _removeSet);
  }

  ORSet<T> remove(T element) {
    if (!_addSet.containsKey(element)) return this;
    final newRemove = Map<T, Set<String>>.from(_removeSet.map((k, v) => MapEntry(k, Set<String>.from(v))));
    newRemove[element] = (newRemove[element] ?? {})..addAll(_addSet[element]!);
    return ORSet(addSet: _addSet, removeSet: newRemove);
  }

  @override
  ORSet<T> merge(covariant ORSet<T> other) {
    final mergedAdd = Map<T, Set<String>>.from(_addSet.map((k, v) => MapEntry(k, Set<String>.from(v))));
    other._addSet.forEach((k, v) {
      mergedAdd[k] = (mergedAdd[k] ?? {})..addAll(v);
    });

    final mergedRemove = Map<T, Set<String>>.from(_removeSet.map((k, v) => MapEntry(k, Set<String>.from(v))));
    other._removeSet.forEach((k, v) {
      mergedRemove[k] = (mergedRemove[k] ?? {})..addAll(v);
    });

    return ORSet(addSet: mergedAdd, removeSet: mergedRemove);
  }

  @override
  List<Object?> get props => [_addSet, _removeSet];
}

/// A single element of an [RgaList], identified by its `(replicaId, counter)`
/// pair and anchored after its [origin] element.
///
/// Deleted elements become **tombstones** (kept so later inserts anchored to
/// them still order correctly); compact them by snapshotting the visible value
/// into a fresh list when your app persists a checkpoint.
class RgaNode<T> extends Equatable {
  /// Creates an element node.
  const RgaNode({
    required this.replicaId,
    required this.counter,
    required this.origin,
    required this.value,
    this.deleted = false,
  });

  /// The replica that created this element.
  final String replicaId;

  /// The Lamport counter at creation time (unique per replica).
  final int counter;

  /// The id of the element this one was inserted after (`null` = list head).
  final String? origin;

  /// The element payload.
  final T value;

  /// Whether this element has been removed (tombstoned).
  final bool deleted;

  /// The globally unique element id.
  String get id => '$replicaId:$counter';

  /// Returns a tombstoned copy of this node.
  RgaNode<T> tombstone() => RgaNode(replicaId: replicaId, counter: counter, origin: origin, value: value, deleted: true);

  @override
  List<Object?> get props => [replicaId, counter, origin, value, deleted];
}

/// A **Replicated Growable Array** (RGA) — a convergent ordered-sequence CRDT.
///
/// This is the sequence type collaborative editors need: concurrent inserts and
/// deletes on different devices merge deterministically without dropping
/// elements. Each element is identified by `(replicaId, counter)` and anchored
/// *after* the element it was inserted behind; concurrent inserts at the same
/// anchor are ordered by Lamport counter (newest first), so every replica
/// arrives at the same order from the same element set.
///
/// Like the other CRDTs in this file it is immutable — operations return a new
/// list — and merging is a state-based union (commutative, associative,
/// idempotent):
///
/// ```dart
/// var a = RgaList<String>(replicaId: 'device-a').insertAll(0, ['h', 'i']);
/// var b = RgaList<String>.fromMap(a.toMap(), (v) => v as String, replicaId: 'device-b');
///
/// a = a.insert(2, '!');            // device A appends '!'
/// b = b.insert(0, '>');            // device B prepends '>'
///
/// final mergedA = a.merge(b);
/// final mergedB = b.merge(a);
/// assert(mergedA.value.join() == mergedB.value.join()); // '>hi!'
/// ```
///
/// Contiguous runs inserted with [insertAll] (or [RgaText.insert]) chain each
/// element to the previous one, so two devices typing words concurrently at the
/// same spot do not interleave characters.
class RgaList<T> extends Equatable implements CRDT<List<T>> {
  /// Creates an empty sequence owned by [replicaId].
  const RgaList({required this.replicaId})
      : _nodes = const {},
        _counter = 0;

  const RgaList._(this.replicaId, this._nodes, this._counter);

  /// Deserializes a sequence.
  ///
  /// **Always pass this device's own [replicaId] when the instance will be
  /// edited.** Without it the list deserializes with an empty (or, for
  /// legacy payloads, the creator's) identity — two devices editing copies
  /// of the same document then mint COLLIDING node ids, and one device's
  /// concurrent edits are deterministically discarded on merge.
  factory RgaList.fromMap(
    Map<String, dynamic> map,
    T Function(dynamic raw) decoder, {
    String? replicaId,
  }) {
    final nodes = <String, RgaNode<T>>{};
    var maxCounter = (map['counter'] as num?)?.toInt() ?? 0;
    for (final raw in (map['nodes'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      final node = RgaNode<T>(
        replicaId: m['r'] as String,
        counter: (m['c'] as num).toInt(),
        origin: m['o'] as String?,
        value: decoder(m['v']),
        deleted: m['d'] as bool? ?? false,
      );
      nodes[node.id] = node;
      if (node.counter > maxCounter) maxCounter = node.counter;
    }
    return RgaList._(replicaId ?? (map['replicaId'] as String? ?? ''), nodes, maxCounter);
  }

  /// This replica's identity, stamped on locally created elements.
  final String replicaId;

  final Map<String, RgaNode<T>> _nodes;
  final int _counter;

  /// The visible (non-tombstoned) elements, in convergent order.
  @override
  List<T> get value => _visible().map((n) => n.value).toList();

  /// The visible element ids in order — stable handles for cursor positions.
  List<String> get idsInOrder => _visible().map((n) => n.id).toList();

  /// Number of visible elements.
  int get length => _visible().length;

  /// Whether the sequence has no visible elements.
  bool get isEmpty => length == 0;

  /// The id of the visible element at [index].
  String elementIdAt(int index) => _visible()[index].id;

  /// The visible index of element [id], or -1 if absent/tombstoned.
  int indexOfId(String id) => _visible().indexWhere((n) => n.id == id);

  /// Number of tombstoned elements retained for ordering (see [compacted]).
  int get tombstoneCount => _nodes.values.where((n) => n.deleted).length;

  /// Returns a copy with every tombstone purged.
  ///
  /// Deleted elements normally stay as tombstones so concurrent inserts
  /// anchored to them keep their position; over the life of a document they
  /// accumulate without bound. Compaction rebuilds the sequence as a linear
  /// chain of only the visible elements — **element ids are preserved**, so
  /// cursor anchors ([elementIdAt]/[indexOfId]) stay valid, order is exactly
  /// the current visible order, and the Lamport counter continues from where
  /// it was (new local inserts cannot collide). The rewrite is a pure
  /// function of the synced state, so replicas compacting the same state
  /// produce identical results.
  ///
  /// ⚠️ **Coordination contract**: compact only at a synchronization barrier
  /// (all replicas have merged this state — e.g. when persisting a checkpoint
  /// or when a single writer holds the document). Merging a compacted list
  /// with a *stale* replica that never observed a deletion resurrects that
  /// element (its tombstone is gone), and elements whose anchors were
  /// rewritten reconcile through [merge]'s deterministic same-id resolution —
  /// convergent on every replica, but the visible order around the stale
  /// edits may shift once.
  RgaList<T> compacted() {
    final nodes = <String, RgaNode<T>>{};
    String? origin;
    for (final node in _visible()) {
      nodes[node.id] = RgaNode<T>(
        replicaId: node.replicaId,
        counter: node.counter,
        origin: origin,
        value: node.value,
      );
      origin = node.id;
    }
    return RgaList._(replicaId, nodes, _counter);
  }

  /// Inserts [element] at visible [index] (0 = head, [length] = append).
  RgaList<T> insert(int index, T element) => insertAll(index, [element]);

  /// Inserts [elements] as a contiguous run at visible [index].
  RgaList<T> insertAll(int index, Iterable<T> elements) {
    final visible = _visible();
    if (index < 0 || index > visible.length) {
      throw RangeError.range(index, 0, visible.length, 'index');
    }
    var origin = index == 0 ? null : visible[index - 1].id;
    final nodes = Map<String, RgaNode<T>>.from(_nodes);
    var counter = _counter;
    for (final element in elements) {
      counter++;
      final node = RgaNode<T>(replicaId: replicaId, counter: counter, origin: origin, value: element);
      nodes[node.id] = node;
      origin = node.id; // chain the run so it cannot be interleaved
    }
    return RgaList._(replicaId, nodes, counter);
  }

  /// Appends [element] at the end of the sequence.
  RgaList<T> add(T element) => insert(length, element);

  /// Tombstones the visible element at [index].
  RgaList<T> removeAt(int index) {
    final visible = _visible();
    if (index < 0 || index >= visible.length) {
      throw RangeError.index(index, visible, 'index');
    }
    return removeById(visible[index].id);
  }

  /// Tombstones [count] visible elements starting at [index].
  RgaList<T> removeRange(int index, int count) {
    final visible = _visible();
    if (index < 0 || count < 0 || index + count > visible.length) {
      throw RangeError.range(index + count, 0, visible.length, 'index+count');
    }
    final nodes = Map<String, RgaNode<T>>.from(_nodes);
    for (var i = index; i < index + count; i++) {
      nodes[visible[i].id] = visible[i].tombstone();
    }
    return RgaList._(replicaId, nodes, _counter);
  }

  /// Tombstones the element with [id] (no-op if unknown).
  RgaList<T> removeById(String id) {
    final node = _nodes[id];
    if (node == null || node.deleted) return this;
    final nodes = Map<String, RgaNode<T>>.from(_nodes);
    nodes[id] = node.tombstone();
    return RgaList._(replicaId, nodes, _counter);
  }

  @override
  RgaList<T> merge(covariant RgaList<T> other) {
    final nodes = Map<String, RgaNode<T>>.from(_nodes);
    for (final node in other._nodes.values) {
      final existing = nodes[node.id];
      if (existing == null) {
        nodes[node.id] = node;
      } else if (existing.value != node.value || existing.origin != node.origin) {
        // Same id, different content: two replicas generated colliding ids —
        // the deserialization trap of editing a document loaded WITHOUT
        // passing this device's own replicaId to fromMap. One edit is
        // already lost; pick the winner DETERMINISTICALLY so every replica
        // at least converges to the same state instead of diverging forever
        // (keeping "ours" made each side keep a different node).
        final keepExisting = _collisionRank(existing).compareTo(_collisionRank(node)) >= 0;
        final winner = keepExisting ? existing : node;
        nodes[node.id] = (existing.deleted || node.deleted) && !winner.deleted ? winner.tombstone() : winner;
      } else if (node.deleted && !existing.deleted) {
        nodes[node.id] = existing.tombstone(); // deletion wins (monotonic)
      }
    }
    final counter = _counter > other._counter ? _counter : other._counter;
    return RgaList._(replicaId, nodes, counter);
  }

  /// Total order over colliding same-id nodes, identical on every replica.
  static String _collisionRank(RgaNode node) => '${node.origin ?? ''} ${node.value}';

  @override
  Map<String, dynamic> toMap() {
    // Canonical node order (counter, then replicaId): two CONVERGED replicas
    // must serialize byte-identically. Iterating map-insertion order made
    // each replica serialize its own nodes first, so order-sensitive deep
    // equality in conflict detection re-flagged converged documents as
    // conflicting on every sync cycle, ping-ponging resolution pushes.
    final ordered = _nodes.values.toList()
      ..sort((a, b) {
        final byCounter = a.counter.compareTo(b.counter);
        if (byCounter != 0) return byCounter;
        return a.replicaId.compareTo(b.replicaId);
      });
    // `replicaId` is deliberately NOT serialized: it is per-DEVICE identity,
    // not document state. Serializing it (the old format) made converged
    // replicas serialize differently AND handed deserializing devices the
    // CREATOR's identity as a default — two devices then minted colliding
    // node ids and silently destroyed each other's concurrent edits.
    return {
      'counter': _counter,
      'nodes': [
        for (final n in ordered)
          {
            'r': n.replicaId,
            'c': n.counter,
            'o': n.origin,
            'v': n.value,
            'd': n.deleted,
          },
      ],
    };
  }

  /// Convergent total order: iterative DFS over the origin tree, visiting
  /// siblings newest-first (counter desc, then replicaId desc). Pure function
  /// of the node set, so all replicas order identically. Tombstones are
  /// traversed (they anchor later inserts) but filtered from the result.
  List<RgaNode<T>> _visible() {
    if (_nodes.isEmpty) return const [];
    final children = <String?, List<RgaNode<T>>>{};
    for (final node in _nodes.values) {
      (children[node.origin] ??= []).add(node);
    }
    for (final siblings in children.values) {
      siblings.sort((a, b) {
        final byCounter = b.counter.compareTo(a.counter);
        if (byCounter != 0) return byCounter;
        return b.replicaId.compareTo(a.replicaId);
      });
    }
    final out = <RgaNode<T>>[];
    final stack = <RgaNode<T>>[...?children[null]?.reversed];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      if (!node.deleted) out.add(node);
      final kids = children[node.id];
      if (kids != null) stack.addAll(kids.reversed);
    }
    return out;
  }

  @override
  List<Object?> get props => [_nodes];

  @override
  String toString() => 'RgaList(replicaId: $replicaId, value: $value)';
}

/// A convergent collaborative **text** CRDT for editors, built on [RgaList].
///
/// ```dart
/// var doc = RgaText(replicaId: 'device-a').insert(0, 'hello');
/// doc = doc.insert(5, ' world');
/// doc = doc.delete(0, 1).insert(0, 'H');   // 'Hello world'
///
/// // Another device edits concurrently, then both merge to the same string:
/// final merged = doc.merge(otherDeviceDoc);
/// ```
class RgaText extends Equatable implements CRDT<String> {
  /// Creates an empty document owned by [replicaId].
  RgaText({required String replicaId}) : _chars = RgaList<String>(replicaId: replicaId);

  const RgaText._(this._chars);

  /// Deserializes a document; pass this device's [replicaId] for local edits.
  factory RgaText.fromMap(Map<String, dynamic> map, {String? replicaId}) => RgaText._(RgaList<String>.fromMap(map, (v) => v as String, replicaId: replicaId));

  final RgaList<String> _chars;

  /// The current text.
  @override
  String get value => _chars.value.join();

  /// The text length.
  int get length => _chars.length;

  /// This replica's identity.
  String get replicaId => _chars.replicaId;

  /// Inserts [text] at character [index] as one contiguous, non-interleavable run.
  RgaText insert(int index, String text) {
    if (text.isEmpty) return this;
    return RgaText._(_chars.insertAll(index, text.split('')));
  }

  /// Deletes [count] characters starting at [index].
  /// Number of tombstoned characters retained for ordering (see [compact]).
  int get tombstoneCount => _chars.tombstoneCount;

  /// Returns a copy with every tombstone purged — see [RgaList.compacted]
  /// for the coordination contract (compact only at a sync barrier).
  /// Character ids, and therefore cursor anchors, are preserved.
  RgaText compact() => RgaText._(_chars.compacted());

  RgaText delete(int index, int count) {
    if (count == 0) return this;
    return RgaText._(_chars.removeRange(index, count));
  }

  /// A stable id for the character at [index] (anchor for remote cursors).
  String characterIdAt(int index) => _chars.elementIdAt(index);

  /// The current index of the character with [id], or -1 if deleted.
  int indexOfCharacter(String id) => _chars.indexOfId(id);

  @override
  RgaText merge(covariant RgaText other) => RgaText._(_chars.merge(other._chars));

  @override
  Map<String, dynamic> toMap() => _chars.toMap();

  @override
  List<Object?> get props => [_chars];

  @override
  String toString() => 'RgaText(replicaId: $replicaId, value: "$value")';
}
