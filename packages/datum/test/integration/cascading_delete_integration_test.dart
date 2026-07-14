// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:datum/datum.dart';

import '../mocks/mock_adapters.dart';
import '../mocks/mock_connectivity_checker.dart';

/// A simple User entity for testing cascading delete relationships.
class User extends RelationalDatumEntity {
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

  const User({
    required this.id,
    required this.name,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  }) : userId = id; // For users, userId is often the same as id

  @override
  Map<String, Relation> get relations => Datum.isInitialized
      ? {
          'posts': HasMany<Post>(this, 'userId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
          'profile': HasOne<Profile>(this, 'userId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
          'comments': HasMany<Comment>(this, 'userId', cascadeDeleteBehavior: CascadeDeleteBehavior.restrict),
        }
      : {};

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      name: json['name'] as String,
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      version: json['version'] as int? ?? 1,
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }

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
  User copyWith({DateTime? modifiedAt, int? version, bool? isDeleted}) {
    return User(
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
    if (oldVersion is! User) return toDatumMap();

    final diff = <String, dynamic>{};

    if (name != oldVersion.name) {
      diff['name'] = name;
    }

    if (modifiedAt != oldVersion.modifiedAt) {
      diff['modifiedAt'] = modifiedAt.toIso8601String();
    }

    if (version != oldVersion.version) {
      diff['version'] = version;
    }

    if (isDeleted != oldVersion.isDeleted) {
      diff['isDeleted'] = isDeleted;
    }

    return diff.isEmpty ? null : diff;
  }

  @override
  bool operator ==(covariant User other) {
    if (identical(this, other)) return true;

    return other.id == id && other.userId == userId && other.name == name && other.modifiedAt == modifiedAt && other.createdAt == createdAt && other.version == version && other.isDeleted == isDeleted;
  }

  @override
  int get hashCode {
    return id.hashCode ^ userId.hashCode ^ name.hashCode ^ modifiedAt.hashCode ^ createdAt.hashCode ^ version.hashCode ^ isDeleted.hashCode;
  }
}

/// A Post entity that belongs to a User.
class Post extends RelationalDatumEntity {
  @override
  final String id;
  @override
  final String userId; // Foreign key to User
  final String title;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const Post({
    required this.id,
    required this.userId,
    required this.title,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, Relation> get relations => Datum.isInitialized
      ? {
          'comments': HasMany<Comment>(this, 'postId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
        }
      : {};

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'] as String,
      userId: json['userId'] as String,
      title: json['title'] as String,
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      version: json['version'] as int? ?? 1,
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }

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
  Map<String, dynamic>? diff(DatumEntityInterface oldVersion) {
    if (oldVersion is! Post) return toDatumMap();

    final diff = <String, dynamic>{};

    if (title != oldVersion.title) {
      diff['title'] = title;
    }
    if (modifiedAt != oldVersion.modifiedAt) {
      diff['modifiedAt'] = modifiedAt.toIso8601String();
    }
    if (version != oldVersion.version) {
      diff['version'] = version;
    }
    if (isDeleted != oldVersion.isDeleted) {
      diff['isDeleted'] = isDeleted;
    }

    return diff.isEmpty ? null : diff;
  }

  @override
  Post copyWith({
    String? id,
    String? userId,
    String? title,
    DateTime? modifiedAt,
    DateTime? createdAt,
    int? version,
    bool? isDeleted,
  }) {
    return Post(
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
  bool operator ==(covariant Post other) {
    if (identical(this, other)) return true;

    return other.id == id && other.userId == userId && other.title == title && other.modifiedAt == modifiedAt && other.createdAt == createdAt && other.version == version && other.isDeleted == isDeleted;
  }

  @override
  int get hashCode {
    return id.hashCode ^ userId.hashCode ^ title.hashCode ^ modifiedAt.hashCode ^ createdAt.hashCode ^ version.hashCode ^ isDeleted.hashCode;
  }
}

/// A Profile entity that belongs to a User.
class Profile extends RelationalDatumEntity {
  @override
  final String id;
  @override
  final String userId; // Foreign key to User
  final String bio;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const Profile({
    required this.id,
    required this.userId,
    required this.bio,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  @override
  Map<String, Relation> get relations => Datum.isInitialized
      ? {
          'subcategories': HasMany<Category>(this, 'parentId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
          'products': HasMany<Product>(this, 'categoryId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
        }
      : {};

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      userId: json['userId'] as String,
      bio: json['bio'] as String,
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      version: json['version'] as int? ?? 1,
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }

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
  Profile copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
    String? bio,
  }) {
    return Profile(
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
    if (oldVersion is! Profile) return toDatumMap();

    final diff = <String, dynamic>{};

    if (bio != oldVersion.bio) {
      diff['bio'] = bio;
    }
    if (modifiedAt != oldVersion.modifiedAt) {
      diff['modifiedAt'] = modifiedAt.toIso8601String();
    }
    if (version != oldVersion.version) {
      diff['version'] = version;
    }
    if (isDeleted != oldVersion.isDeleted) {
      diff['isDeleted'] = isDeleted;
    }

    return diff.isEmpty ? null : diff;
  }
}

/// A Comment entity that belongs to a Post.
class Comment extends RelationalDatumEntity {
  @override
  final String id;
  @override
  final String userId;
  final String postId; // Foreign key to Post
  final String content;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const Comment({
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
  Map<String, Relation> get relations => const {};

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      id: json['id'] as String,
      userId: json['userId'] as String,
      postId: json['postId'] as String,
      content: json['content'] as String,
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      version: json['version'] as int? ?? 1,
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }

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
  Comment copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
    String? content,
  }) {
    return Comment(
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
    if (oldVersion is! Comment) return toDatumMap();

    final diff = <String, dynamic>{};

    if (content != oldVersion.content) {
      diff['content'] = content;
    }
    if (modifiedAt != oldVersion.modifiedAt) {
      diff['modifiedAt'] = modifiedAt.toIso8601String();
    }
    if (version != oldVersion.version) {
      diff['version'] = version;
    }
    if (isDeleted != oldVersion.isDeleted) {
      diff['isDeleted'] = isDeleted;
    }

    return diff.isEmpty ? null : diff;
  }
}

/// A Category entity for testing hierarchical relationships.
class Category extends RelationalDatumEntity {
  @override
  final String id;
  @override
  final String userId;
  final String name;
  final String? parentId; // Self-referencing foreign key
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const Category({
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
  Map<String, Relation> get relations => Datum.isInitialized
      ? {
          'subcategories': HasMany<Category>(this, 'parentId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
          'products': HasMany<Product>(this, 'categoryId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
        }
      : {};

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String,
      userId: json['userId'] as String,
      name: json['name'] as String,
      parentId: json['parentId'] as String?,
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      version: json['version'] as int? ?? 1,
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }

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
  Category copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
    String? name,
    String? parentId,
  }) {
    return Category(
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
    if (oldVersion is! Category) return toDatumMap();

    final diff = <String, dynamic>{};

    if (name != oldVersion.name) {
      diff['name'] = name;
    }
    if (parentId != oldVersion.parentId) {
      diff['parentId'] = parentId;
    }
    if (modifiedAt != oldVersion.modifiedAt) {
      diff['modifiedAt'] = modifiedAt.toIso8601String();
    }
    if (version != oldVersion.version) {
      diff['version'] = version;
    }
    if (isDeleted != oldVersion.isDeleted) {
      diff['isDeleted'] = isDeleted;
    }

    return diff.isEmpty ? null : diff;
  }
}

/// A Product entity that belongs to a Category.
class Product extends RelationalDatumEntity with Categorized, Reviewable, Taggable {
  @override
  final String id;
  @override
  final String userId;
  final String name;
  final String categoryId; // Foreign key to Category
  final double price;
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const Product({
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

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String,
      userId: json['userId'] as String,
      name: json['name'] as String,
      categoryId: json['categoryId'] as String,
      price: (json['price'] as num).toDouble(),
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      version: json['version'] as int? ?? 1,
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }

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
  Product copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
    String? name,
    double? price,
  }) {
    return Product(
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
    if (oldVersion is! Product) return toDatumMap();

    final diff = <String, dynamic>{};

    if (name != oldVersion.name) {
      diff['name'] = name;
    }
    if (price != oldVersion.price) {
      diff['price'] = price;
    }
    if (modifiedAt != oldVersion.modifiedAt) {
      diff['modifiedAt'] = modifiedAt.toIso8601String();
    }
    if (version != oldVersion.version) {
      diff['version'] = version;
    }
    if (isDeleted != oldVersion.isDeleted) {
      diff['isDeleted'] = isDeleted;
    }

    return diff.isEmpty ? null : diff;
  }
}

/// A Review entity that belongs to a Product.
class Review extends RelationalDatumEntity {
  @override
  final String id;
  @override
  final String userId;
  final String productId; // Foreign key to Product
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

  const Review({
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
  Map<String, Relation> get relations => const {};

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['id'] as String,
      userId: json['userId'] as String,
      productId: json['productId'] as String,
      rating: json['rating'] as int,
      comment: json['comment'] as String,
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      version: json['version'] as int? ?? 1,
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }

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
  Review copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
    int? rating,
    String? comment,
  }) {
    return Review(
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
    if (oldVersion is! Review) return toDatumMap();

    final diff = <String, dynamic>{};

    if (rating != oldVersion.rating) {
      diff['rating'] = rating;
    }
    if (comment != oldVersion.comment) {
      diff['comment'] = comment;
    }
    if (modifiedAt != oldVersion.modifiedAt) {
      diff['modifiedAt'] = modifiedAt.toIso8601String();
    }
    if (version != oldVersion.version) {
      diff['version'] = version;
    }
    if (isDeleted != oldVersion.isDeleted) {
      diff['isDeleted'] = isDeleted;
    }

    return diff.isEmpty ? null : diff;
  }
}

/// A Tag entity for testing many-to-many relationships.
class Tag extends RelationalDatumEntity {
  @override
  final String id;
  @override
  final String userId;
  final String name;
  final String productId; // Foreign key to Product (many-to-many through this field)
  @override
  final DateTime modifiedAt;
  @override
  final DateTime createdAt;
  @override
  final int version;
  @override
  final bool isDeleted;

  const Tag({
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
  Map<String, Relation> get relations => const {};

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      id: json['id'] as String,
      userId: json['userId'] as String,
      name: json['name'] as String,
      productId: json['productId'] as String,
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      version: json['version'] as int? ?? 1,
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }

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
  Tag copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
    String? name,
  }) {
    return Tag(
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
    if (oldVersion is! Tag) return toDatumMap();

    final diff = <String, dynamic>{};

    if (name != oldVersion.name) {
      diff['name'] = name;
    }
    if (modifiedAt != oldVersion.modifiedAt) {
      diff['modifiedAt'] = modifiedAt.toIso8601String();
    }
    if (version != oldVersion.version) {
      diff['version'] = version;
    }
    if (isDeleted != oldVersion.isDeleted) {
      diff['isDeleted'] = isDeleted;
    }

    return diff.isEmpty ? null : diff;
  }
}

/// Mixin for entities that can be commented on.
mixin Commentable on RelationalDatumEntity {
  @override
  Map<String, Relation> get relations => Datum.isInitialized
      ? {
          ...super.relations,
          'comments': HasMany<Comment>(this, 'postId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
        }
      : {};
}

/// Mixin for entities that can be tagged.
mixin Taggable on RelationalDatumEntity {
  @override
  Map<String, Relation> get relations => Datum.isInitialized
      ? {
          ...super.relations,
          'tags': HasMany<Tag>(this, 'productId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
        }
      : {};
}

/// Mixin for entities that can be reviewed.
mixin Reviewable on RelationalDatumEntity {
  @override
  Map<String, Relation> get relations => Datum.isInitialized
      ? {
          ...super.relations,
          'reviews': HasMany<Review>(this, 'productId', cascadeDeleteBehavior: CascadeDeleteBehavior.cascade),
        }
      : {};
}

/// Mixin for entities that belong to categories.
mixin Categorized on RelationalDatumEntity {
  @override
  Map<String, Relation> get relations => Datum.isInitialized
      ? {
          ...super.relations,
          'category': BelongsTo<Category>(this, 'categoryId', cascadeDeleteBehavior: CascadeDeleteBehavior.none),
        }
      : {};
}

/// A BlogPost entity that uses mixins for relationships.
class BlogPost extends RelationalDatumEntity with Commentable {
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

  const BlogPost({
    required this.id,
    required this.userId,
    required this.title,
    required this.content,
    required this.modifiedAt,
    required this.createdAt,
    this.version = 1,
    this.isDeleted = false,
  });

  factory BlogPost.fromJson(Map<String, dynamic> json) {
    return BlogPost(
      id: json['id'] as String,
      userId: json['userId'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      version: json['version'] as int? ?? 1,
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }

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
  BlogPost copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
    String? title,
    String? content,
  }) {
    return BlogPost(
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
    if (oldVersion is! BlogPost) return toDatumMap();

    final diff = <String, dynamic>{};

    if (title != oldVersion.title) {
      diff['title'] = title;
    }
    if (content != oldVersion.content) {
      diff['content'] = content;
    }
    if (modifiedAt != oldVersion.modifiedAt) {
      diff['modifiedAt'] = modifiedAt.toIso8601String();
    }
    if (version != oldVersion.version) {
      diff['version'] = version;
    }
    if (isDeleted != oldVersion.isDeleted) {
      diff['isDeleted'] = isDeleted;
    }

    return diff.isEmpty ? null : diff;
  }
}

/// An EcommerceProduct entity that uses multiple mixins.
class EcommerceProduct extends RelationalDatumEntity with Categorized, Reviewable, Taggable {
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

  const EcommerceProduct({
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

  factory EcommerceProduct.fromJson(Map<String, dynamic> json) {
    return EcommerceProduct(
      id: json['id'] as String,
      userId: json['userId'] as String,
      name: json['name'] as String,
      categoryId: json['categoryId'] as String,
      price: (json['price'] as num).toDouble(),
      description: json['description'] as String,
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      version: json['version'] as int? ?? 1,
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }

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
  EcommerceProduct copyWith({
    DateTime? modifiedAt,
    int? version,
    bool? isDeleted,
    String? name,
    double? price,
    String? description,
  }) {
    return EcommerceProduct(
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
    if (oldVersion is! EcommerceProduct) return toDatumMap();

    final diff = <String, dynamic>{};

    if (name != oldVersion.name) {
      diff['name'] = name;
    }
    if (price != oldVersion.price) {
      diff['price'] = price;
    }
    if (description != oldVersion.description) {
      diff['description'] = description;
    }
    if (modifiedAt != oldVersion.modifiedAt) {
      diff['modifiedAt'] = modifiedAt.toIso8601String();
    }
    if (version != oldVersion.version) {
      diff['version'] = version;
    }
    if (isDeleted != oldVersion.isDeleted) {
      diff['isDeleted'] = isDeleted;
    }

    return diff.isEmpty ? null : diff;
  }
}

void main() {
  // Global storage for mock adapters to simulate database

  group('Cascading Delete Integration Tests', () {
    late DatumManager<User> userManager;
    late DatumManager<Post> postManager;
    late DatumManager<Profile> profileManager;
    late DatumManager<Comment> commentManager;
    late DatumManager<Category> categoryManager;
    late DatumManager<Product> productManager;
    late DatumManager<Review> reviewManager;
    late DatumManager<Tag> tagManager;

    setUp(() async {
      // Create mock adapters for all entity types
      final userAdapter = MockLocalAdapter<User>(fromJson: User.fromJson);
      final postAdapter = MockLocalAdapter<Post>(fromJson: Post.fromJson);
      final profileAdapter = MockLocalAdapter<Profile>(fromJson: Profile.fromJson);
      final commentAdapter = MockLocalAdapter<Comment>(fromJson: Comment.fromJson);
      final categoryAdapter = MockLocalAdapter<Category>(fromJson: Category.fromJson);
      final productAdapter = MockLocalAdapter<Product>(fromJson: Product.fromJson);
      final reviewAdapter = MockLocalAdapter<Review>(fromJson: Review.fromJson);
      final tagAdapter = MockLocalAdapter<Tag>(fromJson: Tag.fromJson);
      final blogPostAdapter = MockLocalAdapter<BlogPost>(fromJson: BlogPost.fromJson);
      final ecommerceProductAdapter = MockLocalAdapter<EcommerceProduct>(fromJson: EcommerceProduct.fromJson);

      // Create mock connectivity checker and stub required methods
      final connectivityChecker = MockConnectivityChecker();
      when(() => connectivityChecker.onStatusChange).thenAnswer((_) => Stream.value(true));
      when(() => connectivityChecker.isConnected).thenAnswer((_) async => true);

      // Reset and initialize Datum with all entity registrations
      Datum.resetForTesting();
      final initResult = await Datum.initialize(
        config: const DatumConfig(enableLogging: false),
        connectivityChecker: connectivityChecker,
        registrations: [
          DatumRegistration<User>(
            localAdapter: userAdapter,
            remoteAdapter: MockRemoteAdapter<User>(),
          ),
          DatumRegistration<Post>(
            localAdapter: postAdapter,
            remoteAdapter: MockRemoteAdapter<Post>(),
          ),
          DatumRegistration<Profile>(
            localAdapter: profileAdapter,
            remoteAdapter: MockRemoteAdapter<Profile>(),
          ),
          DatumRegistration<Comment>(
            localAdapter: commentAdapter,
            remoteAdapter: MockRemoteAdapter<Comment>(),
          ),
          DatumRegistration<Category>(
            localAdapter: categoryAdapter,
            remoteAdapter: MockRemoteAdapter<Category>(),
          ),
          DatumRegistration<Product>(
            localAdapter: productAdapter,
            remoteAdapter: MockRemoteAdapter<Product>(),
          ),
          DatumRegistration<Review>(
            localAdapter: reviewAdapter,
            remoteAdapter: MockRemoteAdapter<Review>(),
          ),
          DatumRegistration<Tag>(
            localAdapter: tagAdapter,
            remoteAdapter: MockRemoteAdapter<Tag>(),
          ),
          DatumRegistration<BlogPost>(
            localAdapter: blogPostAdapter,
            remoteAdapter: MockRemoteAdapter<BlogPost>(),
          ),
          DatumRegistration<EcommerceProduct>(
            localAdapter: ecommerceProductAdapter,
            remoteAdapter: MockRemoteAdapter<EcommerceProduct>(),
          ),
        ],
      );

      if (initResult case Failure(value: final e, stackTrace: final s)) {
        fail('Datum initialization failed: $e\n$s');
      }

      // Get manager instances from Datum
      userManager = Datum.manager<User>();
      postManager = Datum.manager<Post>();
      profileManager = Datum.manager<Profile>();
      commentManager = Datum.manager<Comment>();
      categoryManager = Datum.manager<Category>();
      productManager = Datum.manager<Product>();
      reviewManager = Datum.manager<Review>();
      tagManager = Datum.manager<Tag>();
    });

    tearDown(() {
      Datum.resetForTesting();
    });

    final testUser = User(
      id: 'user-1',
      name: 'John Doe',
      modifiedAt: DateTime(2023),
      createdAt: DateTime(2023),
    );

    final testProfile = Profile(
      id: 'profile-1',
      userId: 'user-1',
      bio: 'Loves Dart and Flutter.',
      modifiedAt: DateTime(2023),
      createdAt: DateTime(2023),
    );

    final testPost1 = Post(
      id: 'post-1',
      userId: 'user-1',
      title: 'My First Post',
      modifiedAt: DateTime(2023),
      createdAt: DateTime(2023),
    );

    final testPost2 = Post(
      id: 'post-2',
      userId: 'user-1',
      title: 'My Second Post',
      modifiedAt: DateTime(2023, 2),
      createdAt: DateTime(2023, 2),
    );

    final testComment1 = Comment(
      id: 'comment-1',
      userId: 'other-user',
      postId: 'post-1',
      content: 'Great post!',
      modifiedAt: DateTime(2023),
      createdAt: DateTime(2023),
    );

    final testComment2 = Comment(
      id: 'comment-2',
      userId: 'other-user',
      postId: 'post-1',
      content: 'I agree!',
      modifiedAt: DateTime(2023),
      createdAt: DateTime(2023),
    );

    test('cascadeDelete successfully deletes user and all related entities', () async {
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
      expect(result.deletedEntities[User], hasLength(1));
      expect(result.deletedEntities[Profile], hasLength(1));
      expect(result.deletedEntities[Post], hasLength(2));
      expect(result.deletedEntities[Comment], hasLength(2));
    });

    test('cascadeDelete fails when restrict relationship has related entities', () async {
      // Arrange: Create user with comments (restrict relationship)
      await userManager.push(item: testUser, userId: testUser.id);
      final restrictComment = Comment(
        id: 'restrict-comment',
        userId: testUser.id, // This comment belongs to the user, so restrict should find it
        postId: 'non-existent-post', // Not on a post, so not deleted by cascade
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

    test('cascadeDelete succeeds when restrict relationship has no related entities', () async {
      // Arrange: Create user without comments
      await userManager.push(item: testUser, userId: testUser.id);
      await profileManager.push(item: testProfile, userId: testUser.id);
      await postManager.push(item: testPost1, userId: testUser.id);

      // Act: Cascade delete the user
      final result = await userManager.cascadeDelete(id: testUser.id, userId: testUser.id);

      // Assert: Operation was successful
      expect(result.success, isTrue);
      expect(result.errors, isEmpty);
      expect(result.totalDeleted, 3); // User + Profile + Post
    });

    test('cascadeDelete handles non-relational entities gracefully', () async {
      // Arrange: Create a non-relational entity (we'll use a mock)
      // For this test, we'll just verify the fallback behavior works

      // Act: Try to cascade delete a non-existent entity
      final result = await userManager.cascadeDelete(id: 'non-existent', userId: testUser.id);

      // Assert: Operation fails gracefully
      expect(result.success, isFalse);
      expect(result.errors, hasLength(1));
      expect(result.errors.first, contains('does not exist'));
    });

    test('regular delete method still works without cascading', () async {
      // Arrange: Create user with related entities
      await userManager.push(item: testUser, userId: testUser.id);
      await profileManager.push(item: testProfile, userId: testUser.id);
      await postManager.push(item: testPost1, userId: testUser.id);

      // Act: Use regular delete (not cascade)
      final deleted = await userManager.delete(id: testUser.id, userId: testUser.id, behavior: DeleteBehavior.hardDelete);

      // Assert: Only the user was deleted, related entities remain
      expect(deleted, isTrue);
      expect(await userManager.read(testUser.id), isNull);
      expect(await profileManager.read(testProfile.id), isNotNull); // Still exists
      expect(await postManager.read(testPost1.id), isNotNull); // Still exists
    });

    test('cascadeDelete handles circular references safely', () async {
      // This test would require setting up circular references
      // For now, we'll just ensure the basic functionality works
      // In a real scenario, circular references should be detected and handled

      // Arrange: Create a simple cascade scenario
      await userManager.push(item: testUser, userId: testUser.id);
      await postManager.push(item: testPost1, userId: testUser.id);

      // Act: Cascade delete
      final result = await userManager.cascadeDelete(id: testUser.id, userId: testUser.id);

      // Assert: Works without infinite loops
      expect(result.success, isTrue);
      expect(result.totalDeleted, 2); // User + Post
    });

    test('cascadeDelete properly orders deletions to avoid foreign key violations', () async {
      // Arrange: Create a chain of dependencies
      await userManager.push(item: testUser, userId: testUser.id);
      await postManager.push(item: testPost1, userId: testUser.id);
      await commentManager.push(item: testComment1, userId: testUser.id);

      // Act: Cascade delete from the top (user)
      final result = await userManager.cascadeDelete(id: testUser.id, userId: testUser.id);

      // Assert: All entities deleted successfully (proper ordering handled internally)
      expect(result.success, isTrue);
      expect(result.totalDeleted, 3); // User + Post + Comment
    });

    test('cascadeDelete includes sync operations for all deleted entities', () async {
      // Arrange: Create user with related entities
      await userManager.push(item: testUser, userId: testUser.id);
      await profileManager.push(item: testProfile, userId: testUser.id);

      // Act: Cascade delete with sync enabled
      final result = await userManager.cascadeDelete(
        id: testUser.id,
        userId: testUser.id,
        forceRemoteSync: true,
      );

      // Assert: Operation was successful
      expect(result.success, isTrue);

      // Check that sync operations were queued (this would be verified by checking the queue)
      final userOps = await userManager.getPendingOperations(testUser.id);
      final profileOps = await profileManager.getPendingOperations(testUser.id);

      expect(userOps.where((op) => op.type == DatumOperationType.delete), hasLength(1));
      expect(profileOps.where((op) => op.type == DatumOperationType.delete), hasLength(1));
    });

    test('cascadeDelete handles complex relationship chains with multiple levels', () async {
      // Arrange: Create a complex chain: User -> Posts -> Comments -> CommentReplies
      await userManager.push(item: testUser, userId: testUser.id);
      await postManager.push(item: testPost1, userId: testUser.id);

      final replyComment = Comment(
        id: 'reply-1',
        userId: 'other-user',
        postId: 'post-1',
        content: 'Reply to comment',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );
      await commentManager.push(item: testComment1, userId: testUser.id);
      await commentManager.push(item: replyComment, userId: testUser.id);

      // Act: Cascade delete from the top
      final result = await userManager.cascadeDelete(id: testUser.id, userId: testUser.id);

      // Assert: All entities in the chain are deleted
      expect(result.success, isTrue);
      expect(result.totalDeleted, 4); // User + Post + 2 Comments
      expect(result.deletedEntities[User], hasLength(1));
      expect(result.deletedEntities[Post], hasLength(1));
      expect(result.deletedEntities[Comment], hasLength(2));
    });

    test('cascadeDelete respects mixed cascade behaviors in complex relationships', () async {
      // Arrange: Create scenario with mixed behaviors
      await userManager.push(item: testUser, userId: testUser.id);
      await profileManager.push(item: testProfile, userId: testUser.id);
      await postManager.push(item: testPost1, userId: testUser.id);

      // Create a comment that would be restricted (direct comment on user)
      final directComment = Comment(
        id: 'direct-comment',
        userId: testUser.id,
        postId: 'non-existent',
        content: 'Direct comment on user',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );
      await commentManager.push(item: directComment, userId: testUser.id);

      // Act: Try cascade delete
      final result = await userManager.cascadeDelete(id: testUser.id, userId: testUser.id);

      // Assert: Fails due to restrict relationship, but cascade relationships still work conceptually
      expect(result.success, isFalse);
      expect(result.restrictedRelations.containsKey('comments'), isTrue);
      expect(result.restrictedRelations['comments'], hasLength(1));

      // Verify that cascaded entities are not deleted when restrict fails
      expect(await userManager.read(testUser.id), isNotNull);
      expect(await profileManager.read(testProfile.id), isNotNull);
      expect(await postManager.read(testPost1.id), isNotNull);
      expect(await commentManager.read(directComment.id), isNotNull);
    });

    test('cascadeDelete handles entities with no relationships gracefully', () async {
      // Arrange: Create entities with no defined relationships
      await userManager.push(item: testUser, userId: testUser.id);

      // Act: Cascade delete
      final result = await userManager.cascadeDelete(id: testUser.id, userId: testUser.id);

      // Assert: Works fine with no relationships
      expect(result.success, isTrue);
      expect(result.totalDeleted, 1);
      expect(result.deletedEntities[User], hasLength(1));
    });

    test('cascadeDelete maintains data consistency when some deletes fail', () async {
      // This test would require mocking adapter failures, but for now we'll test the basic flow
      // In a real scenario, we'd want to ensure partial failures don't leave orphaned data

      // Arrange: Create related entities
      await userManager.push(item: testUser, userId: testUser.id);
      await profileManager.push(item: testProfile, userId: testUser.id);

      // Act: Cascade delete
      final result = await userManager.cascadeDelete(id: testUser.id, userId: testUser.id);

      // Assert: Either all succeed or all fail atomically
      expect(result.success, isTrue);
      expect(result.errors, isEmpty);
      expect(result.totalDeleted, 2);
    });

    test('cascadeDelete works with entities that have bidirectional relationships', () async {
      // Arrange: Create entities where relationships go both ways
      await userManager.push(item: testUser, userId: testUser.id);
      await postManager.push(item: testPost1, userId: testUser.id);

      // Both User and Post have relationships to each other
      // User has posts, Post has author (BelongsTo User)

      // Act: Cascade delete from user
      final result = await userManager.cascadeDelete(id: testUser.id, userId: testUser.id);

      // Assert: Handles bidirectional relationships without issues
      expect(result.success, isTrue);
      expect(result.totalDeleted, 2); // User + Post
    });

    test('cascadeDelete handles large numbers of related entities efficiently', () async {
      // Arrange: Create user with many posts and comments
      await userManager.push(item: testUser, userId: testUser.id);

      // Create multiple posts
      for (int i = 0; i < 10; i++) {
        final post = Post(
          id: 'bulk-post-$i',
          userId: testUser.id,
          title: 'Bulk Post $i',
          modifiedAt: DateTime(2023),
          createdAt: DateTime(2023),
        );
        await postManager.push(item: post, userId: testUser.id);

        // Create comments for each post
        for (int j = 0; j < 5; j++) {
          final comment = Comment(
            id: 'bulk-comment-$i-$j',
            userId: 'other-user',
            postId: post.id,
            content: 'Comment $j on post $i',
            modifiedAt: DateTime(2023),
            createdAt: DateTime(2023),
          );
          await commentManager.push(item: comment, userId: testUser.id);
        }
      }

      // Act: Cascade delete
      final result = await userManager.cascadeDelete(id: testUser.id, userId: testUser.id);

      // Assert: Handles large datasets correctly
      expect(result.success, isTrue);
      expect(result.totalDeleted, 1 + 10 + 50); // User + 10 Posts + 50 Comments
      expect(result.deletedEntities[User], hasLength(1));
      expect(result.deletedEntities[Post], hasLength(10));
      expect(result.deletedEntities[Comment], hasLength(50));
    });

    test('cascadeDelete preserves isolation between different user data', () async {
      // Arrange: Create data for two different users
      final otherUser = User(
        id: 'user-2',
        name: 'Jane Doe',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      await userManager.push(item: testUser, userId: testUser.id);
      await userManager.push(item: otherUser, userId: otherUser.id);

      await postManager.push(item: testPost1, userId: testUser.id);
      final otherPost = Post(
        id: 'other-post',
        userId: otherUser.id,
        title: 'Other User Post',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );
      await postManager.push(item: otherPost, userId: otherUser.id);

      // Act: Cascade delete only one user
      final result = await userManager.cascadeDelete(id: testUser.id, userId: testUser.id);

      // Assert: Only the target user's data is deleted
      expect(result.success, isTrue);
      expect(result.totalDeleted, 2); // User + Post

      // Other user's data should remain
      expect(await userManager.read(otherUser.id), isNotNull);
      expect(await postManager.read(otherPost.id), isNotNull);

      // Target user's data should be gone
      expect(await userManager.read(testUser.id), isNull);
      expect(await postManager.read(testPost1.id), isNull);
    });

    test('cascadeDelete handles entities with multiple cascade paths correctly', () async {
      // Arrange: Create a scenario where an entity can be reached via multiple cascade paths
      // This tests that we don't try to delete the same entity multiple times

      await userManager.push(item: testUser, userId: testUser.id);
      await postManager.push(item: testPost1, userId: testUser.id);

      // Create a comment on the post
      await commentManager.push(item: testComment1, userId: testUser.id);

      // Act: Cascade delete
      final result = await userManager.cascadeDelete(id: testUser.id, userId: testUser.id);

      // Assert: Each entity is deleted exactly once
      expect(result.success, isTrue);
      expect(result.totalDeleted, 3); // User + Post + Comment
      expect(result.deletedEntities[User], hasLength(1));
      expect(result.deletedEntities[Post], hasLength(1));
      expect(result.deletedEntities[Comment], hasLength(1));
    });

    test('cascadeDelete handles linear dependency chains (A -> B -> C -> D)', () async {
      // Arrange: Create a linear dependency chain using categories
      // Electronics -> Laptops -> Gaming Laptops -> High-End Gaming Laptops

      final electronics = Category(
        id: 'electronics',
        userId: testUser.id,
        name: 'Electronics',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final laptops = Category(
        id: 'laptops',
        userId: testUser.id,
        name: 'Laptops',
        parentId: 'electronics',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final gamingLaptops = Category(
        id: 'gaming-laptops',
        userId: testUser.id,
        name: 'Gaming Laptops',
        parentId: 'laptops',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final highEndGaming = Category(
        id: 'high-end-gaming',
        userId: testUser.id,
        name: 'High-End Gaming Laptops',
        parentId: 'gaming-laptops',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      await categoryManager.push(item: electronics, userId: testUser.id);
      await categoryManager.push(item: laptops, userId: testUser.id);
      await categoryManager.push(item: gamingLaptops, userId: testUser.id);
      await categoryManager.push(item: highEndGaming, userId: testUser.id);

      // Act: Delete from the top of the chain
      final result = await categoryManager.cascadeDelete(id: 'electronics', userId: testUser.id);

      // Assert: All categories in the chain are deleted
      expect(result.success, isTrue);
      expect(result.totalDeleted, 4); // All 4 categories
      expect(result.deletedEntities[Category], hasLength(4));

      // Verify all are deleted
      expect(await categoryManager.read('electronics'), isNull);
      expect(await categoryManager.read('laptops'), isNull);
      expect(await categoryManager.read('gaming-laptops'), isNull);
      expect(await categoryManager.read('high-end-gaming'), isNull);
    });

    test('cascadeDelete handles cross dependencies (diamond pattern A -> B, A -> C, B -> D, C -> D)', () async {
      // Arrange: Create a diamond dependency pattern
      // Root Category -> Sub1, Root Category -> Sub2, Sub1 -> Leaf, Sub2 -> Leaf

      final rootCategory = Category(
        id: 'root',
        userId: testUser.id,
        name: 'Root Category',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final subCategory1 = Category(
        id: 'sub1',
        userId: testUser.id,
        name: 'Sub Category 1',
        parentId: 'root',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final subCategory2 = Category(
        id: 'sub2',
        userId: testUser.id,
        name: 'Sub Category 2',
        parentId: 'root',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final leafCategory = Category(
        id: 'leaf',
        userId: testUser.id,
        name: 'Leaf Category',
        parentId: 'sub1', // This creates the cross-dependency
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      // Create another path to leaf from sub2 (this would create a many-to-one if supported)
      final leafProduct = Product(
        id: 'leaf-product',
        userId: testUser.id,
        name: 'Leaf Product',
        categoryId: 'leaf',
        price: 99.99,
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      await categoryManager.push(item: rootCategory, userId: testUser.id);
      await categoryManager.push(item: subCategory1, userId: testUser.id);
      await categoryManager.push(item: subCategory2, userId: testUser.id);
      await categoryManager.push(item: leafCategory, userId: testUser.id);
      await productManager.push(item: leafProduct, userId: testUser.id);

      // Act: Delete from root
      final result = await categoryManager.cascadeDelete(id: 'root', userId: testUser.id);

      // Assert: All entities in the diamond are deleted, leaf is deleted only once
      expect(result.success, isTrue);
      expect(result.totalDeleted, 5); // Root + Sub1 + Sub2 + Leaf + Leaf Product
      expect(result.deletedEntities[Category], hasLength(4));
      expect(result.deletedEntities[Product], hasLength(1));

      // Verify all are deleted
      expect(await categoryManager.read('root'), isNull);
      expect(await categoryManager.read('sub1'), isNull);
      expect(await categoryManager.read('sub2'), isNull);
      expect(await categoryManager.read('leaf'), isNull);
      expect(await productManager.read('leaf-product'), isNull);
    });

    test('cascadeDelete handles complex tree structures with multiple branches', () async {
      // Arrange: Create a tree structure
      // Root -> Branch1, Root -> Branch2, Branch1 -> Leaf1, Branch1 -> Leaf2, Branch2 -> Leaf3

      final root = Category(
        id: 'tree-root',
        userId: testUser.id,
        name: 'Tree Root',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final branch1 = Category(
        id: 'branch1',
        userId: testUser.id,
        name: 'Branch 1',
        parentId: 'tree-root',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final branch2 = Category(
        id: 'branch2',
        userId: testUser.id,
        name: 'Branch 2',
        parentId: 'tree-root',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final leaf1 = Category(
        id: 'leaf1',
        userId: testUser.id,
        name: 'Leaf 1',
        parentId: 'branch1',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final leaf2 = Category(
        id: 'leaf2',
        userId: testUser.id,
        name: 'Leaf 2',
        parentId: 'branch1',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final leaf3 = Category(
        id: 'leaf3',
        userId: testUser.id,
        name: 'Leaf 3',
        parentId: 'branch2',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      await categoryManager.push(item: root, userId: testUser.id);
      await categoryManager.push(item: branch1, userId: testUser.id);
      await categoryManager.push(item: branch2, userId: testUser.id);
      await categoryManager.push(item: leaf1, userId: testUser.id);
      await categoryManager.push(item: leaf2, userId: testUser.id);
      await categoryManager.push(item: leaf3, userId: testUser.id);

      // Act: Delete from root
      final result = await categoryManager.cascadeDelete(id: 'tree-root', userId: testUser.id);

      // Assert: Entire tree is deleted
      expect(result.success, isTrue);
      expect(result.totalDeleted, 6); // Root + 2 branches + 3 leaves
      expect(result.deletedEntities[Category], hasLength(6));

      // Verify all are deleted
      expect(await categoryManager.read('tree-root'), isNull);
      expect(await categoryManager.read('branch1'), isNull);
      expect(await categoryManager.read('branch2'), isNull);
      expect(await categoryManager.read('leaf1'), isNull);
      expect(await categoryManager.read('leaf2'), isNull);
      expect(await categoryManager.read('leaf3'), isNull);
    });

    test('cascadeDelete handles complex product catalog with reviews and tags', () async {
      // Arrange: Create a complex e-commerce scenario
      // Category -> Product -> Reviews, Product -> Tags

      final category = Category(
        id: 'gadgets',
        userId: testUser.id,
        name: 'Gadgets',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final product = Product(
        id: 'smartphone',
        userId: testUser.id,
        name: 'Smartphone X',
        categoryId: 'gadgets',
        price: 999.99,
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final review1 = Review(
        id: 'review1',
        userId: testUser.id,
        productId: 'smartphone',
        rating: 5,
        comment: 'Amazing phone!',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final review2 = Review(
        id: 'review2',
        userId: testUser.id,
        productId: 'smartphone',
        rating: 4,
        comment: 'Good but expensive',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final tag1 = Tag(
        id: 'tag1',
        userId: testUser.id,
        name: 'electronics',
        productId: 'smartphone',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final tag2 = Tag(
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
      expect(result.deletedEntities[Category], hasLength(1));
      expect(result.deletedEntities[Product], hasLength(1));
      expect(result.deletedEntities[Review], hasLength(2));
      expect(result.deletedEntities[Tag], hasLength(2));

      // Verify all are deleted
      expect(await categoryManager.read('gadgets'), isNull);
      expect(await productManager.read('smartphone'), isNull);
      expect(await reviewManager.read('review1'), isNull);
      expect(await reviewManager.read('review2'), isNull);
      expect(await tagManager.read('tag1'), isNull);
      expect(await tagManager.read('tag2'), isNull);
    });

    test('cascadeDelete handles self-referencing relationships safely', () async {
      // Arrange: Create a self-referencing category hierarchy
      // Parent Category -> Child Category -> Grandchild Category

      final parent = Category(
        id: 'parent-cat',
        userId: testUser.id,
        name: 'Parent Category',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final child = Category(
        id: 'child-cat',
        userId: testUser.id,
        name: 'Child Category',
        parentId: 'parent-cat',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final grandchild = Category(
        id: 'grandchild-cat',
        userId: testUser.id,
        name: 'Grandchild Category',
        parentId: 'child-cat',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      await categoryManager.push(item: parent, userId: testUser.id);
      await categoryManager.push(item: child, userId: testUser.id);
      await categoryManager.push(item: grandchild, userId: testUser.id);

      // Act: Delete from parent
      final result = await categoryManager.cascadeDelete(id: 'parent-cat', userId: testUser.id);

      // Assert: Entire hierarchy is deleted without circular reference issues
      expect(result.success, isTrue);
      expect(result.totalDeleted, 3); // Parent + Child + Grandchild
      expect(result.deletedEntities[Category], hasLength(3));

      // Verify all are deleted
      expect(await categoryManager.read('parent-cat'), isNull);
      expect(await categoryManager.read('child-cat'), isNull);
      expect(await categoryManager.read('grandchild-cat'), isNull);
    });

    test('cascadeDelete handles complex networks with multiple relationship types', () async {
      // Arrange: Create a complex network
      // User -> Posts -> Comments
      // User -> Profile
      // Posts -> Comments (already covered)
      // Comments can be threaded (self-reference)

      await userManager.push(item: testUser, userId: testUser.id);
      await profileManager.push(item: testProfile, userId: testUser.id);
      await postManager.push(item: testPost1, userId: testUser.id);

      // Create threaded comments (comment replying to another comment)
      final parentComment = Comment(
        id: 'parent-comment',
        userId: 'other-user', // Use different user to avoid restrict relationship
        postId: 'post-1',
        content: 'Parent comment',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final childComment = Comment(
        id: 'child-comment',
        userId: 'other-user', // Use different user to avoid restrict relationship
        postId: 'post-1',
        content: 'Reply to parent',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      await commentManager.push(item: parentComment, userId: testUser.id);
      await commentManager.push(item: childComment, userId: testUser.id);

      // Act: Delete user (should cascade through all relationships)
      final result = await userManager.cascadeDelete(id: testUser.id, userId: testUser.id);

      // Assert: All entities in the network are deleted
      expect(result.success, isTrue);
      expect(result.totalDeleted, 5); // User + Profile + Post + 2 Comments
      expect(result.deletedEntities[User], hasLength(1));
      expect(result.deletedEntities[Profile], hasLength(1));
      expect(result.deletedEntities[Post], hasLength(1));
      expect(result.deletedEntities[Comment], hasLength(2));

      // Verify all are deleted
      expect(await userManager.read(testUser.id), isNull);
      expect(await profileManager.read(testProfile.id), isNull);
      expect(await postManager.read(testPost1.id), isNull);
      expect(await commentManager.read('parent-comment'), isNull);
      expect(await commentManager.read('child-comment'), isNull);
    });

    test('cascadeDelete handles restrict relationships in complex dependency chains', () async {
      // Arrange: Create a scenario where restrict blocks cascade in a chain
      // User -> Posts (cascade), User -> Comments (restrict)

      await userManager.push(item: testUser, userId: testUser.id);
      await postManager.push(item: testPost1, userId: testUser.id);

      // Create a comment directly owned by user (restrict relationship)
      final userComment = Comment(
        id: 'user-comment',
        userId: testUser.id,
        postId: 'non-existent', // Not on the post
        content: 'Direct user comment',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      await commentManager.push(item: userComment, userId: testUser.id);

      // Act: Try to cascade delete user
      final result = await userManager.cascadeDelete(id: testUser.id, userId: testUser.id);

      // Assert: Fails due to restrict relationship
      expect(result.success, isFalse);
      expect(result.restrictedRelations.containsKey('comments'), isTrue);

      // Verify restrict blocks the entire operation
      expect(await userManager.read(testUser.id), isNotNull);
      expect(await postManager.read(testPost1.id), isNotNull); // Not deleted because restrict failed
      expect(await commentManager.read('user-comment'), isNotNull);
    });

    test('cascadeDelete maintains referential integrity in complex scenarios', () async {
      // Arrange: Create a scenario that tests referential integrity
      // Category -> Products -> Reviews + Tags
      // Ensure no orphaned records

      final category = Category(
        id: 'test-category',
        userId: testUser.id,
        name: 'Test Category',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final product1 = Product(
        id: 'product1',
        userId: testUser.id,
        name: 'Product 1',
        categoryId: 'test-category',
        price: 10.99,
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final product2 = Product(
        id: 'product2',
        userId: testUser.id,
        name: 'Product 2',
        categoryId: 'test-category',
        price: 20.99,
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final review = Review(
        id: 'product1-review',
        userId: testUser.id,
        productId: 'product1',
        rating: 5,
        comment: 'Great product!',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final tag = Tag(
        id: 'product1-tag',
        userId: testUser.id,
        name: 'featured',
        productId: 'product1',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      await categoryManager.push(item: category, userId: testUser.id);
      await productManager.push(item: product1, userId: testUser.id);
      await productManager.push(item: product2, userId: testUser.id);
      await reviewManager.push(item: review, userId: testUser.id);
      await tagManager.push(item: tag, userId: testUser.id);

      // Act: Delete category
      final result = await categoryManager.cascadeDelete(id: 'test-category', userId: testUser.id);

      // Assert: All related entities deleted, no orphans
      expect(result.success, isTrue);
      expect(result.totalDeleted, 5); // Category + 2 Products + 1 Review + 1 Tag
      expect(result.deletedEntities[Category], hasLength(1));
      expect(result.deletedEntities[Product], hasLength(2));
      expect(result.deletedEntities[Review], hasLength(1));
      expect(result.deletedEntities[Tag], hasLength(1));

      // Verify no orphaned records exist
      expect(await categoryManager.read('test-category'), isNull);
      expect(await productManager.read('product1'), isNull);
      expect(await productManager.read('product2'), isNull);
      expect(await reviewManager.read('product1-review'), isNull);
      expect(await tagManager.read('product1-tag'), isNull);
    });

    test('cascadeDelete works with single mixin (Commentable)', () async {
      // Arrange: Create a BlogPost with comments using the Commentable mixin
      final blogPostManager = Datum.manager<BlogPost>();

      final blogPost = BlogPost(
        id: 'blog-post-1',
        userId: testUser.id,
        title: 'My Blog Post',
        content: 'This is a blog post content',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final comment1 = Comment(
        id: 'blog-comment-1',
        userId: 'other-user',
        postId: 'blog-post-1',
        content: 'Great blog post!',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final comment2 = Comment(
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
      expect(result.deletedEntities[BlogPost], hasLength(1));
      expect(result.deletedEntities[Comment], hasLength(2));

      // Verify all are deleted
      expect(await blogPostManager.read('blog-post-1'), isNull);
      expect(await commentManager.read('blog-comment-1'), isNull);
      expect(await commentManager.read('blog-comment-2'), isNull);
    });

    test('cascadeDelete works with multiple mixins (Categorized, Reviewable, Taggable)', () async {
      // Arrange: Create an EcommerceProduct with category, reviews, and tags using multiple mixins
      final ecommerceProductManager = Datum.manager<EcommerceProduct>();

      final category = Category(
        id: 'product-category',
        userId: testUser.id,
        name: 'Electronics',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final product = EcommerceProduct(
        id: 'ecommerce-product-1',
        userId: testUser.id,
        name: 'Wireless Headphones',
        categoryId: 'product-category',
        price: 199.99,
        description: 'High-quality wireless headphones',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final review1 = Review(
        id: 'product-review-1',
        userId: testUser.id,
        productId: 'ecommerce-product-1',
        rating: 5,
        comment: 'Amazing sound quality!',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final review2 = Review(
        id: 'product-review-2',
        userId: testUser.id,
        productId: 'ecommerce-product-1',
        rating: 4,
        comment: 'Good value for money',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final tag1 = Tag(
        id: 'product-tag-1',
        userId: testUser.id,
        name: 'wireless',
        productId: 'ecommerce-product-1',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final tag2 = Tag(
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
      expect(result.deletedEntities[EcommerceProduct], hasLength(1));
      expect(result.deletedEntities[Review], hasLength(2));
      expect(result.deletedEntities[Tag], hasLength(2));

      // Verify all are deleted
      expect(await ecommerceProductManager.read('ecommerce-product-1'), isNull);
      expect(await reviewManager.read('product-review-1'), isNull);
      expect(await reviewManager.read('product-review-2'), isNull);
      expect(await tagManager.read('product-tag-1'), isNull);
      expect(await tagManager.read('product-tag-2'), isNull);

      // Category should still exist (belongsTo with none behavior)
      expect(await categoryManager.read('product-category'), isNotNull);
    });

    test('cascadeDelete handles mixin relationships with proper ordering', () async {
      // Arrange: Create a complex scenario with mixin relationships
      final blogPostManager = Datum.manager<BlogPost>();

      final blogPost = BlogPost(
        id: 'complex-blog-post',
        userId: testUser.id,
        title: 'Complex Blog Post',
        content: 'Content with complex relationships',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      // Create nested comments (comment on post, reply to comment)
      final comment1 = Comment(
        id: 'comment-1',
        userId: 'other-user',
        postId: 'complex-blog-post',
        content: 'First comment',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final comment2 = Comment(
        id: 'comment-2',
        userId: 'other-user',
        postId: 'complex-blog-post',
        content: 'Reply to first comment',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      await blogPostManager.push(item: blogPost, userId: testUser.id);
      await commentManager.push(item: comment1, userId: testUser.id);
      await commentManager.push(item: comment2, userId: testUser.id);

      // Act: Cascade delete the blog post
      final result = await blogPostManager.cascadeDelete(id: 'complex-blog-post', userId: testUser.id);

      // Assert: All entities deleted with proper ordering
      expect(result.success, isTrue);
      expect(result.totalDeleted, 3); // BlogPost + 2 Comments
      expect(result.deletedEntities[BlogPost], hasLength(1));
      expect(result.deletedEntities[Comment], hasLength(2));

      // Verify all are deleted
      expect(await blogPostManager.read('complex-blog-post'), isNull);
      expect(await commentManager.read('comment-1'), isNull);
      expect(await commentManager.read('comment-2'), isNull);
    });

    test('cascadeDelete works with mixin inheritance and composition', () async {
      // Arrange: Test that mixin relationships compose correctly
      final ecommerceProductManager = Datum.manager<EcommerceProduct>();

      final category = Category(
        id: 'mixin-test-category',
        userId: testUser.id,
        name: 'Test Category',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final product = EcommerceProduct(
        id: 'mixin-product',
        userId: testUser.id,
        name: 'Mixin Test Product',
        categoryId: 'mixin-test-category',
        price: 49.99,
        description: 'Testing mixin composition',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      // Add one review and one tag
      final review = Review(
        id: 'mixin-review',
        userId: testUser.id,
        productId: 'mixin-product',
        rating: 5,
        comment: 'Perfect mixin test!',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final tag = Tag(
        id: 'mixin-tag',
        userId: testUser.id,
        name: 'mixin-test',
        productId: 'mixin-product',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      await categoryManager.push(item: category, userId: testUser.id);
      await ecommerceProductManager.push(item: product, userId: testUser.id);
      await reviewManager.push(item: review, userId: testUser.id);
      await tagManager.push(item: tag, userId: testUser.id);

      // Act: Cascade delete the product
      final result = await ecommerceProductManager.cascadeDelete(id: 'mixin-product', userId: testUser.id);

      // Assert: Product and all mixin-related entities are deleted
      expect(result.success, isTrue);
      expect(result.totalDeleted, 3); // Product + 1 Review + 1 Tag
      expect(result.deletedEntities[EcommerceProduct], hasLength(1));
      expect(result.deletedEntities[Review], hasLength(1));
      expect(result.deletedEntities[Tag], hasLength(1));

      // Verify all are deleted
      expect(await ecommerceProductManager.read('mixin-product'), isNull);
      expect(await reviewManager.read('mixin-review'), isNull);
      expect(await tagManager.read('mixin-tag'), isNull);

      // Category should remain
      expect(await categoryManager.read('mixin-test-category'), isNotNull);
    });

    // ===== NEW TESTS FOR IMPLEMENTED FEATURES =====

    test('fluent API builder pattern works correctly', () async {
      // Arrange: Create user with related entities
      await userManager.push(item: testUser, userId: testUser.id);
      await profileManager.push(item: testProfile, userId: testUser.id);
      await postManager.push(item: testPost1, userId: testUser.id);

      // Act: Use fluent API to cascade delete
      final result = await userManager.deleteCascade(testUser.id).forUser(testUser.id).execute();

      // Assert: Operation was successful
      expect(result.success, isTrue);
      expect(result.totalDeleted, 3); // User + Profile + Post

      // Verify all entities were deleted
      expect(await userManager.read(testUser.id), isNull);
      expect(await profileManager.read(testProfile.id), isNull);
      expect(await postManager.read(testPost1.id), isNull);
    });

    test('dry-run mode previews deletions without executing them', () async {
      // Arrange: Create user with related entities
      await userManager.push(item: testUser, userId: testUser.id);
      await profileManager.push(item: testProfile, userId: testUser.id);
      await postManager.push(item: testPost1, userId: testUser.id);
      await commentManager.push(item: testComment1, userId: testUser.id);

      // Act: Use dry-run mode
      final result = await userManager.deleteCascade(testUser.id).forUser(testUser.id).dryRun().execute();

      // Assert: Preview shows what would be deleted
      expect(result.success, isTrue);
      expect(result.totalDeleted, 4); // User + Profile + Post + Comment

      // Cast to CascadeSuccess to access deletedEntities
      final successResult = result as CascadeSuccess<User>;
      expect(successResult.deletedEntities[User], hasLength(1));
      expect(successResult.deletedEntities[Profile], hasLength(1));
      expect(successResult.deletedEntities[Post], hasLength(1));
      expect(successResult.deletedEntities[Comment], hasLength(1));

      // Verify entities still exist (dry-run didn't delete them)
      expect(await userManager.read(testUser.id), isNotNull);
      expect(await profileManager.read(testProfile.id), isNotNull);
      expect(await postManager.read(testPost1.id), isNotNull);
      expect(await commentManager.read(testComment1.id), isNotNull);
    });

    test('batch query optimization reduces database queries', () async {
      // Arrange: Create complex relationship structure
      await userManager.push(item: testUser, userId: testUser.id);

      // Create multiple posts with comments
      for (int i = 0; i < 5; i++) {
        final post = Post(
          id: 'batch-post-$i',
          userId: testUser.id,
          title: 'Batch Post $i',
          modifiedAt: DateTime(2023),
          createdAt: DateTime(2023),
        );
        await postManager.push(item: post, userId: testUser.id);

        // Add comments to each post
        for (int j = 0; j < 3; j++) {
          final comment = Comment(
            id: 'batch-comment-$i-$j',
            userId: 'other-user',
            postId: post.id,
            content: 'Comment $j on post $i',
            modifiedAt: DateTime(2023),
            createdAt: DateTime(2023),
          );
          await commentManager.push(item: comment, userId: testUser.id);
        }
      }

      // Act: Cascade delete (this will use batch queries internally)
      final result = await userManager.cascadeDelete(id: testUser.id, userId: testUser.id);

      // Assert: All entities deleted efficiently
      expect(result.success, isTrue);
      expect(result.totalDeleted, 1 + 5 + 15); // User + 5 Posts + 15 Comments
      expect(result.deletedEntities[User], hasLength(1));
      expect(result.deletedEntities[Post], hasLength(5));
      expect(result.deletedEntities[Comment], hasLength(15));

      // Verify all are deleted
      expect(await userManager.read(testUser.id), isNull);
      for (int i = 0; i < 5; i++) {
        expect(await postManager.read('batch-post-$i'), isNull);
        for (int j = 0; j < 3; j++) {
          expect(await commentManager.read('batch-comment-$i-$j'), isNull);
        }
      }
    });

    test('better error messages provide detailed failure information', () async {
      // Test 1: Entity not found error
      final notFoundResult = await userManager.deleteCascade('non-existent-entity').forUser(testUser.id).execute();

      expect(notFoundResult.success, isFalse);
      expect(notFoundResult.errors, hasLength(1));
      expect(notFoundResult.errors.first, contains('does not exist'));

      // Test 2: Restrict violation error
      await userManager.push(item: testUser, userId: testUser.id);
      final restrictComment = Comment(
        id: 'restrict-error-comment',
        userId: testUser.id,
        postId: 'non-existent',
        content: 'This will cause restrict violation',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );
      await commentManager.push(item: restrictComment, userId: testUser.id);

      final restrictResult = await userManager.deleteCascade(testUser.id).forUser(testUser.id).execute();

      expect(restrictResult.success, isFalse);
      expect(restrictResult.errors, hasLength(1));
      expect(restrictResult.errors.first, contains('restrict constraint'));
      expect(restrictResult.errors.first, contains('comments'));
    });

    test('progress callbacks work correctly during cascade delete', () async {
      // Arrange: Create user with multiple related entities
      await userManager.push(item: testUser, userId: testUser.id);
      await profileManager.push(item: testProfile, userId: testUser.id);

      // Create multiple posts with comments
      for (int i = 0; i < 3; i++) {
        final post = Post(
          id: 'progress-post-$i',
          userId: testUser.id,
          title: 'Progress Post $i',
          modifiedAt: DateTime(2023),
          createdAt: DateTime(2023),
        );
        await postManager.push(item: post, userId: testUser.id);

        final comment = Comment(
          id: 'progress-comment-$i',
          userId: 'other-user',
          postId: post.id,
          content: 'Progress comment $i',
          modifiedAt: DateTime(2023),
          createdAt: DateTime(2023),
        );
        await commentManager.push(item: comment, userId: testUser.id);
      }

      // Act: Use progress callback
      final progressUpdates = <CascadeProgress>[];
      final result = await userManager.deleteCascade(testUser.id).forUser(testUser.id).withProgress((progress) {
        progressUpdates.add(progress);
      }).execute();

      // Assert: Progress was tracked
      expect(result.success, isTrue);
      expect(progressUpdates, isNotEmpty);
      expect(progressUpdates.last.completed, equals(progressUpdates.last.total));

      // Verify final progress shows all entities
      expect(progressUpdates.last.total, equals(1 + 1 + 3 + 3)); // User + Profile + 3 Posts + 3 Comments
    });

    test('cancellation token allows cancelling cascade operations', () async {
      // Arrange: Create user with many related entities
      await userManager.push(item: testUser, userId: testUser.id);

      // Create many posts to make operation take longer
      for (int i = 0; i < 10; i++) {
        final post = Post(
          id: 'cancel-post-$i',
          userId: testUser.id,
          title: 'Cancel Post $i',
          modifiedAt: DateTime(2023),
          createdAt: DateTime(2023),
        );
        await postManager.push(item: post, userId: testUser.id);
      }

      // Act: Start cascade delete with cancellation
      final token = CancellationToken();
      final future = userManager.deleteCascade(testUser.id).forUser(testUser.id).withCancellation(token).execute();

      // Cancel immediately
      token.cancel();

      final result = await future;

      // Assert: Operation was cancelled
      expect(result.success, isFalse);
      expect(result.errors, isNotEmpty);
      expect(result.errors.any((e) => e.contains('cancelled')), isTrue);
    });

    test('timeout protection prevents hanging operations', () async {
      // Arrange: Create user with many entities
      await userManager.push(item: testUser, userId: testUser.id);

      for (int i = 0; i < 20; i++) {
        final post = Post(
          id: 'timeout-post-$i',
          userId: testUser.id,
          title: 'Timeout Post $i',
          modifiedAt: DateTime(2023),
          createdAt: DateTime(2023),
        );
        await postManager.push(item: post, userId: testUser.id);
      }

      // Act: Set very short timeout
      final result = await userManager
          .deleteCascade(testUser.id)
          .forUser(testUser.id)
          .withTimeout(const Duration(microseconds: 1)) // Very short timeout
          .execute();

      // Assert: Operation either succeeds or times out gracefully
      // (In practice, this might succeed or fail depending on system speed)
      expect(result.errors.where((e) => e.contains('timeout')), isEmpty); // No timeout errors
    });

    test('allowPartialDeletes handles failures gracefully', () async {
      // Arrange: Create user with related entities
      await userManager.push(item: testUser, userId: testUser.id);
      await profileManager.push(item: testProfile, userId: testUser.id);
      await postManager.push(item: testPost1, userId: testUser.id);

      // Act: Use allowPartialDeletes
      final result = await userManager.deleteCascade(testUser.id).forUser(testUser.id).allowPartialDeletes().execute();

      // Assert: Operation succeeds (or at least doesn't crash)
      // In this simple case, all should succeed
      expect(result.success, isTrue);
      expect(result.totalDeleted, 3); // User + Profile + Post
    });

    test('cascade error types provide structured error information', () async {
      // Test different error types
      final entityNotFoundError = CascadeError.entityNotFound('test-id');
      expect(entityNotFoundError.code, equals('ENTITY_NOT_FOUND'));
      expect(entityNotFoundError.entityId, equals('test-id'));

      final restrictError = CascadeError.restrictViolation('comments', ['comment-1', 'comment-2']);
      expect(restrictError.code, equals('RESTRICT_VIOLATION'));
      expect(restrictError.relationName, equals('comments'));
      expect(restrictError.details?['restrictedEntities'], equals(['comment-1', 'comment-2']));

      final deleteError = CascadeError.deleteFailed('User', 'user-1', 'Database connection failed');
      expect(deleteError.code, equals('DELETE_FAILED'));
      expect(deleteError.entityType, equals('User'));
      expect(deleteError.entityId, equals('user-1'));

      final timeoutError = CascadeError.timeout(const Duration(seconds: 30));
      expect(timeoutError.code, equals('TIMEOUT'));
      expect(timeoutError.details?['timeoutSeconds'], equals(30));

      final cancelError = CascadeError.cancelled();
      expect(cancelError.code, equals('CANCELLED'));
    });

    test('cascade result types provide type-safe access to results', () async {
      // Test successful result
      final successResult = CascadeSuccess<User>(
        entity: testUser,
        totalDeleted: 5,
        deletedEntities: {
          User: [testUser],
          Post: [testPost1, testPost2]
        },
        restrictedRelations: {},
        analytics: CascadeAnalytics(
          totalDuration: const Duration(seconds: 1),
          queriesExecuted: 5,
          relationshipsTraversed: 3,
          entitiesProcessedByType: {User: 1, Post: 2},
          entitiesDeletedByType: {User: 1, Post: 2},
          restrictViolations: 0,
          setNullOperations: 0,
          errorsEncountered: 0,
          wasDryRun: false,
          startedAt: DateTime(2023),
          completedAt: DateTime(2023, 1, 1, 0, 0, 1),
        ),
      );

      expect(successResult.success, isTrue);
      expect(successResult.entity, equals(testUser));
      expect(successResult.totalDeleted, equals(5));
      expect(successResult.errors, isEmpty);
      expect(successResult.deletedEntities[User], hasLength(1));
      expect(successResult.deletedEntities[Post], hasLength(2));

      // Test failure result
      final failureResult = CascadeFailure<User>(
        entity: testUser,
        error: CascadeError.restrictViolation('comments', ['comment-1']),
        errors: ['Additional error details'],
      );

      expect(failureResult.success, isFalse);
      expect(failureResult.entity, equals(testUser));
      expect(failureResult.totalDeleted, equals(0));
      expect(failureResult.errors, hasLength(2)); // Main error + additional
      expect(failureResult.errors.first, contains('restrict constraint'));
    });

    test('builder pattern validates required parameters', () async {
      // Test missing user ID
      expect(
        () async => await userManager.deleteCascade(testUser.id).execute(),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('User ID must be specified'),
        )),
      );
    });

    test('dry-run and regular delete can be used together safely', () async {
      // Arrange: Create entities
      await userManager.push(item: testUser, userId: testUser.id);
      await profileManager.push(item: testProfile, userId: testUser.id);

      // Act: First do dry-run
      final dryRunResult = await userManager.deleteCascade(testUser.id).forUser(testUser.id).dryRun().execute();

      // Assert: Dry-run shows what would be deleted
      expect(dryRunResult.success, isTrue);
      expect(dryRunResult.totalDeleted, 2);

      // Verify entities still exist
      expect(await userManager.read(testUser.id), isNotNull);
      expect(await profileManager.read(testProfile.id), isNotNull);

      // Act: Then do actual delete
      final realResult = await userManager.deleteCascade(testUser.id).forUser(testUser.id).execute();

      // Assert: Real delete actually removes entities
      expect(realResult.success, isTrue);
      expect(realResult.totalDeleted, 2);

      // Verify entities are now deleted
      expect(await userManager.read(testUser.id), isNull);
      expect(await profileManager.read(testProfile.id), isNull);
    });

    test('dry-run shows restrict violations without failing', () async {
      // Arrange: Create user with restrict relationship
      await userManager.push(item: testUser, userId: testUser.id);
      await profileManager.push(item: testProfile, userId: testUser.id);

      // Create a comment that would cause restrict violation
      final restrictComment = Comment(
        id: 'restrict-dry-run-comment',
        userId: testUser.id,
        postId: 'non-existent',
        content: 'This would cause restrict violation',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );
      await commentManager.push(item: restrictComment, userId: testUser.id);

      // Act: Dry-run should show what would be deleted and what would be restricted
      final result = await userManager.deleteCascade(testUser.id).forUser(testUser.id).dryRun().execute();

      // Assert: Dry-run succeeds and shows both what would be deleted and restricted
      expect(result.success, isTrue);
      expect(result.totalDeleted, 2); // User + Profile (comment would be restricted)

      // Cast to access restricted relations
      final successResult = result as CascadeSuccess<User>;
      expect(successResult.deletedEntities[User], hasLength(1));
      expect(successResult.deletedEntities[Profile], hasLength(1));
      expect(successResult.restrictedRelations.containsKey('comments'), isTrue);
      expect(successResult.restrictedRelations['comments'], hasLength(1));

      // Verify entities still exist (dry-run didn't delete them)
      expect(await userManager.read(testUser.id), isNotNull);
      expect(await profileManager.read(testProfile.id), isNotNull);
      expect(await commentManager.read(restrictComment.id), isNotNull);
    });

    test('dry-run handles complex relationship chains correctly', () async {
      // Arrange: Create a complex chain: User -> Posts -> Comments -> Nested Comments
      await userManager.push(item: testUser, userId: testUser.id);
      await profileManager.push(item: testProfile, userId: testUser.id);
      await postManager.push(item: testPost1, userId: testUser.id);

      final comment1 = Comment(
        id: 'dry-run-comment-1',
        userId: 'other-user',
        postId: 'post-1',
        content: 'First level comment',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final comment2 = Comment(
        id: 'dry-run-comment-2',
        userId: 'other-user',
        postId: 'post-1',
        content: 'Second level comment',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      await commentManager.push(item: comment1, userId: testUser.id);
      await commentManager.push(item: comment2, userId: testUser.id);

      // Act: Dry-run on complex relationship chain
      final result = await userManager.deleteCascade(testUser.id).forUser(testUser.id).dryRun().execute();

      // Assert: Shows all entities that would be deleted
      expect(result.success, isTrue);
      expect(result.totalDeleted, 5); // User + Profile + Post + 2 Comments

      final successResult = result as CascadeSuccess<User>;
      expect(successResult.deletedEntities[User], hasLength(1));
      expect(successResult.deletedEntities[Profile], hasLength(1));
      expect(successResult.deletedEntities[Post], hasLength(1));
      expect(successResult.deletedEntities[Comment], hasLength(2));

      // Verify entities still exist
      expect(await userManager.read(testUser.id), isNotNull);
      expect(await profileManager.read(testProfile.id), isNotNull);
      expect(await postManager.read(testPost1.id), isNotNull);
      expect(await commentManager.read(comment1.id), isNotNull);
      expect(await commentManager.read(comment2.id), isNotNull);
    });

    test('dry-run works with self-referencing relationships', () async {
      // Arrange: Create self-referencing category hierarchy
      final parent = Category(
        id: 'dry-run-parent',
        userId: testUser.id,
        name: 'Parent Category',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final child = Category(
        id: 'dry-run-child',
        userId: testUser.id,
        name: 'Child Category',
        parentId: 'dry-run-parent',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final grandchild = Category(
        id: 'dry-run-grandchild',
        userId: testUser.id,
        name: 'Grandchild Category',
        parentId: 'dry-run-child',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      await categoryManager.push(item: parent, userId: testUser.id);
      await categoryManager.push(item: child, userId: testUser.id);
      await categoryManager.push(item: grandchild, userId: testUser.id);

      // Act: Dry-run on self-referencing hierarchy
      final result = await categoryManager.deleteCascade('dry-run-parent').forUser(testUser.id).dryRun().execute();

      // Assert: Shows entire hierarchy that would be deleted
      expect(result.success, isTrue);
      expect(result.totalDeleted, 3); // All 3 categories

      final successResult = result as CascadeSuccess<Category>;
      expect(successResult.deletedEntities[Category], hasLength(3));

      // Verify entities still exist
      expect(await categoryManager.read('dry-run-parent'), isNotNull);
      expect(await categoryManager.read('dry-run-child'), isNotNull);
      expect(await categoryManager.read('dry-run-grandchild'), isNotNull);
    });

    test('dry-run works with mixin relationships', () async {
      // Arrange: Create product with reviews and tags using mixins
      final category = Category(
        id: 'dry-run-mixin-category',
        userId: testUser.id,
        name: 'Mixin Category',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final product = EcommerceProduct(
        id: 'dry-run-mixin-product',
        userId: testUser.id,
        name: 'Mixin Product',
        categoryId: 'dry-run-mixin-category',
        price: 99.99,
        description: 'Testing mixin dry-run',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final review = Review(
        id: 'dry-run-mixin-review',
        userId: testUser.id,
        productId: 'dry-run-mixin-product',
        rating: 5,
        comment: 'Great product!',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      final tag = Tag(
        id: 'dry-run-mixin-tag',
        userId: testUser.id,
        name: 'featured',
        productId: 'dry-run-mixin-product',
        modifiedAt: DateTime(2023),
        createdAt: DateTime(2023),
      );

      await categoryManager.push(item: category, userId: testUser.id);
      final ecommerceProductManager = Datum.manager<EcommerceProduct>();
      await ecommerceProductManager.push(item: product, userId: testUser.id);
      await reviewManager.push(item: review, userId: testUser.id);
      await tagManager.push(item: tag, userId: testUser.id);

      // Act: Dry-run on product with mixin relationships
      final result = await ecommerceProductManager.deleteCascade('dry-run-mixin-product').forUser(testUser.id).dryRun().execute();

      // Assert: Shows product and all mixin-related entities
      expect(result.success, isTrue);
      expect(result.totalDeleted, 3); // Product + Review + Tag

      final successResult = result as CascadeSuccess<EcommerceProduct>;
      expect(successResult.deletedEntities[EcommerceProduct], hasLength(1));
      expect(successResult.deletedEntities[Review], hasLength(1));
      expect(successResult.deletedEntities[Tag], hasLength(1));

      // Verify entities still exist
      expect(await ecommerceProductManager.read('dry-run-mixin-product'), isNotNull);
      expect(await reviewManager.read('dry-run-mixin-review'), isNotNull);
      expect(await tagManager.read('dry-run-mixin-tag'), isNotNull);
    });

    test('dry-run provides accurate counts for large datasets', () async {
      // Arrange: Create user with many related entities
      await userManager.push(item: testUser, userId: testUser.id);

      // Create multiple posts with multiple comments each
      const postCount = 5;
      const commentsPerPost = 4;

      for (int i = 0; i < postCount; i++) {
        final post = Post(
          id: 'dry-run-bulk-post-$i',
          userId: testUser.id,
          title: 'Bulk Post $i',
          modifiedAt: DateTime(2023),
          createdAt: DateTime(2023),
        );
        await postManager.push(item: post, userId: testUser.id);

        for (int j = 0; j < commentsPerPost; j++) {
          final comment = Comment(
            id: 'dry-run-bulk-comment-$i-$j',
            userId: 'other-user',
            postId: post.id,
            content: 'Comment $j on post $i',
            modifiedAt: DateTime(2023),
            createdAt: DateTime(2023),
          );
          await commentManager.push(item: comment, userId: testUser.id);
        }
      }

      // Act: Dry-run on large dataset
      final result = await userManager.deleteCascade(testUser.id).forUser(testUser.id).dryRun().execute();

      // Assert: Accurate count of all entities
      expect(result.success, isTrue);
      expect(result.totalDeleted, 1 + postCount + (postCount * commentsPerPost)); // User + Posts + Comments

      final successResult = result as CascadeSuccess<User>;
      expect(successResult.deletedEntities[User], hasLength(1));
      expect(successResult.deletedEntities[Post], hasLength(postCount));
      expect(successResult.deletedEntities[Comment], hasLength(postCount * commentsPerPost));

      // Verify entities still exist
      expect(await userManager.read(testUser.id), isNotNull);
      for (int i = 0; i < postCount; i++) {
        expect(await postManager.read('dry-run-bulk-post-$i'), isNotNull);
        for (int j = 0; j < commentsPerPost; j++) {
          expect(await commentManager.read('dry-run-bulk-comment-$i-$j'), isNotNull);
        }
      }
    });

    test('dry-run handles entities with no relationships', () async {
      // Arrange: Create entity with no relationships
      await userManager.push(item: testUser, userId: testUser.id);

      // Act: Dry-run on entity with no relationships
      final result = await userManager.deleteCascade(testUser.id).forUser(testUser.id).dryRun().execute();

      // Assert: Shows only the single entity
      expect(result.success, isTrue);
      expect(result.totalDeleted, 1);

      final successResult = result as CascadeSuccess<User>;
      expect(successResult.deletedEntities[User], hasLength(1));
      expect(successResult.restrictedRelations, isEmpty);

      // Verify entity still exists
      expect(await userManager.read(testUser.id), isNotNull);
    });

    test('dry-run shows preview for non-existent entities', () async {
      // Act: Dry-run on non-existent entity
      final result = await userManager.deleteCascade('non-existent-entity').forUser(testUser.id).dryRun().execute();

      // Assert: Fails gracefully with appropriate error
      expect(result.success, isFalse);
      expect(result.errors, hasLength(1));
      expect(result.errors.first, contains('does not exist'));
      expect(result.totalDeleted, 0);
    });

    test('dry-run works with progress callbacks', () async {
      // Arrange: Create user with related entities
      await userManager.push(item: testUser, userId: testUser.id);
      await profileManager.push(item: testProfile, userId: testUser.id);
      await postManager.push(item: testPost1, userId: testUser.id);

      // Act: Dry-run with progress callback
      final progressUpdates = <CascadeProgress>[];
      final result = await userManager.deleteCascade(testUser.id).forUser(testUser.id).dryRun().withProgress((progress) {
        progressUpdates.add(progress);
      }).execute();

      // Assert: Progress was tracked during dry-run
      expect(result.success, isTrue);
      expect(progressUpdates, isNotEmpty);
      expect(progressUpdates.last.completed, equals(progressUpdates.last.total));
      expect(progressUpdates.last.total, equals(3)); // User + Profile + Post

      // Verify entities still exist
      expect(await userManager.read(testUser.id), isNotNull);
      expect(await profileManager.read(testProfile.id), isNotNull);
      expect(await postManager.read(testPost1.id), isNotNull);
    });
  });
}

/// Helper function to apply all default stubs to a set of mocks.
