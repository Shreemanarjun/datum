import 'package:datum/datum.dart';

import '../engine/metadata_hash_cache.dart';
import '../utils/lru_cache.dart';

/// Internal collaborator of `DatumManager` that owns all manager-level cache
/// state: the query cache, the relationship-query cache, the entity-existence
/// cache, and the sync-metadata hash cache.
///
/// This class is an implementation detail of the manager and is NOT exported
/// from the package barrel.
class ManagerCacheCoordinator<T extends DatumEntityInterface> {
  ManagerCacheCoordinator({
    required int maxRelationshipQueryCacheSize,
    required int maxEntityExistenceCacheSize,
    required int maxQueryCacheSize,
    required DatumLogger logger,
  })  : relationshipQueryCache = LRUCache(maxRelationshipQueryCacheSize),
        entityExistenceCache = LRUCache(maxEntityExistenceCacheSize),
        queryCache = LRUCache(maxQueryCacheSize),
        _logger = logger;

  final DatumLogger _logger;

  /// Cache for relationship query results to improve performance
  final LRUCache<String, List<DatumEntityInterface>> relationshipQueryCache;

  /// Cache for entity existence checks
  final LRUCache<String, bool> entityExistenceCache;

  /// Cache for query results
  final LRUCache<String, List<T>> queryCache;

  /// Shared with the sync engine: manager CRUD invalidates entries so the
  /// engine can reuse the content hash on idle cycles.
  final MetadataHashCache metadataHashCache = MetadataHashCache();

  /// Gets cached relationship query results.
  List<DatumEntityInterface>? getCachedRelationshipQuery(String cacheKey) {
    final cached = relationshipQueryCache[cacheKey];
    if (cached != null) {
      _logger.debug('Using cached relationship query results for key: $cacheKey');
    }
    return cached;
  }

  /// Caches relationship query results.
  void cacheRelationshipQuery(String cacheKey, List<DatumEntityInterface> results) {
    relationshipQueryCache[cacheKey] = results;
    _logger.debug('Cached relationship query results for key: $cacheKey (${results.length} entities)');
  }

  /// Creates a cache key for a query.
  String createQueryCacheKey(DatumQuery query, DataSource source, String? userId) {
    final buffer = StringBuffer();
    buffer.write('${T.toString()}:${source.name}');
    if (userId != null) buffer.write(':$userId');

    // Include filters in cache key (order matters for consistency)
    if (query.filters.isNotEmpty) {
      buffer.write(':filters=');
      for (final filter in query.filters) {
        if (filter is Filter) {
          buffer.write('${filter.field}${filter.operator}${filter.value};');
        } else if (filter is CompositeFilter) {
          buffer.write('composite${filter.operator}${filter.conditions.length};');
        }
      }
    }

    // Include sorting in cache key
    if (query.sorting.isNotEmpty) {
      buffer.write(':sort=');
      for (final sort in query.sorting) {
        buffer.write('${sort.field}${sort.descending ? 'desc' : 'asc'};');
      }
    }

    // Include limit/offset in cache key
    if (query.limit != null) {
      buffer.write(':limit=${query.limit}');
    }
    if (query.offset != null) {
      buffer.write(':offset=${query.offset}');
    }

    return buffer.toString();
  }

  /// Gets cached query results.
  List<T>? getCachedQuery(String cacheKey) {
    final cached = queryCache[cacheKey];
    if (cached != null) {
      _logger.debug('Using cached query results for key: $cacheKey');
    }
    return cached;
  }

  /// Caches query results.
  void cacheQuery(String cacheKey, List<T> results) {
    queryCache[cacheKey] = results;
    _logger.debug('Cached query results for key: $cacheKey (${results.length} entities)');
  }

  /// Clears all caches. Useful for testing or when data consistency is critical.
  void clearCaches() {
    relationshipQueryCache.clear();
    entityExistenceCache.clear();
    queryCache.clear();
    _logger.debug('All caches cleared');
  }

  /// Clears relationship caches for a specific entity type.
  void clearRelationshipCacheForType(Type entityType) {
    // Also clear related query caches
    relationshipQueryCache.removeWhere((key, _) => key.startsWith('${entityType.toString()}:'));
    _logger.debug('Cleared relationship caches for $entityType');
  }

  /// Invalidates caches that might be affected by changes to an entity.
  void invalidateCachesForEntity(T entity) {
    // Clear query caches that might be affected by this entity change
    queryCache.removeWhere((key, _) {
      // For simplicity, clear all query caches when any entity changes
      // In a more sophisticated implementation, we could be more selective
      return true;
    });

    // Clear relationship query caches that involve this entity
    relationshipQueryCache.removeWhere((key, _) {
      // Remove caches where this entity is the parent or child in relationships
      return key.startsWith('${entity.runtimeType}:${entity.id}:') || key.contains(':${entity.runtimeType}:${entity.id}');
    });

    // Clear entity existence cache for this entity
    entityExistenceCache.remove('${entity.runtimeType}:${entity.id}');

    _logger.debug('Invalidated caches for entity ${entity.runtimeType}:${entity.id}');
  }

  /// Gets cache statistics for monitoring and debugging.
  Map<String, int> getCacheStats() {
    return {
      'relationship_queries': relationshipQueryCache.length,
      'entity_existence': entityExistenceCache.length,
      'queries': queryCache.length,
    };
  }
}
