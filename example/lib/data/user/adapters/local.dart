import 'package:example/data/task/adapters/hive_local_adapter.dart';
import 'package:example/data/user/entity/user.dart';

/// A concrete implementation of `HiveLocalAdapter` for the `UserEntity` entity.
///
/// This class now extends the generic `HiveLocalAdapter`, providing only the
/// specific information needed for the `UserEntity` entity.
class UserLocalAdapter extends HiveLocalAdapter<UserEntity> {
  UserLocalAdapter()
      : super(
          entityBoxName: 'users',
          fromMap: UserEntity.fromMap,
        );
}
