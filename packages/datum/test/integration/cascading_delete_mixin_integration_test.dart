// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import 'package:datum/datum.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';

/// A simple User entity for testing cascading delete relationships using mixins.
class UserMixin extends RelationalDatumEntity with RelationalDatumEntityMixin {
  @override
  final String id;
  @override
  final String userId;
  final String name;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const UserMixin({
    required this.id,
    required this.name,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  }) : userId = id;

  @override
  Map<String, Relation> get relations => {
        'posts': HasMany<PostMixin>(this, 'userId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
        'profile': HasOne<ProfileMixin>(this, 'userId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
        'comments': HasMany<CommentMixin>(this, 'userId', cascadeDeleteBehavior: CascadeDeleteBehavior.restrict),
      };

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'name': name,
        'modifiedAt': modifiedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  UserMixin copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) {
    return UserMixin(
      id: id,
      name: name,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    if (oldVersion is! UserMixin) return toDatumMap();
    final diff = <String, dynamic>{};
    if (name != oldVersion.name) diff['name'] = name;
    if (modifiedAt != oldVersion.modifiedAt) diff['modifiedAt'] = modifiedAt.toIso8601String();
    if (version != oldVersion.version) diff['version'] = version;
    if (isDeleted != oldVersion.isDeleted) diff['isDeleted'] = isDeleted;
    return diff.isEmpty ? null : diff;
  }

  @override
  bool operator ==(covariant UserMixin other) {
    if (identical(this, other)) return true;
    return other.id == id && other.userId == userId && other.name == name && other.modifiedAt == modifiedAt && other.createdAt == createdAt && other.version == version && other.isDeleted == isDeleted;
  }

  @override
  int get hashCode {
    return id.hashCode ^ userId.hashCode ^ name.hashCode ^ modifiedAt.hashCode ^ createdAt.hashCode ^ version.hashCode ^ isDeleted.hashCode;
  }
}

/// A Post entity that belongs to a User using mixins.
class PostMixin extends RelationalDatumEntity with RelationalDatumEntityMixin {
  @override
  final String id;
  @override
  final String userId;
  final String title;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const PostMixin({
    required this.id,
    required this.userId,
    required this.title,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, Relation> get relations => {
        'author': BelongsTo<UserMixin>(this, 'userId', cascadeDeleteBehavior: CascadeDeleteBehavior.none),
        'comments': HasMany<CommentMixin>(this, 'postId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
      };

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'title': title,
        'modifiedAt': modifiedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  PostMixin copyWith({
    String? id,
    String? userId,
    String? title,
    DateTime? modifiedAt,
    DateTime? createdAt,
    int? version,
    bool? isDeleted,
  }) {
    return PostMixin(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt ?? this.createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    if (oldVersion is! PostMixin) return toDatumMap();
    final diff = <String, dynamic>{};
    if (title != oldVersion.title) diff['title'] = title;
    if (modifiedAt != oldVersion.modifiedAt) diff['modifiedAt'] = modifiedAt.toIso8601String();
    if (version != oldVersion.version) diff['version'] = version;
    if (isDeleted != oldVersion.isDeleted) diff['isDeleted'] = isDeleted;
    return diff.isEmpty ? null : diff;
  }

  @override
  bool operator ==(covariant PostMixin other) {
    if (identical(this, other)) return true;
    return other.id == id && other.userId == userId && other.title == title && other.modifiedAt == modifiedAt && other.createdAt == createdAt && other.version == version && other.isDeleted == isDeleted;
  }

  @override
  int get hashCode {
    return id.hashCode ^ userId.hashCode ^ title.hashCode ^ modifiedAt.hashCode ^ createdAt.hashCode ^ version.hashCode ^ isDeleted.hashCode;
  }
}

/// A Profile entity that belongs to a User using mixins.
class ProfileMixin extends RelationalDatumEntity with RelationalDatumEntityMixin {
  @override
  final String id;
  @override
  final String userId;
  final String bio;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const ProfileMixin({
    required this.id,
    required this.userId,
    required this.bio,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, Relation> get relations => {
        'user': BelongsTo<UserMixin>(this, 'userId', cascadeDeleteBehavior: CascadeDeleteBehavior.none),
      };

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'bio': bio,
        'modifiedAt': modifiedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  ProfileMixin copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
    String? bio,
  }) {
    return ProfileMixin(
      id: id,
      userId: userId,
      bio: bio ?? this.bio,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    if (oldVersion is! ProfileMixin) return toDatumMap();
    final diff = <String, dynamic>{};
    if (bio != oldVersion.bio) diff['bio'] = bio;
    if (modifiedAt != oldVersion.modifiedAt) diff['modifiedAt'] = modifiedAt.toIso8601String();
    if (version != oldVersion.version) diff['version'] = version;
    if (isDeleted != oldVersion.isDeleted) diff['isDeleted'] = isDeleted;
    return diff.isEmpty ? null : diff;
  }
}

/// A Comment entity that belongs to a Post using mixins.
class CommentMixin extends RelationalDatumEntity with RelationalDatumEntityMixin {
  @override
  final String id;
  @override
  final String userId;
  final String postId;
  final String content;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const CommentMixin({
    required this.id,
    required this.userId,
    required this.postId,
    required this.content,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, Relation> get relations => {
        'post': BelongsTo<PostMixin>(this, 'postId', cascadeDeleteBehavior: CascadeDeleteBehavior.none),
      };

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'postId': postId,
        'content': content,
        'modifiedAt': modifiedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  CommentMixin copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
    String? content,
  }) {
    return CommentMixin(
      id: id,
      userId: userId,
      postId: postId,
      content: content ?? this.content,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    if (oldVersion is! CommentMixin) return toDatumMap();
    final diff = <String, dynamic>{};
    if (content != oldVersion.content) diff['content'] = content;
    if (modifiedAt != oldVersion.modifiedAt) diff['modifiedAt'] = modifiedAt.toIso8601String();
    if (version != oldVersion.version) diff['version'] = version;
    if (isDeleted != oldVersion.isDeleted) diff['isDeleted'] = isDeleted;
    return diff.isEmpty ? null : diff;
  }
}

/// A Category entity for testing hierarchical relationships using mixins.
class CategoryMixin extends RelationalDatumEntity with RelationalDatumEntityMixin {
  @override
  final String id;
  @override
  final String userId;
  final String name;
  final String? parentId;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const CategoryMixin({
    required this.id,
    required this.userId,
    required this.name,
    this.parentId,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, Relation> get relations => {
        'parent': BelongsTo<CategoryMixin>(this, 'parentId', cascadeDeleteBehavior: CascadeDeleteBehavior.none),
        'subcategories': HasMany<CategoryMixin>(this, 'parentId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
        'products': HasMany<ProductMixin>(this, 'categoryId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
      };

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'name': name,
        'parentId': parentId,
        'modifiedAt': modifiedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  CategoryMixin copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
    String? name,
    String? parentId,
  }) {
    return CategoryMixin(
      id: id,
      userId: userId,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    if (oldVersion is! CategoryMixin) return toDatumMap();
    final diff = <String, dynamic>{};
    if (name != oldVersion.name) diff['name'] = name;
    if (parentId != oldVersion.parentId) diff['parentId'] = parentId;
    if (modifiedAt != oldVersion.modifiedAt) diff['modifiedAt'] = modifiedAt.toIso8601String();
    if (version != oldVersion.version) diff['version'] = version;
    if (isDeleted != oldVersion.isDeleted) diff['isDeleted'] = isDeleted;
    return diff.isEmpty ? null : diff;
  }
}

/// A Product entity that belongs to a Category using mixins.
class ProductMixin extends RelationalDatumEntity with RelationalDatumEntityMixin {
  @override
  final String id;
  @override
  final String userId;
  final String name;
  final String categoryId;
  final double price;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const ProductMixin({
    required this.id,
    required this.userId,
    required this.name,
    required this.categoryId,
    required this.price,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, Relation> get relations => {
        'category': BelongsTo<CategoryMixin>(this, 'categoryId', cascadeDeleteBehavior: CascadeDeleteBehavior.none),
        'reviews': HasMany<ReviewMixin>(this, 'productId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
        'tags': HasMany<TagMixin>(this, 'productId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
      };

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'name': name,
        'categoryId': categoryId,
        'price': price,
        'modifiedAt': modifiedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  ProductMixin copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
    String? name,
    double? price,
  }) {
    return ProductMixin(
      id: id,
      userId: userId,
      name: name ?? this.name,
      categoryId: categoryId,
      price: price ?? this.price,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    if (oldVersion is! ProductMixin) return toDatumMap();
    final diff = <String, dynamic>{};
    if (name != oldVersion.name) diff['name'] = name;
    if (price != oldVersion.price) diff['price'] = price;
    if (modifiedAt != oldVersion.modifiedAt) diff['modifiedAt'] = modifiedAt.toIso8601String();
    if (version != oldVersion.version) diff['version'] = version;
    if (isDeleted != oldVersion.isDeleted) diff['isDeleted'] = isDeleted;
    return diff.isEmpty ? null : diff;
  }
}

/// A Review entity that belongs to a Product using mixins.
class ReviewMixin extends RelationalDatumEntity with RelationalDatumEntityMixin {
  @override
  final String id;
  @override
  final String userId;
  final String productId;
  final int rating;
  final String comment;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const ReviewMixin({
    required this.id,
    required this.userId,
    required this.productId,
    required this.rating,
    required this.comment,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, Relation> get relations => {
        'product': BelongsTo<ProductMixin>(this, 'productId', cascadeDeleteBehavior: CascadeDeleteBehavior.none),
      };

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'productId': productId,
        'rating': rating,
        'comment': comment,
        'modifiedAt': modifiedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  ReviewMixin copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
    int? rating,
    String? comment,
  }) {
    return ReviewMixin(
      id: id,
      userId: userId,
      productId: productId,
      rating: rating ?? this.rating,
      comment: comment ?? this.comment,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    if (oldVersion is! ReviewMixin) return toDatumMap();
    final diff = <String, dynamic>{};
    if (rating != oldVersion.rating) diff['rating'] = rating;
    if (comment != oldVersion.comment) diff['comment'] = comment;
    if (modifiedAt != oldVersion.modifiedAt) diff['modifiedAt'] = modifiedAt.toIso8601String();
    if (version != oldVersion.version) diff['version'] = version;
    if (isDeleted != oldVersion.isDeleted) diff['isDeleted'] = isDeleted;
    return diff.isEmpty ? null : diff;
  }
}

/// A Tag entity for testing many-to-many relationships using mixins.
class TagMixin extends RelationalDatumEntity with RelationalDatumEntityMixin {
  @override
  final String id;
  @override
  final String userId;
  final String name;
  final String productId;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const TagMixin({
    required this.id,
    required this.userId,
    required this.name,
    required this.productId,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, Relation> get relations => {
        'product': BelongsTo<ProductMixin>(this, 'productId', cascadeDeleteBehavior: CascadeDeleteBehavior.none),
      };

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'name': name,
        'productId': productId,
        'modifiedAt': modifiedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  TagMixin copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
    String? name,
  }) {
    return TagMixin(
      id: id,
      userId: userId,
      name: name ?? this.name,
      productId: productId,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    if (oldVersion is! TagMixin) return toDatumMap();
    final diff = <String, dynamic>{};
    if (name != oldVersion.name) diff['name'] = name;
    if (modifiedAt != oldVersion.modifiedAt) diff['modifiedAt'] = modifiedAt.toIso8601String();
    if (version != oldVersion.version) diff['version'] = version;
    if (isDeleted != oldVersion.isDeleted) diff['isDeleted'] = isDeleted;
    return diff.isEmpty ? null : diff;
  }
}

/// Mixin for entities that can be commented on.
mixin CommentableMixin on RelationalDatumEntity {
  Map<String, Relation> get commentableRelations => {
        'comments': HasMany<CommentMixin>(this, 'postId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
      };

  @override
  Map<String, Relation> get relations => {
        ...super.relations,
        ...commentableRelations,
      };
}

/// Mixin for entities that can be tagged.
mixin TaggableMixin on RelationalDatumEntity {
  Map<String, Relation> get taggableRelations => {
        'tags': HasMany<TagMixin>(this, 'productId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
      };

  @override
  Map<String, Relation> get relations => {
        ...super.relations,
        ...taggableRelations,
      };
}

/// Mixin for entities that can be reviewed.
mixin ReviewableMixin on RelationalDatumEntity {
  Map<String, Relation> get reviewableRelations => {
        'reviews': HasMany<ReviewMixin>(this, 'productId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
      };

  @override
  Map<String, Relation> get relations => {
        ...super.relations,
        ...reviewableRelations,
      };
}

/// Mixin for entities that belong to categories.
mixin CategorizedMixin on RelationalDatumEntity {
  Map<String, Relation> get categorizedRelations => {
        'category': BelongsTo<CategoryMixin>(this, 'categoryId', cascadeDeleteBehavior: CascadeDeleteBehavior.none),
      };

  @override
  Map<String, Relation> get relations => {
        ...super.relations,
        ...categorizedRelations,
      };
}

/// A BlogPost entity that uses mixins for relationships.
class BlogPostMixin extends RelationalDatumEntity with RelationalDatumEntityMixin, CommentableMixin {
  @override
  final String id;
  @override
  final String userId;
  final String title;
  final String content;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const BlogPostMixin({
    required this.id,
    required this.userId,
    required this.title,
    required this.content,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, Relation> get relations => {
        ...super.relations,
        'author': BelongsTo<UserMixin>(this, 'userId', cascadeDeleteBehavior: CascadeDeleteBehavior.none),
      };

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'title': title,
        'content': content,
        'modifiedAt': modifiedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  BlogPostMixin copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
    String? title,
    String? content,
  }) {
    return BlogPostMixin(
      id: id,
      userId: userId,
      title: title ?? this.title,
      content: content ?? this.content,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    if (oldVersion is! BlogPostMixin) return toDatumMap();
    final diff = <String, dynamic>{};
    if (title != oldVersion.title) diff['title'] = title;
    if (content != oldVersion.content) diff['content'] = content;
    if (modifiedAt != oldVersion.modifiedAt) diff['modifiedAt'] = modifiedAt.toIso8601String();
    if (version != oldVersion.version) diff['version'] = version;
    if (isDeleted != oldVersion.isDeleted) diff['isDeleted'] = isDeleted;
    return diff.isEmpty ? null : diff;
  }
}

/// An EcommerceProduct entity that uses multiple mixins.
class EcommerceProductMixin extends RelationalDatumEntity with RelationalDatumEntityMixin, CategorizedMixin, ReviewableMixin, TaggableMixin {
  @override
  final String id;
  @override
  final String userId;
  final String name;
  final String categoryId;
  final double price;
  final String description;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const EcommerceProductMixin({
    required this.id,
    required this.userId,
    required this.name,
    required this.categoryId,
    required this.price,
    required this.description,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, Relation> get relations => {
        ...super.relations,
        'seller': BelongsTo<UserMixin>(this, 'userId', cascadeDeleteBehavior: CascadeDeleteBehavior.none),
      };

  @override
  Map<String, dynamic> toDatumMap({MapTarget target = MapTarget.local}) => {
        'id': id,
        'userId': userId,
        'name': name,
        'categoryId': categoryId,
        'price': price,
        'description': description,
        'modifiedAt': modifiedAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'version': version,
        'isDeleted': isDeleted,
      };

  @override
  EcommerceProductMixin copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
    String? name,
    double? price,
    String? description,
  }) {
    return EcommerceProductMixin(
      id: id,
      userId: userId,
      name: name ?? this.name,
      categoryId: categoryId,
      price: price ?? this.price,
      description: description ?? this.description,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      createdAt: createdAt,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    if (oldVersion is! EcommerceProductMixin) return toDatumMap();
    final diff = <String, dynamic>{};
    if (name != oldVersion.name) diff['name'] = name;
    if (price != oldVersion.price) diff['price'] = price;
    if (description != oldVersion.description) diff['description'] = description;
    if (modifiedAt != oldVersion.modifiedAt) diff['modifiedAt'] = modifiedAt.toIso8601String();
    if (version != oldVersion.version) diff['version'] = version;
    if (isDeleted != oldVersion.isDeleted) diff['isDeleted'] = isDeleted;
    return diff.isEmpty ? null : diff;
  }
}

void main() {
  group('Cascading Delete Mixin Integration Tests', () {
    late DatumManager<UserMixin> userManager;
    late DatumManager<PostMixin> postManager;
    late DatumManager<ProfileMixin> profileManager;
    late DatumManager<CommentMixin> commentManager;
    late DatumManager<CategoryMixin> categoryManager;
    late DatumManager<ProductMixin> productManager;
    late DatumManager<ReviewMixin> reviewManager;
    late DatumManager<TagMixin> tagManager;

    final testUser = UserMixin(
      id: 'user-1',
      name: 'John Doe',
      modifiedAt: DateTime(2023),
      createdAt: DateTime(2023),
    );

    final testProfile = ProfileMixin(
      id: 'profile-1',
      userId: 'user-1',
      bio: 'Loves Dart and Flutter.',
      modifiedAt: DateTime(2023),
      createdAt: DateTime(2023),
    );

    final testPost1 = PostMixin(
      id: 'post-1',
      userId: 'user-1',
      title: 'My First Post',
      modifiedAt: DateTime(2023),
      createdAt: DateTime(2023),
    );

    final testPost2 = PostMixin(
      id: 'post-2',
      userId: 'user-1',
      title: 'My Second Post',
      modifiedAt: DateTime(2023, 2),
      createdAt: DateTime(2023, 2),
    );

    final testComment1 = CommentMixin(
      id: 'comment-1',
      userId: 'other-user',
      postId: 'post-1',
      content: 'Great post!',
      modifiedAt: DateTime(2023),
      createdAt: DateTime(2023),
    );

    final testComment2 = CommentMixin(
      id: 'comment-2',
      userId: 'other-user',
      postId: 'post-1',
      content: 'I agree!',
      modifiedAt: DateTime(2023),
      createdAt: DateTime(2023),
    );

    setUp(() async {
      // Create mock adapters for all entity types
      final userAdapter = MockLocalAdapter<UserMixin>();
      final postAdapter = MockLocalAdapter<PostMixin>();
      final profileAdapter = MockLocalAdapter<ProfileMixin>();
      final commentAdapter = MockLocalAdapter<CommentMixin>();
      final categoryAdapter = MockLocalAdapter<CategoryMixin>();
      final productAdapter = MockLocalAdapter<ProductMixin>();
      final reviewAdapter = MockLocalAdapter<ReviewMixin>();
      final tagAdapter = MockLocalAdapter<TagMixin>();
      final blogPostAdapter = MockLocalAdapter<BlogPostMixin>();
      final ecommerceProductAdapter = MockLocalAdapter<EcommerceProductMixin>();

      // Create and stub connectivity checker
      final connectivityChecker = MockConnectivityChecker();
      when(() => connectivityChecker.onStatusChange).thenAnswer((_) => Stream.value(true));
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);

      Datum.resetForTesting();
      final result = await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: connectivityChecker,
        registrations: [
          DatumRegistration<UserMixin>(
            localAdapter: userAdapter,
            remoteAdapter: MockRemoteAdapter<UserMixin>(),
          ),
          DatumRegistration<PostMixin>(
            localAdapter: postAdapter,
            remoteAdapter: MockRemoteAdapter<PostMixin>(),
          ),
          DatumRegistration<ProfileMixin>(
            localAdapter: profileAdapter,
            remoteAdapter: MockRemoteAdapter<ProfileMixin>(),
          ),
          DatumRegistration<CommentMixin>(
            localAdapter: commentAdapter,
            remoteAdapter: MockRemoteAdapter<CommentMixin>(),
          ),
          DatumRegistration<CategoryMixin>(
            localAdapter: categoryAdapter,
            remoteAdapter: MockRemoteAdapter<CategoryMixin>(),
          ),
          DatumRegistration<ProductMixin>(
            localAdapter: productAdapter,
            remoteAdapter: MockRemoteAdapter<ProductMixin>(),
          ),
          DatumRegistration<ReviewMixin>(
            localAdapter: reviewAdapter,
            remoteAdapter: MockRemoteAdapter<ReviewMixin>(),
          ),
          DatumRegistration<TagMixin>(
            localAdapter: tagAdapter,
            remoteAdapter: MockRemoteAdapter<TagMixin>(),
          ),
          DatumRegistration<BlogPostMixin>(
            localAdapter: blogPostAdapter,
            remoteAdapter: MockRemoteAdapter<BlogPostMixin>(),
          ),
          DatumRegistration<EcommerceProductMixin>(
            localAdapter: ecommerceProductAdapter,
            remoteAdapter: MockRemoteAdapter<EcommerceProductMixin>(),
          ),
        ],
      );

      if (result case Failure(value: final e, stackTrace: final s)) {
        fail('Datum initialization failed: $e\n$s');
      }

      userManager = Datum.manager<UserMixin>();
      postManager = Datum.manager<PostMixin>();
      profileManager = Datum.manager<ProfileMixin>();
      commentManager = Datum.manager<CommentMixin>();
      categoryManager = Datum.manager<CategoryMixin>();
      productManager = Datum.manager<ProductMixin>();
      reviewManager = Datum.manager<ReviewMixin>();
      tagManager = Datum.manager<TagMixin>();
    });

    tearDown(() {
      if (Datum.isInitialized) {
        Datum.resetForTesting();
      }
    });

    test('cascadeDelete successfully deletes user and all related entities with mixins', () async {
      // Arrange: Create a complete user with posts, profile, and comments
      await userManager.push(item: testUser, userId: testUser.id);
      await profileManager.push(item: testProfile, userId: testUser.id);
      await postManager.push(item: testPost1, userId: testUser.id);
      await postManager.push(item: testPost2, userId: testUser.id);
      await commentManager.push(item: testComment1, userId: testUser.id);
      await commentManager.push(item: testComment2, userId: testUser.id);

      // Verify all entities exist
      expect(await userManager.read(testUser.id), isNotNull);
      expect(await profileManager.read(testProfile.id), isNotNull);
      expect(await postManager.read(testPost1.id), isNotNull);
      expect(await postManager.read(testPost2.id), isNotNull);
      expect(await commentManager.read(testComment1.id), isNotNull);
      expect(await commentManager.read(testComment2.id), isNotNull);

      // Act: Cascade delete the user
      final result = await userManager.cascadeDelete(id: testUser.id, userId: testUser.id);

      // Assert: Operation was successful
      expect(result.success, isTrue);
      expect(result.errors, isEmpty);
      expect(result.totalDeleted, 6); // User + Profile + 2 Posts + 2 Comments

      // Verify all entities were deleted
      expect(await userManager.read(testUser.id), isNull);
      expect(await profileManager.read(testProfile.id), isNull);
      expect(await postManager.read(testPost1.id), isNull);
      expect(await postManager.read(testPost2.id), isNull);
      expect(await commentManager.read(testComment1.id), isNull);
      expect(await commentManager.read(testComment2.id), isNull);

      // Check deleted entities map
      expect(result.deletedEntities[UserMixin], hasLength(1));
      expect(result.deletedEntities[ProfileMixin], hasLength(1));
      expect(result.deletedEntities[PostMixin], hasLength(2));
      expect(result.deletedEntities[CommentMixin], hasLength(2));
    });

    test('cascadeDelete fails when restrict relationship has related entities with mixins', () async {
      // Arrange: Create user with comments (restrict relationship)
      await userManager.push(item: testUser, userId: testUser.id);
      final restrictComment = CommentMixin(
        id: 'restrict-comment',
        userId: testUser.id,
        postId: 'non-existent-post',
        content: 'Restrict test comment',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );
      await commentManager.push(item: restrictComment, userId: testUser.id);

      // Act: Try to cascade delete the user
      final result = await userManager.cascadeDelete(id: testUser.id, userId: testUser.id);

      // Assert: Operation failed due to restrict constraint
      expect(result.success, isFalse);
      expect(result.errors, isNotEmpty);
      expect(result.restrictedRelations.containsKey('comments'), isTrue);
      expect(result.restrictedRelations['comments'], hasLength(1));

      // Verify entities still exist
      expect(await userManager.read(testUser.id), isNotNull);
      expect(await commentManager.read(restrictComment.id), isNotNull);
    });

    test('cascadeDelete handles complex product catalog with reviews and tags with mixins', () async {
      // Arrange: Create a complex e-commerce scenario
      final category = CategoryMixin(
        id: 'gadgets',
        userId: testUser.id,
        name: 'Gadgets',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final product = ProductMixin(
        id: 'smartphone',
        userId: testUser.id,
        name: 'Smartphone X',
        categoryId: 'gadgets',
        price: 999.99,
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final review1 = ReviewMixin(
        id: 'review1',
        userId: testUser.id,
        productId: 'smartphone',
        rating: 5,
        comment: 'Amazing phone!',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final review2 = ReviewMixin(
        id: 'review2',
        userId: testUser.id,
        productId: 'smartphone',
        rating: 4,
        comment: 'Good but expensive',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final tag1 = TagMixin(
        id: 'tag1',
        userId: testUser.id,
        name: 'electronics',
        productId: 'smartphone',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final tag2 = TagMixin(
        id: 'tag2',
        userId: testUser.id,
        name: 'mobile',
        productId: 'smartphone',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      await categoryManager.push(item: category, userId: testUser.id);
      await productManager.push(item: product, userId: testUser.id);
      await reviewManager.push(item: review1, userId: testUser.id);
      await reviewManager.push(item: review2, userId: testUser.id);
      await tagManager.push(item: tag1, userId: testUser.id);
      await tagManager.push(item: tag2, userId: testUser.id);

      // Act: Delete category (should cascade through all related entities)
      final result = await categoryManager.cascadeDelete(id: 'gadgets', userId: testUser.id);

      // Assert: All related entities are deleted
      expect(result.success, isTrue);
      expect(result.totalDeleted, 6); // Category + Product + 2 Reviews + 2 Tags
      expect(result.deletedEntities[CategoryMixin], hasLength(1));
      expect(result.deletedEntities[ProductMixin], hasLength(1));
      expect(result.deletedEntities[ReviewMixin], hasLength(2));
      expect(result.deletedEntities[TagMixin], hasLength(2));

      // Verify all are deleted
      expect(await categoryManager.read('gadgets'), isNull);
      expect(await productManager.read('smartphone'), isNull);
      expect(await reviewManager.read('review1'), isNull);
      expect(await reviewManager.read('review2'), isNull);
      expect(await tagManager.read('tag1'), isNull);
      expect(await tagManager.read('tag2'), isNull);
    });

    test('cascadeDelete works with single mixin (Commentable) using mixins', () async {
      // Arrange: Create a BlogPost with comments using the Commentable mixin
      final blogPostManager = Datum.manager<BlogPostMixin>();

      final blogPost = BlogPostMixin(
        id: 'blog-post-1',
        userId: testUser.id,
        title: 'My Blog Post',
        content: 'This is a blog post content',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final comment1 = CommentMixin(
        id: 'blog-comment-1',
        userId: 'other-user',
        postId: 'blog-post-1',
        content: 'Great blog post!',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final comment2 = CommentMixin(
        id: 'blog-comment-2',
        userId: 'other-user',
        postId: 'blog-post-1',
        content: 'I learned something new',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      await blogPostManager.push(item: blogPost, userId: testUser.id);
      await commentManager.push(item: comment1, userId: testUser.id);
      await commentManager.push(item: comment2, userId: testUser.id);

      // Act: Cascade delete the blog post
      final result = await blogPostManager.cascadeDelete(id: 'blog-post-1', userId: testUser.id);

      // Assert: Blog post and all comments are deleted
      expect(result.success, isTrue);
      expect(result.totalDeleted, 3); // BlogPost + 2 Comments
      expect(result.deletedEntities[BlogPostMixin], hasLength(1));
      expect(result.deletedEntities[CommentMixin], hasLength(2));

      // Verify all are deleted
      expect(await blogPostManager.read('blog-post-1'), isNull);
      expect(await commentManager.read('blog-comment-1'), isNull);
      expect(await commentManager.read('blog-comment-2'), isNull);
    });

    test('cascadeDelete works with multiple mixins (Categorized, Reviewable, Taggable) using mixins', () async {
      // Arrange: Create an EcommerceProduct with category, reviews, and tags using multiple mixins
      final ecommerceProductManager = Datum.manager<EcommerceProductMixin>();

      final category = CategoryMixin(
        id: 'product-category',
        userId: testUser.id,
        name: 'Electronics',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final product = EcommerceProductMixin(
        id: 'ecommerce-product-1',
        userId: testUser.id,
        name: 'Wireless Headphones',
        categoryId: 'product-category',
        price: 199.99,
        description: 'High-quality wireless headphones',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final review1 = ReviewMixin(
        id: 'product-review-1',
        userId: testUser.id,
        productId: 'ecommerce-product-1',
        rating: 5,
        comment: 'Amazing sound quality!',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final review2 = ReviewMixin(
        id: 'product-review-2',
        userId: testUser.id,
        productId: 'ecommerce-product-1',
        rating: 4,
        comment: 'Good value for money',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final tag1 = TagMixin(
        id: 'product-tag-1',
        userId: testUser.id,
        name: 'wireless',
        productId: 'ecommerce-product-1',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final tag2 = TagMixin(
        id: 'product-tag-2',
        userId: testUser.id,
        name: 'audio',
        productId: 'ecommerce-product-1',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      await categoryManager.push(item: category, userId: testUser.id);
      await ecommerceProductManager.push(item: product, userId: testUser.id);
      await reviewManager.push(item: review1, userId: testUser.id);
      await reviewManager.push(item: review2, userId: testUser.id);
      await tagManager.push(item: tag1, userId: testUser.id);
      await tagManager.push(item: tag2, userId: testUser.id);

      // Act: Cascade delete the product
      final result = await ecommerceProductManager.cascadeDelete(id: 'ecommerce-product-1', userId: testUser.id);

      // Assert: Product and all related entities from mixins are deleted
      expect(result.success, isTrue);
      expect(result.totalDeleted, 5); // Product + 2 Reviews + 2 Tags
      expect(result.deletedEntities[EcommerceProductMixin], hasLength(1));
      expect(result.deletedEntities[ReviewMixin], hasLength(2));
      expect(result.deletedEntities[TagMixin], hasLength(2));

      // Verify all are deleted
      expect(await ecommerceProductManager.read('ecommerce-product-1'), isNull);
      expect(await reviewManager.read('product-review-1'), isNull);
      expect(await reviewManager.read('product-review-2'), isNull);
      expect(await tagManager.read('product-tag-1'), isNull);
      expect(await tagManager.read('product-tag-2'), isNull);

      // Category should still exist (belongsTo with none behavior)
      expect(await categoryManager.read('product-category'), isNotNull);
    });
  });
}
